# Where it is weak

Nov 13, 2026 · tip `d94ef47` · reviewed as someone about to give it to twenty teammates. Nothing was fixed.

- **How bad:** `blocks` = sort it out before handing it out · `fix` = should fix · `nice` = nice to have.
- **Verified** = I ran it in the throwaway instance or saw it on screen (`LOG.md` has the output). **Inferred** = read in the code, by me or by a read-only sub-agent, with the file and line given; not run.
- The command-line defects B1 to B7 and the on-screen list are described in full in `WORKS.md`; they have rows here so the plan can rank them.

## The ones that block handing it out

| id | name | area | how bad | how I know | |
| --- | --- | --- | --- | --- | --- |
| F01 | The build needs github.com: `Package.swift` and `Package.resolved` name five packages there (TOMLKit, SwiftTerm and three they pull in). `make mirror` carries the app only. A work Mac that cannot reach GitHub cannot build or update. | install | blocks | `grep url: Package.swift`, `Package.resolved` | verified (the files); the failure on a blocked network is inferred |
| F02 | Team skills go live with no click and no notice. A sync links `skills/*` into the Claude, Codex, Hermes and Cortex skill folders as links into the clone, so every later push changes the skill in place. A push that carries only skills shows no banner. | team | blocks | I saw the link appear on `team sync`; the missing banner is `TeamSync.swift:31` (`isEmpty` leaves skills out) and `:296` | verified (the link) · inferred (no banner) |
| F03 | A team command can name any of your Keychain secrets and gets the value when you run it. Nothing separates "a secret the team asked you to store" from one you stored for yourself. | team | blocks | `team-reads-secret` with `env = { TOKEN = "keychain:AUDIT_TOKEN" }` printed "the team got 24 characters of your token" | verified |
| F04 | A changed team command is announced once, in memory. The sync that fetched it prints the old and new run line; the window's banner is cut to three lines and gone after one click or a relaunch; a later `great-gui run` says nothing. | team | blocks | The sync line is verified. The banner limits are `ModernWindow.swift:104-109` | verified (sync line) · inferred (banner) |
| F05 | A changed team tool is never announced. Only new tool names are reported; a new `install` or `update` line under an old name is silent. Install Missing, Update All, `tools install` and `tools update` with no names all include team tools. Only the first line of a multi-line install is shown. | team | blocks | `tools install` ran the team's line with no question (verified). The rest: `TeamSync.swift:133`, `CLI+Tools.swift:104-107`, `Tools.swift:428` | verified (runs team lines) · inferred (silent change) |
| F06 | A team file pointer can name any path and is not marked as the team's. `file store` with no names read a file the team's commit pointed at into the Keychain. By the code, a pointer named like one of your secrets would overwrite that secret, and `file restore` with no names writes a stored value to the team's path when nothing is there. | team | blocks | `file store` → `✓ team-grab stored · 46 bytes` (verified). Overwrite and restore: `Team.swift:65-66`, `CLI.swift:695`, `FileSecrets.swift:90,111` | verified (store) · inferred (overwrite, restore) |
| F07 | Every teammate's build is ad-hoc signed, so after each update the Keychain treats it as a new app and asks for the login keychain password for each secret. A scheduled run that is denied fails with a line in its log only. | install | blocks | I got exactly that dialog from a differently signed build. README:399 says ad-hoc builds ask again after every rebuild. The scheduled case is `CLI.swift:1064` | verified (the dialog) · inferred (after update, scheduled) |
| F08 | The window freezes while a Keychain dialog is up. The read happens on the main thread; clicks queue, and a second Run click raised a second dialog. | code | blocks | `sample`: 871 of 871 samples waiting on the main thread; `AppModel.swift:444` | verified |
| F09 | A new teammate's first window shows your personal examples (`ds-next`, `atlas`, `gitlab-pipelines`, `brew-outdated`), no welcome, and no way in sight to join the team: the join field is in Settings below what the window shows. | first run | blocks | Capture of a fresh instance; Settings capture | verified |
| F10 | The install text sends a teammate to GitHub. README:22, 32, 35 give the GitHub clone and `gh auth login`; `install.sh` defaults to the GitHub address unless `GREAT_GUI_REPO` is set. | install | blocks | `scripts/install.sh:42`, README | inferred |
| F11 | The Secrets, History and Tools screens are unreadable at the default window size: names cut to `AUDIT_…`, state to `in…`, the file buttons off the edge, History's mode and exit columns cut. | look | blocks | Captures `m04`–`m06` | verified |

## Should fix

| id | name | area | how bad | how I know | |
| --- | --- | --- | --- | --- | --- |
| F12 | The gate does not hold from the command line. `great-gui edit NAME --no-gate` then `run NAME` ran a gated command with no Touch ID, and the refusal's own hint says "or set gate = false". The window's edit form does not ask either. | agents | fix | Ran it | verified |
| F13 | History loses runs. Twenty runs at once recorded ten. The app, the command line and launchd all rewrite one JSON file with no lock; a file that fails to decode is replaced by a single entry. | code | fix | Ran it; `HistoryStore.swift:37,43-48` | verified (loss) · inferred (wipe) |
| F14 | A rewritten team push leaves every clone stuck with the wrong message ("the team folder has changes of its own"). A push rewound to an older commit is reported as up to date and the retracted commit stays live. | team | fix | Amended a commit, synced; rewind is `TeamSync.swift:113` | verified (stuck) · inferred (rewind) |
| F15 | A team's invalid file on first join hides all team commands and `list` still exits 0. | team | fix | B5 | verified |
| F16 | Every look except the daily one runs `BIN --version` for each `script` tool on PATH, the team's included: at launch, after a sync that changes the tool list, on `great-gui tools`. AGENTS.md and local-028 say a look asks package managers and PATH only. `bin` must be a plain program name. | team | fix | `Tools.swift:244`, `AppModel.swift:274,314` | inferred |
| F17 | The "daily" checks run on every launch. The three timestamps are in memory, so each launch does a team fetch and merge, `brew update --quiet` and an app fetch. One Settings switch turns all three off together. | code | fix | `AppModel.swift:686-693`; I saw "checked for updates 51s ago" right after a launch | verified (the header) · inferred (cause) |
| F18 | Copying a team command arms its schedule: the copy form is prefilled with the team's schedule and Save loads the agent. Nothing says so at Save. | team | fix | `AppModel.swift:120`; the on-screen note says it is "not armed until your copy has the schedule" | inferred |
| F19 | An interactive command can run twice. The terminal view starts the process when it is created, and both looks re-create it (status change in the terminal look; leaving and returning to the Terminal tab in the modern look). | code | fix | `TerminalPane.swift:17-27`, `MainView.swift:723-730`, `CommandDetail.swift:24-29` | inferred |
| F20 | One run slot with no guard: starting a second command while one runs mixes the first one's lines into the second and records the wrong exit code. Output lines are unbounded. | code | fix | `AppModel.swift:401-431,464,475-492` | inferred |
| F21 | A run waits for its pipe to close, with no timeout. A command that leaves a child holding the pipe never finishes; a hung scheduled run blocks the next. The tool and update timeouts stop the shell, not its children. | code | fix | `Runner.swift:64-68`, `CLI.swift:548`, `ToolRunner.swift:29` | inferred |
| F22 | Editing a command through the form or `edit` can change hand-written content: `;`, `=` and `!` in values are split on the way back; comments inside or after a block are dropped; a `[[command]]` line inside a multi-line string splits the block; no lock between the app and the command line. | code | fix | `RegistryWriter.swift:11-53`, `RegistryWriter+Edit.swift:22-128` | inferred |
| F23 | The window does not mask a secret that contains a newline (a PEM key, a token file ending in a newline). The command line does. | secrets | fix | `Runner.swift:96-130` against `CLI.swift:504` | inferred |
| F24 | A literal secret is accepted into the registry without a word: `--env TOKEN=value` is written to the file, committed, and shown by `show`, `list --json` and the window. In a team file it lands in the shared repository. | secrets | fix | I added `--env PLAIN=value` and saw it in the answer; `RegistryWriter.swift:47,132` | verified |
| F25 | A parameter value and a whole `exec` line go into the process arguments, `history.json` (mode 644) and `--json`. A password passed as `-P` is recorded. No Keychain value takes this path. | secrets | fix | `history --json` showed the substituted line; `ls -l history.json` | verified |
| F26 | Launchd agents are rewritten by whichever binary last synced: the agent file embeds the caller's path and `GREAT_GUI_*` variables, so the app, the command line and a debug build each reload every agent. A debug build without the overrides would point the real agents at `.build/debug`. | code | fix | `Scheduler.swift:32-35,50-53,155` | inferred |
| F27 | The update pulls and builds the tip of the branch, on one click, with no version to pin or roll back to. The built app has an empty version in its Info.plist (`bundle.sh` reads a name that is not in `Version.swift`). | install | fix | `scripts/update.sh:21-33`; the Info.plist | verified (empty version) · inferred (flow) |
| F28 | `~/.local/bin` is not on a stock PATH; the installer prints one note. The skills call bare `great-gui`, and their "command not found" help names `~/Developer/the-great-gui`. | install | fix | `install.sh:83-85`, `skills/use-secret/SKILL.md:107` | inferred |
| F29 | A Mac with no developer tools: the documented first step is `git clone`, which is the stub that raises the install dialog and fails. If the installer is reached it waits forever when that dialog is cancelled. | install | fix | `install.sh:28-32` | inferred |
| F30 | A dirty or diverged checkout: `make update` says "pulling over them" and then fails on `git pull --ff-only`; the window keeps offering the update. Offline gives the same text. | install | fix | `update.sh:17-23` | inferred |
| F31 | `make update` from a shell can kill a scheduled run in flight (it matches every process of the binary) and can open the app although it was closed. It also quits the app by a hard-coded bundle identifier. | install | fix | `update.sh:14,39-42` | inferred |
| F32 | The GreatGUI target has no tests: about 6,500 of 9,857 lines, including the app model, the whole command line, the team sync, the history, the run environment and both looks. | code | fix | `Package.swift` test targets | inferred |
| F33 | Tests that check little: `testServiceOverrideFromEnvironment` asserts only that a string is not empty; the scheduler's status test parses a literal the test wrote; the tool parsers are tested only against text the test wrote; the launchd fake always succeeds. | code | fix | `SecretStoreTests.swift:40`, `SchedulerTests.swift:21,112`, `ToolsTests.swift:65-154` | inferred |
| F34 | `tools install` says ✓ for a tool that is still missing, on the command line and in the window's sheet. | cli | fix | B4; capture `m25` | verified |
| F35 | `exec --json` without `--` answers in text; `secrets --json` has no `ok`; `--help` under `--json` prints text; an invalid registry exits 1 from four commands and 2 from six. | cli | fix | B1, B2; exit codes at `CLI.swift` (see `WORKS.md`) | verified (first three) · inferred (codes) |
| F36 | The modern look draws in three styles at once under Paper and Ink: the theme's square ink buttons and pills, system-blue selection and sidebar icons, glass Run and Stop, rounded sheets. `CommandDetail.swift` uses literal glass and a capsule against AGENTS.md. | look | fix | Captures; `CommandDetail.swift:44,53,266` | verified |
| F37 | The new-command sheet is taller than the window, and its grey right-aligned placeholders read as filled-in values. | look | fix | Capture `m20` | verified |
| F38 | Settings draws dark when the app is set to Light and carries none of the theme. | look | fix | Capture `m27` | verified |
| F39 | The same rule is written two or three times and already disagrees: which tools get Update (both looks offer it for pipx, pip, cargo, go; the command line's bulk update never picks them); the kind badge (three versions); file state advice (two wordings). | code | fix | `MainView.swift:609`, `ToolsViews.swift:47`, `CLI+Tools.swift:107`; `MainView.swift:200`, `Palette.swift:50`, `CLI.swift:998` | inferred |
| F40 | Logic in views: the terminal view builds the environment and starts the process; views decide which file actions a state allows, which fields are required, and read the log file on each draw. Ten `@AppStorage` properties sit in views. | code | fix | `TerminalPane.swift:22-28`, `MainView.swift:234,396,461`, `SecretsViews.swift:98,334` | inferred |
| F41 | Secret values stay in the model after a run ends (`RunState.env`, `redact`) and that struct is handed to views; AGENTS.md says no value reaches a view. Views use only the count. | secrets | fix | `AppModel.swift:225-226,454-455` | inferred |
| F42 | Before the app's first launch, `list`, `check`, `tools` and `schedule` answer "no registry"; only `add` works. An agent set up before the person opens the window is stuck. | first run | fix | Ran them against an empty instance | verified |
| F43 | The documents lag the code in about twenty places and are wrong in seven (targets, glass, the tools JSON shape, the history modes, `tools update NAME`). Three shipped templates still say four install methods. | docs | fix | `WORKS.md`, "Documents against the code" | verified in part |

## Nice to have

| id | name | area | how bad | how I know | |
| --- | --- | --- | --- | --- | --- |
| F44 | Masking hides the exact value only. `cut`, `base64` and `rev` printed the made-up secret; env-file values under six characters are shown. Both are documented (local-020, README:247). | secrets | nice | Ran it | verified |
| F45 | A typed, unsaved secret stays in the field when the secrets pane is closed by ⌘N, ⌘E or Update. | secrets | nice | `AppModel.swift:567,581,740` | inferred |
| F46 | A crash during restore can leave a `.NAME.….tmp` file (mode 600) holding the bytes; restore follows a symlink at the path. | secrets | nice | `FileSecrets.swift:149-167` | inferred |
| F47 | A team address with a token in it is echoed in errors, `team --json` and Settings. | team | nice | `TeamSync.swift:81`, `CLI.swift:370` | inferred |
| F48 | Two command names are reserved in the model and not in the parser: a command named `tools` records the wrong line in history; one named `update-the-great-gui` that exits 0 restarts the app. | team | nice | `AppModel.swift:485,493` | inferred |
| F49 | A team's descriptions and tags reach an agent unfiltered through `list` and `show`. | team | nice | `CLI.swift:888,920,999` | inferred |
| F50 | `history` and the team line word a moment just past as the future (`in 0s`, `synced in 0s`); the same mode is `shell` in text and `cli` in JSON. | cli | nice | B3; capture `t02` | verified |
| F51 | `file` prints a ✓ header while reporting drift; `tools update NAME` on a missing tool prints ✓. | cli | nice | B6, B7 | verified |
| F52 | `{word}` in a run line is always a parameter, with no escape: `awk '{print}'` is refused. A placeholder inside quotes gets nested quotes; `~` in a value is expanded. | code | nice | `Registry.swift:173,189,201` | inferred |
| F53 | The scheduled log is trimmed at a byte count, which can split a character; the log then fails to read as text and the window shows none of it. Dates are formatted without a fixed locale. | code | nice | `Scheduler.swift:210-229` | inferred |
| F54 | `Schedule(", 18:00")` is accepted with no days. `bootout` followed at once by `bootstrap` may be refused by launchd; the test fake cannot show it. | code | nice | `Schedule.swift:75-81`, `Scheduler.swift:156,166` | inferred |
| F55 | The tool probe is POSIX shell run through `$SHELL -lc`: a fish user would see everything missing. Non-interactive runs use `-lc`, interactive ones `-lic`, so the same command can see a different PATH. | code | nice | `Tools.swift:237`, `ToolRunner.swift:18`, `Runner.swift:36` | inferred |
| F56 | The pipx, pip, cargo and go parsers have only ever read sample text. `pip install --user` is likely refused by Homebrew's Python. | install | nice | `ToolsTests.swift`; `Tools.swift:88` | inferred |
| F57 | `install-skills.sh` replaces any link of the same name in the agents' skill folders, a team skill's or your own. | install | nice | `install-skills.sh:15` | inferred |
| F58 | Possible macOS 26 build problem: `pickerStyle(.tabs)` behind `#available(macOS 27, *)` may need the 27 SDK to compile. This Mac is on 27. | install | nice | `CommandDetail.swift:174` | inferred, not sure |
| F59 | The update check and Update… may be off when the app is opened through the `~/Applications` link, if the bundle path is not resolved to the checkout. | install | nice | `AppModel.swift:661` | inferred, not sure |
| F60 | Empty striped rows fill every table; a team command wears two identical `TEAM` pills; the install sheet is window-sized for four lines; Stop looked lit after a run ended. | look | nice | Captures | verified |
| F61 | Terminal look: the header box's corner is one cell short at 1120 wide; the header takes almost half of a 740-point window; the two looks share one saved window size. | look | nice | Captures `t01`–`t03` | verified |
| F62 | Unused or half-used code: `Palette.codeSurface`, `Palette.monoBold`, `ProcessRun.isRunning`, the `started` event, `Scheduler.Status.running` and `lastExit`. The terminal list re-draws its rows by hand instead of using `Draw.menuRow`. `AppModel.swift` is 1,136 lines and holds state for both looks. | code | nice | grep | inferred |

## What an agent can do through great-gui that a person would want to have seen first

By design, with your decision recorded (local-020, local-024): run any command with any stored secret by name, with no prompt. That is settled and is not a finding. The rest:

| What | Seen first? | |
| --- | --- | --- |
| `add --schedule`: arms a launchd job that runs with the window closed | no; the skill asks the agent to confirm, nothing enforces it | verified |
| `edit NAME --no-gate`, then `run NAME` (F12) | no | verified |
| `tools install` with no names: runs every missing tool's line, the team's included (F05) | no | verified |
| `tools update` with no names: runs every script tool's update line | no | inferred |
| `file restore --force`: overwrites a credential file that differs | no; the skill says ask first | verified (the flag works) |
| `file store` / `file restore` with no names: acts on team pointers too (F06) | no | verified (store) |
| `team join ADDRESS`: starts following a repository and links its skills into every agent | no | verified |
| `add --env KEY=literal`: writes a value into the registry and commits it (F24) | no | verified |
| `remove NAME`, `team leave` | no; `leave` goes to the Trash, `remove` is in git history only if the folder is a repository | verified |

## Checked and found sound

- No secret value in any output, the history, the registry, a scheduled log, or a process's arguments. verified
- A secret split across two writes a second apart was still masked; stdout and stderr both masked. verified
- A parameter value is shell-quoted; `x=a; echo INJECTED` printed as text. verified
- A team schedule is not armed by a sync. verified
- A bad push after joining is refused and the last good file stays. verified
- Your command wins over the team's of the same name; team commands and tools are read-only. verified
- A locally edited team clone is not overwritten. verified
- No tool field can inject into a derived shell line: every one is quoted and `pkg` and `bin` are held to plain names. inferred (`Tools.swift:84-103,145-149`)
- The clone runs no hooks and no submodules; git is told never to prompt. inferred
- Restore writes at mode 600 through a temporary file and a rename; never wider. inferred (`FileSecrets.swift:150-167`)
- Keychain items carry no sync attribute: they stay in the login keychain of this Mac. inferred (`SecretStore.swift:96-100`)
- There is no way to give a secret's value on the command line or on stdin. inferred
- No network, export or sync code touches a secret. inferred
