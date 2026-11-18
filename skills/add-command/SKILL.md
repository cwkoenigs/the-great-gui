---
name: add-command
description: Interview the user about a terminal command they want in the-great-gui (their native Mac command manager) and add it with `great-gui add`, or change or remove one with `great-gui edit` and `great-gui remove`. Use when the user says "add a command", "add X to the great gui", "put X in my commands", "fix the description of X", "remove X from my commands", "/add-command", or wants a command they keep typing to live in the window. Works the same in Claude Code, Codex and Cortex Code; it only needs a shell.
---

# add-command

the-great-gui keeps one registry of commands in `~/.great-gui/commands.toml` and runs them from a
window: plain ones with their output on the rail, interactive ones in an embedded terminal, with
Keychain secrets and Touch ID gating. This skill gets one command into that registry: interview the
user in chat, show the exact command you will run, then run `great-gui add` with flags.
**Never hand-edit the TOML file**, and never ask for or handle a secret's value: values go in through
⌘K in the window, by the user.

## Before you start

```bash
great-gui version        # must work; if not, see "great-gui missing" below
great-gui list           # the names in use (avoid duplicates) and the groups that exist
great-gui list --json    # the same as data; great-gui show NAME --json for one command in full
                         # add, edit and remove take --json too and answer with the command as it now is
```

`great-gui missing`: try `~/.local/bin/great-gui version`. If that works, `~/.local/bin` is not on
PATH: tell the user (the installer offers to add it). If it does not, the app is not installed: run
`make install` in its checkout, which builds the app and links `great-gui` into `~/.local/bin`.

## Interview: one question at a time, in plain chat

Ask only what you cannot derive. Offer a recommended answer with each question.

1. **The command line.** What exactly do they type? That is `--run`. If a part of it changes each
   time (a path, a name, a number), make it a parameter: `{name}` in the run line and
   `--param name:description=default` (append `!` when it is required). Values are shell-quoted
   when substituted, so the user never quotes them.
2. **Name and group.** A short lowercase `NAME` (digits, `.` `_` `-` allowed), unique in
   `great-gui list`; a `--group` from the existing groups unless a new one is clearly right; a
   one-line `--desc` in the user's words, lowercase, no trailing period.
3. **Where it runs.** `--cwd` only when the command cares (a repository, a project). `~` is fine.
4. **Does it need a terminal?** A program that draws a UI, asks questions or reads keys needs
   `--interactive`: it runs in the embedded terminal. Something that just prints does not.
5. **Secrets and gating.** If the command needs a token or key, pass it as an environment variable
   from the Keychain: `--env NAME=keychain:secret-name`. Tell the user to add the value with ⌘K in
   the window; do not ask what it is. If it reads a whole `.env`, keep that file in the Keychain and
   pass it as `--env-file keychain:NAME`: its entries join the environment and the file never touches
   the disk. `great-gui file add NAME --path ~/project/.env` stores it, and the user runs that
   themselves, since it reads their credentials; never read, print or copy the file's contents. If the command is one they would not want run by accident
   (deploys, deletes, money), suggest `--gate`: Touch ID or the password before each run.
6. **Should it run on its own?** If they want it to happen without asking (a morning check, a sync),
   `--schedule "weekdays 08:30"`: the phrases are `every 15m`, `hourly`, `daily 09:00`,
   `weekdays 08:30`, `weekends 10:00`, `mon,thu 18:00`, `monthly 1 07:00`. launchd runs it with the
   window closed and its output goes to a log the window shows. A gated or interactive command cannot
   be scheduled, nor one with a parameter that has no default; `great-gui` says so.
7. **Confirm.** Print the complete `great-gui add …` command in a code block and ask for a yes.

## Run it

```bash
great-gui add caffeinate --group mac --desc "keep the Mac awake until stopped" --run "caffeinate -dimsu"
```

`great-gui add` validates like the window does and appends one block to the file; when
`~/.great-gui` is a git repository it commits the change (never pushes). The window reloads on its
own. On `✗`, read the line under it: it names the fix.

## Changing or removing one later

`great-gui edit NAME` takes the same flags as `add`; a flag given replaces that field and the rest
stays. `--name NEW` renames; `--no-interactive`, `--no-gate`, `--clear-tags`, `--clear-env` and
`--clear-params` and `--clear-schedule` turn things off. `great-gui remove NAME` takes a command out.
`great-gui schedule` lists what runs on its own; `great-gui pause NAME` and `resume NAME` hold and release
one without changing the file. Both rewrite only that
command's block, keep the rest of the file and commit (`edit NAME`, `rename A to B`, `remove NAME`).
As with add: show the exact command, ask for a yes, then run it. In the window the same is ⌘E and ⌘⌫.

```bash
great-gui edit caffeinate --desc "keep the Mac awake until stopped (Esc stops it)"
great-gui remove caffeinate
```

## After

Tell the user, in one line each: type the name in the window's filter and press Enter; how to stop
it if it runs until stopped (Esc or ⌘.); and, if there is a secret, to add it with ⌘K first.
