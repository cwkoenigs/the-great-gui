# Team tooling: to implement

Status: **part 1 is built** (2026-11-11 and 12, `DECISIONS.md` local-027 and local-028): the shared registry
with commands, secret checklists, skills and tool installs. All of part 2 is not.
`DECISIONS.md` local-022 points at this file.

## What the-great-gui is for

In Clark's words, on 2026-11-11:

- **Agents will use it a lot.** The command line, the skills and the output are designed for agents
  first; the window is a person's view of the same thing.
- **A safe spot for people to store secrets.** Each person's own, in their own Keychain.
- **A secure way to interact with their machine.**
- **The way we push our tooling to them.**

All four exist in some form. The fourth is the team's registry below; before it an update delivered
the app and its skills, and nothing else.

## What is to be built

### 1 · A shared team registry

A second registry beside each person's own, read-only in their window, that the team maintains and every
install receives.

Decided:

- **A clash of names: the personal command wins**, and the window marks it as overriding the team's.
  People can adapt a team command without breaking updates.
- **Delivery is automatic, daily.** The daily look (local-021) also brings in new team entries, since
  they are text. The window says what changed. An app update still waits for a click.
- **A push can carry four things:**
  1. **Commands**: shared `[[command]]` entries.
  2. **Secret checklists**: the names of the secrets and the `[[file]]` pointers the team's commands
     need, so each person's Secrets screen shows what to store. Never a value.
  3. **Agent skills**: linked into each person's Claude Code, Codex, Hermes and Cortex Code beside
     `add-command` and `use-secret`.
  4. **Tool installs**: a list of tools to install and keep current. This is what the separate
     `updater` project (`cwkoenigs/update-gui`) did; it is folded in here as `[[tool]]` entries (local-028),
     so `updater` and its secrets code, built there by mistake on 2026-11-10, can be retired.

Decided on 2026-11-11 and built:

- **Where the team registry lives: a separate team repository**, cloned to `~/.great-gui-team`, so
  tooling changes without an app rebuild. Clark agreed "as long as this can easily be ported to my work
  computer", so the app names no host: `great-gui team join ADDRESS` takes any git address and the
  clone's remote is the only record of it. `great-gui team init DIR` starts such a repository.
- **A team schedule is held back** (the agent's choice, for Clark to confirm): automatic delivery plus a
  schedule would run a pushed command unattended on every Mac. It shows as a suggestion; a person's own
  copy arms it.
- **A push is checked before it is taken**: a `commands.toml` that does not load stays on the remote.

Decided on 2026-11-12 and built (local-028):

- **A pushed tool is installed on a click**, never by the sync: it shows as missing until the person
  presses Install or their agent runs `great-gui tools install`. The same rule as a team schedule.
- **Four methods at first**: `brew`, `cask`, `uv` and `script`. pipx, pip, npm, cargo and go followed the
  same day (local-030).
- **Tools are personal too**: `[[tool]]` works in a person's own file, and theirs wins a clash of names.
- **Updates are reported, and applied on a click**: the daily look asks Homebrew and uv what is behind.

Built: commands, secret checklists (the Secrets screen and `great-gui team` list what is missing),
agent skills, tool installs, and saying what changed in a team command after a sync (local-030).

Still to do on each Mac that should use it: create the team repository on a git host that Mac can
reach, and join it. At work that host is the company's own, not GitHub: `make mirror TO=ADDRESS` carries
the app there (local-031), and the team repository is pushed there with plain git.

### 2 · Registered installs, targeted pushes, data back

Clark wants to push a command to one specific person, and to have installs register and report back so
that pushes can be targeted.

Decided:

- **What an install reports**, all four:
  1. **Install facts**: who, which Mac, app version, macOS version, last seen.
  2. **Tool inventory**: which team tools are installed, at what version.
  3. **Team command runs**: for team commands only, when each ran, its exit code and duration.
  4. **Secret checklist status**: for the secrets the team's commands need, stored or missing, by name.
- **What an install never reports**, under any design: a secret's value, a command's output, a personal
  command or anything about one, the contents of any file.
- **Consent: shown, and on by default.** First launch explains what is reported; a Settings page shows
  the exact data sent, with a switch to turn it off.

Open, and deliberately left to implement:

- **The hub: where installs register and report to.** Three candidates, none chosen:
  - **Git only.** The team repository is the hub: an install registers by committing a small file about
    itself, and a command names who it is for. No service to run or have approved; teammates need push
    access, and data arrives when they sync.
  - **A small web service.** An API and a database that installs call daily. A live view of every install
    and immediate targeting; a service to secure and host, and work Macs would send data to it, which
    the company may need to approve.
  - **Snowflake at work.** Installs report into a table through each person's own connection. Stays
    inside company systems; only for people with Snowflake access, and slower to build.
- **Identity.** What names a person and an install (a chosen name, a GitHub login, a work email), and
  how a targeted entry is addressed to them.
- **Whether a targeted push is a secret from the others.** In a git hub every teammate can read every
  targeted entry.

### 3 · Around it

- **Every command readable by an agent**: done on 2026-11-11 and 12 (local-023, local-029). `--json` on
  every command but `path`, `version` and `help`, errors as JSON, one set of exit codes. `run`, `exec` and
  `tools install|update` send the command's own output to stderr and print a result object on stdout.
- **The trust model for agents**: decided on 2026-11-11 (local-024). Any agent can use any stored secret
  with no approval. `great-gui history` is the record of what agents did.

## Rules that hold whatever is built

- **Secret values never leave the Mac they were stored on.** No export, import, sync or cloud backend.
  A team push carries names and pointers only.
- **A team push is read-only on arrival** and never edits a person's own registry.
- **Reporting is visible.** Nothing is sent that Settings does not show.
