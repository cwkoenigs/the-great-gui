---
name: use-secret
description: Use a key, token, password, connection string or credential file that the user keeps in the-great-gui's Keychain store, without ever seeing or handling its value. Use when the user says "use key X to connect to Y", "use my snowflake / postgres / gitlab / aws credentials", "the token is in the great gui", "run this with my API key", when a command you are about to run needs a credential, or when you are tempted to ask the user to paste a secret, read a .env, or export a token. Works the same in Claude Code, Codex, Hermes and Cortex Code; it only needs a shell.
---

# use-secret

The user's credentials live in the macOS Keychain, managed by the-great-gui. You refer to one **by
name**; `great-gui` hands its value to the command you run, in that command's environment only, and
masks it in the output. You never see the value, and it never lands in the chat, a file, your shell's
environment or a command line.

## The three rules

1. **Never ask for a value, and never accept one.** If the user starts to paste a key, stop them and
   point at the window instead (below). A value in the chat is a leaked value.
2. **Never try to read one.** No `echo $KEY`, `env`, `printenv`, `set`, `cat` of a credential file,
   `security find-generic-password`, or writing the variable to a file. Output is masked, but masking is
   a safety net, not permission.
3. **Never put a value on a command line or in a file you write.** Refer to the environment variable
   inside the command (`"$DATABASE_URL"`), in single quotes so *your* shell does not expand it.

## 1 · See what is stored

```bash
great-gui secrets            # names only: secrets and credential files, and which commands use them
great-gui secrets --json     # the same, to parse
```

`great-gui list --json` and `great-gui show NAME --json` tell you which registered commands already
use a secret, and how to run them (`runnable_from_cli`, `params`). Prefer a command that exists over a
new `exec`.

Pick the name that matches what the user said. If two could fit, ask which. If nothing fits, the
secret is not stored yet: see "It is missing" below.

## 2 · Run with it

One-off, nothing added to the registry:

```bash
great-gui exec --env DATABASE_URL=keychain:db-prod-url -- 'psql "$DATABASE_URL" -c "select count(*) from orders"'
```

- `--env KEY=keychain:NAME` gives the command the secret `NAME` as the variable `KEY`. Repeat it for
  several. Use the variable name the tool expects: `PGPASSWORD`, `SNOWFLAKE_PASSWORD`, `GITLAB_TOKEN`,
  `AWS_SECRET_ACCESS_KEY`, `ANTHROPIC_API_KEY`.
- `--env-file keychain:NAME` gives it every `KEY=value` of a whole stored `.env`.
- `--cwd DIR` runs it in a folder. `--env KEY=plain` (no `keychain:`) sets an ordinary value.
- Everything after `--` is the command. Pass it as **one single-quoted string** when it contains `$VAR`,
  pipes or quotes, so the variable is expanded inside the run and not by your shell.
- The exit code is the command's. A masked value shows as `•••••`.

More shapes:

```bash
# a script that reads its settings from the environment
great-gui exec --env-file keychain:my-project-env --cwd ~/Developer/my-project -- uv run report.py

# an API call
great-gui exec --env TOKEN=keychain:gitlab-token -- 'curl -sf -H "PRIVATE-TOKEN: $TOKEN" https://gitlab.com/api/v4/user'

# two secrets at once
great-gui exec --env PGUSER=keychain:db-user --env PGPASSWORD=keychain:db-password -- psql -h db.internal -d app -c 'select 1'
```

**A tool that reads a file at a fixed path** (Snowflake's `~/.snowflake/connections.toml`, `~/.aws/credentials`):
the file itself is what is stored. Check it is in place, and restore it if not; then run the tool normally.

```bash
great-gui file                         # each credential file: in sync, not on this Mac, differs…
great-gui file restore snowflake-connections
snow sql -q "select current_user()"    # the tool finds its file as usual
```

Do not open, print or copy a restored file. If `great-gui file` says a file **differs**, tell the user
and ask before `restore --force`: it overwrites their file.

**If the user will want it again**, make it a command they can also click, with `great-gui add`
(the `add-command` skill): `--env KEY=keychain:NAME` or `--env-file keychain:NAME`, then
`great-gui run NAME`. Its output is masked the same way.

## It is missing

`✗ … needs the secret NAME, which is not in the Keychain` means the user has not stored it on this Mac.
Say so and tell them how; do not offer to take the value:

- One value: open the-great-gui, Secrets, **Add secret**, name it `NAME`.
- A whole file: Secrets, **Add file**; or they run `great-gui file add NAME --path ~/project/.env`
  themselves, since it reads their credentials.

Then run your command again. A secret never comes from another Mac or a teammate: each person stores
their own.

## Reading answers

Every command but `path`, `version` and `help` takes `--json` and prints one JSON object on stdout; an
error is `{"ok": false, "error": "…", "fix": "…"}`, and `fix` says what to do. With `--json`, `run NAME`
and `exec` (put `--json` before the `--`) send the command's own output to stderr, still masked, and
print `{"ok", "code", "seconds", "secrets"}` when it ends. Add `--capture` (for `exec`, before the `--`) to
get what the command printed in the same object, as `output`: still masked, stdout and stderr in order,
the newest 64 KB, with `output_truncated` when the front was cut.
Exit codes: `0` fine, `1` something is not as it should be (a file out of sync), `2` the request was
wrong or refused, `10` an update is waiting; `run` and `exec` return the command's own.
`great-gui history --json` is the record of what ran, `exec` runs included, with the secret names used.

## If something goes wrong

- `great-gui: command not found`: try `~/.local/bin/great-gui version`. If that works, `~/.local/bin` is not on PATH: tell the user (the installer offers to add it). If it does not, the app is not installed: `make install` in its checkout.
- A Keychain dialog appears: the user clicks Always Allow. You cannot answer it.
- `✗ … is gated`: that command asks for Touch ID and only runs from the window. Tell the user.
- The output is all `•••••`: the command printed the secret. That is the mask working; fix the command
  so it does not print it, and do not look for a way around it.
