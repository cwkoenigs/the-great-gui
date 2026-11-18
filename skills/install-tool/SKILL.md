---
name: install-tool
description: Check, install, update or list the programs a Mac should have (command-line tools, apps, Python and npm packages) through the-great-gui's tool list. Use when the user says "install X", "is X installed", "update my tools", "what is out of date", "add X to my tools", "set up this Mac", "the team says I need X", or when a command you are about to run is missing a program that the-great-gui lists. Works the same in Claude Code, Codex, Hermes and Cortex Code; it only needs a shell.
---

# install-tool

the-great-gui keeps a list of the programs this Mac should have: the person's own, and the ones their
team pushed. Each entry says how the tool is installed. `great-gui tools` reads the list and runs the
installs. Nothing on the list installs by itself: it happens when the person asks, or when you do on
their behalf.

## Look first

```bash
great-gui tools --json            # every listed tool: installed, version, missing; exit 1 when one is missing
great-gui tools --check --json    # the same, and which are behind (slower: it asks the package managers)
```

Each tool carries the exact shell lines an install or an update would run (`install`, `update`), whose
it is (`origin`: `personal` or `team`), and what this Mac has (`installed`, `version`, `outdated`).

## Install and update

```bash
great-gui tools install --json            # everything that is missing
great-gui tools install ripgrep jq --json # only these
great-gui tools update --json             # everything a package manager says is behind
great-gui tools update uv --json          # this one, whatever its state
```

With `--json` the installer's own output goes to stderr and stdout is one object:
`{"ok", "results": [{"name", "code", "seconds", "line"}], "skipped", "failed"}`. Exit 0 when all of them
worked, 1 when one failed.

Before you install:

- **Say what will run.** Read the tool's `install` line from `great-gui tools --json` and tell the user
  which tools you are about to install. For a tool whose `method` is `script`, show them the line itself:
  it is a shell command, often one that downloads and runs an installer.
- **A team tool is the team's word, not the user's.** If `origin` is `team` and the user did not ask for
  that tool by name, ask before installing it.
- **An installer may ask for a password** (Homebrew casks do). You cannot answer it. If an install fails
  for that reason, tell the user to press Install on the Tools screen (⌘U in the app), which runs in a
  terminal they can type into.
- A tool marked `elsewhere` is on PATH but was not installed by its package manager. Leave it alone.

## Add a tool to the list

Ask what the tool is and how it is installed, then:

```bash
great-gui tools methods                                    # every method and the lines it derives
great-gui tools add ripgrep --method brew --bin rg --desc "fast search"
great-gui tools add ruff --method uv --requires uv
great-gui tools add uv --method script --install "curl -LsSf https://astral.sh/uv/install.sh | sh" --update "uv self update"
great-gui tools remove ripgrep                             # off the list; nothing is uninstalled
```

Methods: `brew`, `cask`, `uv`, `pipx`, `pip`, `npm`, `cargo`, `go`, `script`. Use `--pkg` when the
package manager's name differs from the tool's, and `--bin` for the program it puts on PATH. Adding
installs nothing; say so, and offer `great-gui tools install NAME`.

You can only add to and remove from the person's own list. A team tool is read-only here: to use a
different version, add a tool of the same name, which wins.

## Do not

- Do not run `brew install`, `uv tool install`, `npm install -g` and the like yourself for a tool that is
  on the list: go through `great-gui tools`, so the run is recorded in `great-gui history`.
- Do not edit the team's folder (`~/.great-gui-team`).
- Do not install everything a sync brought without telling the user what it is.
