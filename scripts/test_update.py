"""Exercise the same update entry point as the app, against disposable Git clones."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


SCRIPTS = Path(__file__).resolve().parent


class UpdateTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.env = dict(PATH=os.environ["PATH"], HOME=temp.name, GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_CONFIG_NOSYSTEM="1", GREAT_GUI_UPDATE_FROM_APP="1")
        self.origin = self.root / "upstream"
        self.origin.mkdir()
        self.git(self.origin, "init", "-qb", "main")
        self.git(self.origin, "config", "user.name", "Update Test")
        self.git(self.origin, "config", "user.email", "test@example.invalid")
        (self.origin / "scripts").mkdir()
        for name in ("update.sh", "update_checkout.py"):
            shutil.copy2(SCRIPTS / name, self.origin / "scripts")
        (self.origin / "Makefile").write_text("install:\n\t@touch built\n")
        self.base = "title\n" + "context\n" * 12 + "footer\n"
        (self.origin / "guide").write_text(self.base)
        (self.origin / "notes").write_text("old\n")
        self.git(self.origin, "add", ".")
        self.git(self.origin, "commit", "-qm", "base")
        self.repo = self.root / "demo"
        self.git(self.root, "clone", "-q", str(self.origin), str(self.repo))
        self.preview = self.base.replace("title", "published title")
        (self.origin / "guide").write_text(self.preview)
        (self.origin / "new page").write_text("published\n")
        (self.origin / "other incoming").write_text("remote only\n")
        self.git(self.origin, "add", ".")
        self.git(self.origin, "commit", "-qm", "publish preview")

    def git(self, cwd, *args):
        return subprocess.check_output(["git", *args], cwd=cwd, env=self.env)

    def update(self):
        return subprocess.run(["sh", "scripts/update.sh"], cwd=self.repo, env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def test_update_keeps_local_edits_and_staging(self):
        mixed = self.preview.replace("footer", "local footer")
        (self.repo / "guide").write_text(mixed)
        (self.repo / "new page").write_text("published\n")
        (self.repo / "notes").write_text("staged\n")
        self.git(self.repo, "add", "notes")
        (self.repo / "notes").write_text("unstaged\n")
        (self.repo / "scratch").write_text("private notes\n")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), self.git(self.origin, "rev-parse", "HEAD"))
        self.assertEqual((self.repo / "guide").read_text(), mixed)
        self.assertEqual(self.git(self.repo, "show", ":guide").decode(), self.preview)
        self.assertEqual(self.git(self.repo, "show", ":notes"), b"staged\n")
        self.assertEqual((self.repo / "notes").read_text(), "unstaged\n")
        self.assertEqual((self.repo / "scratch").read_text(), "private notes\n")
        self.assertEqual((self.repo / "other incoming").read_text(), "remote only\n")
        self.assertTrue((self.repo / "built").exists())
        self.assertEqual(self.update().returncode, 0)

    def test_staged_and_unstaged_edits_in_preview_file(self):
        staged = self.base.replace("footer", "staged footer")
        (self.repo / "guide").write_text(staged)
        self.git(self.repo, "add", "guide")
        local = self.preview.replace("footer", "working footer")
        (self.repo / "guide").write_text(local)
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.git(self.repo, "show", ":guide").decode(),
                         self.preview.replace("footer", "staged footer"))
        self.assertEqual((self.repo / "guide").read_text(), local)

    def test_hook_staging_and_interrupted_merge(self):
        # Interrupt the merge after HEAD advances, while a real post-merge hook is running.
        (self.repo / "new page").write_text("published\n")
        staged = self.base.replace("footer", "staged footer")
        (self.repo / "guide").write_text(staged)
        self.git(self.repo, "add", "guide")
        (self.repo / "guide").write_text(self.preview.replace("footer", "working footer"))
        hook = self.repo / ".git/hooks/post-merge"
        hook.write_text("#!/bin/sh\necho staged > review\ngit add review || exit 1\n"
                        "echo working > review\ntouch hook-started\nsleep 30\n")
        hook.chmod(0o755)
        with subprocess.Popen(["sh", "scripts/update.sh"], cwd=self.repo, env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              start_new_session=True) as process:
            try:
                deadline = time.monotonic() + 10
                while not (self.repo / "hook-started").exists():
                    if process.poll() is not None or time.monotonic() > deadline:
                        self.fail("The post-merge hook did not start")
                    time.sleep(0.05)
                os.killpg(process.pid, signal.SIGINT)
                process.communicate(timeout=10)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), self.git(self.origin, "rev-parse", "HEAD"))
        self.assertEqual(self.git(self.repo, "show", ":review"), b"staged\n")
        self.assertEqual((self.repo / "review").read_text(), "working\n")
        self.assertEqual(self.git(self.repo, "show", ":guide").decode(), self.preview.replace("footer", "staged footer"))
        self.assertFalse((self.repo / ".git/index.lock").exists())
        self.assertEqual(self.update().returncode, 0)

    def test_refuses_divergence_and_busy_index(self):
        self.git(self.repo, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "commit", "--allow-empty", "-qm", "local history")
        (self.repo / "guide").write_text(self.preview)
        for busy in (False, True):
            with self.subTest(busy=busy):
                if busy:
                    (self.repo / ".git/index.lock").write_bytes(b"another Git writer")
                before = self.git(self.repo, "rev-parse", "HEAD")
                self.assertNotEqual(self.update().returncode, 0)
                self.assertEqual(before, self.git(self.repo, "rev-parse", "HEAD"))
                self.assertEqual((self.repo / "guide").read_text(), self.preview)
                self.assertFalse((self.repo / "built").exists())
                if busy:
                    self.assertEqual((self.repo / ".git/index.lock").read_bytes(), b"another Git writer")

    def test_conflict_and_untracked_collision_leave_checkout_intact(self):
        for local, new in [(self.preview, "different new file\n"), ("conflicting title\n", "published\n")]:
            with self.subTest(local=local[:8]):
                (self.repo / "guide").write_text(local)
                (self.repo / "new page").write_text(new)
                (self.repo / "notes").write_text("staged\n")
                self.git(self.repo, "add", "notes")
                before = [self.git(self.repo, *args) for args in [("rev-parse", "HEAD"), ("write-tree",)]]
                result = self.update()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(before, [self.git(self.repo, *args) for args in [("rev-parse", "HEAD"), ("write-tree",)]])
                self.assertEqual((self.repo / "guide").read_text(), local)
                self.assertEqual((self.repo / "new page").read_text(), new)
                self.assertFalse((self.repo / "built").exists())
                self.assertFalse((self.repo / "other incoming").exists())


if __name__ == "__main__":
    unittest.main()
