"""Fast-forward the tracked branch, recognizing a preview already present on disk."""
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile


def git(*args, env=None, data=None):
    return subprocess.check_output(["git", *args], env=env, input=data)


def reconcile(local, base, incoming, scratch):
    """Git's three-way result, or None when the texts conflict."""
    if local == incoming or local == base:
        return incoming
    if base is None or b"\0" in local or b"\0" in base or b"\0" in incoming:
        return None
    paths = [scratch / name for name in ("local", "base", "incoming")]
    for path, content in zip(paths, (local, base, incoming)):
        path.write_bytes(content)
    merge = subprocess.run(["git", "merge-file", "-p", *paths], stdout=subprocess.PIPE)
    return merge.stdout if merge.returncode == 0 else None


def staged_entries(env=None):
    entries = {}
    for record in git("ls-files", "--stage", "-z", env=env).split(b"\0")[:-1]:
        meta, name = record.split(b"\t", 1)
        mode, oid, stage = meta.split()
        if stage != b"0":
            raise SystemExit("Resolve the existing index conflict before updating.")
        entries[name] = (mode, oid)
    return entries


def set_entries(entries, env):
    if entries:
        data = b"".join(mode + b" " + oid + b"\t" + name + b"\0"
                        for name, (mode, oid) in entries.items())
        git("update-index", "-z", "--index-info", env=env, data=data)


def preview_entries(before, target, scratch):
    """Return published entries and any additional edits that should stay staged."""
    staged = staged_entries()
    dirty = set(git("diff-files", "--name-only", "-z").split(b"\0"))
    raw = git("diff", "--raw", "--no-abbrev", "--no-renames", "-z", before, target).split(b"\0")
    align, keep = {}, {}
    for meta, name in zip(raw[0::2], raw[1::2]):
        oldmode, mode, oldoid, oid, _ = meta[1:].split()
        added = oldmode == b"000000"
        entry = staged.get(name)
        if mode not in (b"100644", b"100755") or entry == (mode, oid):
            continue
        if not added and name not in dirty and entry == (oldmode, oldoid):
            continue
        path = Path(os.fsdecode(name))
        if path.absolute() != path.resolve() or not path.is_file():
            continue
        perms = path.stat().st_mode
        if not stat.S_ISREG(perms):
            continue
        if mode != oldmode and bool(perms & stat.S_IXUSR) != (mode == b"100755"):
            continue
        if not added and (oldmode not in (b"100644", b"100755") or entry is None):
            continue

        incoming = git("cat-file", "blob", oid)
        base = None if added else git("cat-file", "blob", oldoid)
        local = path.read_bytes()
        if reconcile(local, base, incoming, scratch) != local:
            continue

        # Preserve the index and working copy independently when both have edits.
        if entry and entry != (oldmode, oldoid):
            if added or entry[0] not in (b"100644", b"100755"):
                continue
            merged = reconcile(git("cat-file", "blob", entry[1]), base, incoming, scratch)
            if merged is None:
                continue
            staged_mode = mode if entry[0] == oldmode else entry[0]
            if merged != incoming or staged_mode != mode:
                blob = git("hash-object", "-w", "--stdin", data=merged).strip()
                keep[name] = staged_mode, blob
        align[name] = mode, oid
    return align, keep


def fast_forward():
    before = git("rev-parse", "--verify", "HEAD").strip()
    target = git("rev-parse", "--verify", "@{upstream}^{commit}").strip()
    merge = ["git", "merge", "--ff-only", "--no-autostash", "--no-overwrite-ignore", target]
    index = Path(os.fsdecode(git("rev-parse", "--git-path", "index").rstrip(b"\n"))).absolute()
    lock = index.with_name(index.name + ".lock")
    if lock.exists():
        raise SystemExit(f"Git's index is locked at {lock}. Finish or recover the interrupted Git operation before updating.")
    ordinary = subprocess.run(merge, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if ordinary.returncode == 0:
        sys.stdout.buffer.write(ordinary.stdout)
        return
    # A divergent history or an unrelated Git error belongs to the normal merge.
    if subprocess.run(["git", "merge-base", "--is-ancestor", before, target]).returncode != 0:
        sys.stderr.buffer.write(ordinary.stdout)
        raise SystemExit(ordinary.returncode)

    # Reserve Git's own lock and let the native fast-forward operate on a copy of
    # the index there. Git still checks every other path and runs the checkout's hooks.
    with tempfile.TemporaryDirectory(dir=index.parent, prefix="preview-") as directory:
        lock.touch(mode=0o600, exist_ok=False)
        advanced = False
        try:
            if git("rev-parse", "HEAD").strip() != before:
                raise SystemExit("The checkout changed during Update. Run Update again.")
            align, keep = preview_entries(before, target, Path(directory))
            if not align:
                sys.stderr.buffer.write(ordinary.stdout)
                raise SystemExit(ordinary.returncode)
            shutil.copy2(index, lock)
            env = dict(os.environ, GIT_INDEX_FILE=str(lock))
            set_entries(align, env)
            try:
                subprocess.run(merge, env=env, check=True)
            finally:
                # A signal or failing hook can arrive after Git moved the branch.
                # Publish Git's actual result even then. Keep its hook-staged files.
                advanced = git("rev-parse", "HEAD").strip() == target
                if advanced:
                    if keep:
                        current = staged_entries(env)
                        set_entries({name: entry for name, entry in keep.items()
                                     if current.get(name) == align[name]}, env)
                    os.replace(lock, index)
        finally:
            if not advanced:
                lock.unlink(missing_ok=True)
        print(f"  recognized {len(align)} published preview file(s); kept local edits")


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        fast_forward()
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"Could not update the checkout: {error}")
