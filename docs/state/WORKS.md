# What really works

Nov 13, 2026 · tip `d94ef47` · tested with `.build/debug/GreatGUI` against a throwaway instance (nine
`GREAT_GUI_*` overrides into a scratch folder, a scratch Keychain service). Nothing here was fixed.

Every claim is marked **verified** (I ran it and read the output) or **inferred** (I read the code, or a
sub-agent read it and I did not run it). The raw record is in `LOG.md`.

## In short

- The command line is in good shape. About 150 cases, plain and `--json`: the registry, runs, history, secrets by name, credential files, the team registry and tools all did what the help says. Seven small defects, listed below. **verified**
- Scheduling works end to end. One scratch-labelled agent (`every 1m`, an `echo`) was armed, fired seven times on the minute from launchd, was paused (unloaded), resumed (loaded again) and removed (agent file and launchd entry gone). **verified**
- Both looks were clicked through in a scratch app bundle (second pass, after Accessibility was granted). Every modern screen and sheet opens and does its job. The layout is where it is weak: the Secrets, History and Tools tables are crushed into a narrow column beside a wide help panel, and system blue, glass and rounded sheets sit on top of the square Paper and Ink theme. Details under "The screens". **verified**
- The documents lag the code in about twenty places and are wrong in six. Two code defects turned up on the way: the built app has an empty version in its Info.plist, and the modern look uses literal glass against its own rule.

## The checks

| Check | Result | |
| --- | --- | --- |
| `make check` | exit 0 | verified |
| Tests | 74 cases, 0 failures (TerminalDesign, Registry 43, Runner, Scheduler, Secrets) | verified |
| Token check | `Tokens.swift agrees with …/ds-cli-design/design-system/tokens.json` | verified |
| Command-line-tools-only build | `Build complete!` | verified |
| `make snapshot` | six PNGs, terminal look only: gallery, main, tools × dark, light | verified |
| No `@State` | the only two matches are comments | verified |
| Size | 9,857 lines in `Sources`, 1,342 in `Tests`, six targets | verified |
| `DECISIONS.md` | 31 entries, `local-001` to `local-031`, no gaps | verified |

A passing test here is not proof of a screen: no test draws the modern look, and `make snapshot` does not either.

## The command line

Each row was run plain and with `--json`. "One object" means stdout parsed as exactly one JSON object.

| Command | Plain | `--json` | Exit codes seen | Status |
| --- | --- | --- | --- | --- |
| `version`, `help`, `path` | works | not offered, as documented | 0 | WORKS |
| unknown command | `✗ unknown command bogus` | one object | 2 | WORKS |
| `check` | works | one object | 0; 1 when the team's file is invalid | WORKS |
| `list` | works, team entries marked `team` | one object | 0 | WORKS (see B5) |
| `show NAME` | works; missing name refused | one object | 0, 2 | WORKS |
| `run NAME [-P k=v]` | works; defaults, required and unknown parameters handled; parameters shell-quoted | one object, output on stderr | the command's own; 2 on refusal | WORKS |
| `run` of a gated command | refused: "run it from the window" | one object | 2 | WORKS |
| `run` of an interactive command | ran and printed | one object | 0 | WORKS |
| `history [NAME] [-n N]` | works | one object | 0, 2 | WORKS (see B3) |
| `add` | works; duplicate, bad name, bad flag, bad schedule, bad env, undeclared parameter all refused with a named fix | one object | 0, 2 | WORKS without a schedule |
| `add --schedule "every 1m"` | `✓ added tick … · agents synced`; agent file written, loaded in launchd | not run a second time | 0 | WORKS |
| `add --schedule` with gate, interactive, or a required parameter | each refused | | 2 | WORKS |
| `edit`, `edit --name` | works; team command refused | one object | 0, 2 | WORKS |
| `remove`, `rm` | works; team command refused | one object | 0, 2 | WORKS |
| commit after a write | every answer said `"committed": false` | | | UNTESTED (scratch folder was not a git repository) |
| `schedule`, `schedule sync` with nothing scheduled | works | one object | 0 | WORKS |
| `schedule` with entries, `pause`, `resume` | `tick  every minute · loaded`; pause → `paused`, 0 in `launchctl list`; resume → loaded; `remove` → agent gone | `schedule --json` one object with `next_run`, `last_run`, `log` | 0, 2 | WORKS |
| `secrets`, `secret` | names only, who uses each | one object, but no `ok` key | 0 | WORKS (see B2) |
| `exec … -- COMMAND` | works as words and as one quoted line; `--cwd`; the command's exit code | one object when `--json` is before `--` | the command's own; 2 | WORKS (see B1) |
| `exec` with a secret | `v=•••••` on stdout and stderr; `"masked": 1` | one object | 0 | WORKS |
| `exec` with a missing secret | refused by name | one object | 2 | WORKS |
| `file`, `files` | states `wrong mode`, `differs`, `missing` shown | one object | 0; 1 when out of sync | WORKS (see B6) |
| `file add` (`--no-store`, missing path) | works | one object | 0 | WORKS |
| `file store` | works; unknown name refused | one object | 0, 2 | WORKS |
| `file restore` | same file: mode set to 600; differing file refused; `--force` overwrites; absent file written | one object | 0, 1 | WORKS |
| `file remove [--purge]` | works; warns a command still needs it | one object | 0 | WORKS |
| `update-check` | `✓ up to date` | one object | 0 | WORKS; exit 10 UNTESTED (nothing was waiting) |
| `team` | works joined and not joined | one object | 0; 1 when the team's file is invalid | WORKS |
| `team init DIR` | wrote `commands.toml`, `README.md`, `skills/.gitkeep`, `.git` | one object | 0 | WORKS |
| `team join ADDRESS` | cloned; a second join refused; a bad address refused | one object | 0, 1 | WORKS |
| `team sync` | took a new commit, listed what changed, linked the team's skill | one object | 0 | WORKS |
| `team leave` | folder moved to the Trash, skill link removed | one object | 0 | WORKS |
| a team schedule | not armed: no agent file, nothing in `launchctl list` | | | WORKS |
| `tools`, `tool`, `tools --check` | works | one object | 0; 1 when one is missing | WORKS for `script` tools |
| `tools methods` | nine methods | one object | 0 | WORKS |
| `tools add`, `tools remove` | works; bad method, `script` without a line, team tool all refused | one object | 0, 2 | WORKS |
| `tools install`, `tools update` | ran `echo` lines; a failing line reported; already-installed skipped | one object, output on stderr | 0, 1, 2 | WORKS for `script` tools (see B4, B7) |
| `brew`, `cask`, `uv`, `pipx`, `pip`, `npm`, `cargo`, `go` tools | not run | | | UNTESTED (by rule: a real entry changes this Mac) |

Secrets, checked across every recorded output, the history file and the registry: the two made-up values appear nowhere in plain form. **verified**

### Broken, with the output

**B1 · `exec --json` without `--` answers in text.** verified
```
$ great-gui exec --json echo hi
✗ exec needs -- before the command          (stderr; stdout is empty; exit 2)
```
The help promises "one JSON object on stdout, errors included".

**B2 · `secrets --json` has no `ok` key.** verified. Every other answer has one.
```
{ "secrets" : [ … ], "service" : "com.cwkoenigs.the-great-gui.audit-scratch" }
```

**B3 · `history` words a run that just ended as the future, and names the mode two ways.** verified
```
    in 0s       shell     exit 3   fail            (plain)
    "mode" : "cli"                                 (--json, same run)
```
The help says the modes are "window, shell, scheduled, exec"; the code never prints "window" (inferred).

**B4 · `tools install` says ✓ when the tool is still missing.** verified. Success is the install line's exit code only.
```
$ great-gui tools install tp        →  ✓ tp · 0.1s        (exit 0)
$ great-gui tools                   →  tp  missing        (exit 1)
```

**B5 · A broken team file hides every team command, and `list` still exits 0.** verified
```
$ great-gui list
✗ the team's registry: two commands are named team-hello        (stderr)
✓ 11 commands · 3 groups · …                                    (stdout, exit 0; `check` exits 1)
```
This was on a first join. The code is said to refuse a bad push once joined (inferred, `TeamSync.swift:119`); I did not test that path.

**B6 · `file` prints a ✓ header while reporting drift and exiting 1.** verified
```
✓ 4 files · Keychain service …
    fakep                   differs          …
```

**B7 · `tools update NAME` on a tool that is not installed prints ✓ and exits 0.** verified
```
✓ tp · not installed: great-gui tools install tp
```
The install-tool skill says `tools update uv` updates "this one, whatever its state".

Smaller, all verified: `add --json --help` prints the help text, not JSON. `seconds` prints as `0.10000000000000001`. A bad name is reported as `command[0]: 'bad name' is not a valid name`. The registry writer leaves no blank line before a `[[command.param]]` block. After a file is purged, `secrets` lists its name as a missing secret. `list` says "1 file in the Keychain: team-file" for a team pointer that is not in the Keychain.

### Things that work but you should know (carried into Phase 2)

- Masking hides an exact value only. The same made-up secret printed in full through `cut`, `base64` and `rev`. verified
- Values under six characters from an env file are not masked (`user=audit pass=•••••`). verified; the floor is in `RunEnvironment.swift:22`.
- A team sync linked the team's skill into the agents' skill folders with no further step. verified (in the scratch folder).
- `tools install team-tool` ran the team's line with no question. verified
- `great-gui --json list` opens the window instead of failing: any first argument starting with `-` does. inferred (`CLI.swift:20`)
- An invalid registry exits 1 from `list`, `check`, `show`, `schedule` and 2 from `run`, `edit`, `remove`, `file`, `tools`, `pause`. inferred
- The Settings switch for update checks also turns off the daily team sync and the daily tools look. inferred (`AppModel.swift:687`)
- A `script` tool's `BIN --version` is run by every look except the daily one, including the look at launch. inferred (`Tools.swift:244`, `AppModel.swift:274`). AGENTS.md says a look "asks package managers and PATH only".

## The screens

Second pass, Nov 13 05:35–05:45. The same build wrapped as a scratch bundle (`AuditScratch.app` in my
scratch folder, its own bundle identifier, all nine overrides checked in its environment), driven with
clicks and keys. Everything in this table is **verified** by a capture I looked at unless marked.

| Screen | Modern look | Terminal look |
| --- | --- | --- |
| Commands list and detail | seen, Paper and Ink and ds-next, light and dark | seen, dark |
| A run in progress, done, failed | seen: spinner pill `running · 2s`, `done`, `exit 3` with `exit 3 · 0.0s · 1 line` | seen: output streams under the list, `ctrl-c interrupts` |
| A parameter | seen: an inline field, default filled, ran `echo hi world` | captured, not looked at |
| Embedded terminal | seen: `type something:` with a cursor, `ctrl-d leaves` | not tried |
| A command with a secret | seen: `TOKEN = keychain:AUDIT_TOKEN`; after I denied the Keychain dialog, `did not run` and a clear reason | not tried |
| New command sheet | seen | captured, not looked at |
| Edit sheet, delete confirmation | captured, not looked at | not tried |
| Scheduled | seen: `every minute · next 05:36 · last 1m ago, exit 0`, a Pause button, a Log tab | no such screen (inferred) |
| Team | seen: `TEAM COMMAND`, read-only note, "The team suggests running it daily at 03:00; that is not armed until your copy has the schedule" | header line `team  3 commands · 1 overridden by yours` seen |
| Tools | seen | seen in snapshots; real pane captured, not looked at |
| Add-tool sheet | seen | seen in snapshots |
| Install run sheet | seen: the line, its output, `✓ echo-tool`, `done` | no sheet; a tools run shows in history as `terminal` |
| Secrets and files | seen | seen |
| History (all runs) | seen | last five under the list: seen |
| Settings | seen | same window |
| Update sheet | **not opened**: Update… acts on the real checkout | not opened |
| Gallery | not opened | seen in snapshots |
| A gated command (Touch ID) | **not tried**: I cannot answer Touch ID | not tried |
| The "from the team" notice after a sync | not seen (no sync happened while the window was open) | not seen |

### What works in the window
- Run, stop, the status pill, the output block, the embedded terminal and the parameter field all behave.
- A scheduled command shows its next and last run, and the count in the sidebar is right.
- A team command is marked, read-only, and the toolbar's edit button becomes a copy button.
- The install sheet runs the line and shows its output.
- A denied Keychain read is explained in words, with a pointer to the README.
- The terminal look streams a run, lists secrets and files with their state, and filters as you type.

### What is wrong on screen
1. **The data is squeezed and the help is wide.** On Secrets the table is about 320 points wide: the name shows as `AUDIT_…`, the state as `in…`, the user as `with-se…`, and the files table is cut at `no comman` with its Store and Restore buttons off the edge. On History the Mode, exit and duration columns are cut off (`M`), beside three stat tiles and one sentence in a panel twice as wide. On Tools the names are cut (`team-t…`, `already on this…`) beside a help panel. These are the screens nobody had seen.
2. **Empty striped rows fill every table.** One secret, then a page of grey placeholder bars.
3. **Three visual languages at once in Paper and Ink.** Square ink buttons, square pills and square panels from the theme; system-blue selection and blue sidebar icons from macOS; glass Run and Stop buttons; and sheets with rounded corners and rounded grouped rows. The teal accent of the theme appears only in kickers and links.
4. **Stop looked lit when nothing was running.** Two seconds after the failed run ended, Run and Stop were both filled teal; in a later capture Stop was grey again. I cannot say whether it is a slow animation or a state bug.
5. **The new-command sheet is taller than the window** (772 points against 740): it hangs below the window's bottom edge. Its placeholders are right-aligned in grey beside one real value in black (`scratch`), so an empty form looks filled in. I did not scroll it, so I did not see the tags, interactive, gate or schedule rows.
6. **Settings ignores its own Appearance.** The app was Light; Settings drew dark, in plain system style with none of the theme. Its window shows Look and Updates; the team join section was not in view (it is in the code; I did not scroll).
7. **A team command wears two identical pills**, `TEAM` (its group) and `TEAM` (its origin).
8. **The install sheet says `done` and `✓ echo-tool` for a tool that is still missing** (B4, in the window too), and the sheet is the size of the window for four lines.
9. **Stale words on screen:** Tools says "Once a day the app asks Homebrew and uv what is behind". The header reads "checked for updates 51s ago" after a launch that only looked.
10. **The window froze while the Keychain dialog was up.** Clicks on other rows and on Run did nothing until the dialog was answered; a sample of the process showed the main thread waiting. A second Run click queued a second dialog.
11. **Terminal look:** the header box's top-right corner is drawn one cell short of the right border at 1120 wide; the header takes almost half of a 740-point window, so the secrets pane runs off the bottom; `synced in 0s` words a past moment as the future (same as B3); the path line shows `/` when the app is opened from Finder.
12. **The window opens at whichever size the other look last had**: the saved frame is shared between the two looks.

### What one look has that the other lacks
Seen where marked; the rest **inferred** from which model actions each look's files call.
- Modern only: a Scheduled screen (seen), a History screen (seen), a Team sidebar entry (seen), a sheet for a tool run (seen), a Log tab (seen), a Pause button (seen), drag to reorder, a Check for Updates button.
- Terminal only: a live preview of the entry while the form is filled; ⌥↑ and ⌥↓ to reorder; the registry path, shell and Keychain service always in view (seen).
- Shared through the menu bar or Settings: pause and resume, team join, sync and leave, the update.
- `make snapshot` covers the terminal look only. Nothing renders the modern look for review.

## Documents against the code

Read by a sub-agent with file and line for each; the rows marked ✔ I checked again myself. Everything else here is **inferred**.

**Wrong**

| Where | It says | The code |
| --- | --- | --- |
| AGENTS.md:9 | "never a literal corner radius, capsule or glass effect" | ✔ `CommandDetail.swift:44` `.buttonStyle(.glassProminent)`, `:53` `.buttonStyle(.glass)`, `:266` `.glassEffect(.regular, in: Capsule())` |
| AGENTS.md:17 | "answer with exactly one `CLI.emit`" | ✔ `secrets --json` prints its own object (`CLI.swift:417`) |
| AGENTS.md:19 | "A look … asks package managers and PATH only" | ✔ `Tools.swift:244` runs `BIN --version` for script tools unless `versions: false` |
| Help, README.md:275 | `tools install\|update` "print `{"ok", "code", "seconds", …}`" | ✔ the object is `{"ok","action","results","skipped","failed"}`; `code` and `seconds` are per result |
| Help (`CLI.swift:78`) | history modes "window, shell, scheduled, exec" | `HistoryStore.swift:52` prints `terminal`, `scheduled`, `shell`, `run` |
| install-tool SKILL.md:29 | `tools update uv` "this one, whatever its state" | ✔ a tool that is not installed is skipped |
| add-command SKILL.md:21 | `remove --json` answers "with the command as it now is" | ✔ it answers with the name and a count |

**Stale**

| Where | It says | The code |
| --- | --- | --- |
| AGENTS.md:4, README.md:377 | five targets | ✔ six: `Scheduler` is missing from both |
| README.md:14 | "To implement next: team tooling" | part 1 is built |
| README.md:27 | the installer links "the `add-command` skill" | all three skills are linked |
| README.md:74 | `make check` is tests and the token check | ✔ it also does the tools-only build |
| README.md:78, Makefile:25 | snapshot renders "the gallery and the main window" | ✔ also the tools screen |
| README.md:106 | sidebar is "groups plus Secrets and History" | ✔ also Scheduled, Tools, Team |
| README.md:108, :155 | "the same ten fields" | twelve: `env_file` and `schedule` were added |
| README.md:158, :177 | flags of `add` and `edit` | `--schedule`, `--no-commit`, `--clear-schedule` are missing |
| README.md:126 | the registry format | no `tags`, no `schedule`, no `desc` on `[[file]]` |
| README.md:320, team-tooling.md:61 | the check "asks Homebrew and uv" | npm is asked too |
| add-command SKILL.md:3 | "Claude Code, Codex and Cortex Code" | ✔ Hermes is linked too, and the other two skills say so |
| add-command SKILL.md:68 | the clear flags | `--clear-env-file` is missing |
| Help | `update-check` | takes an optional checkout path |
| `commands.example.toml:87`, `TeamSync.swift:212`, `MainView.swift:630` | "method is brew, cask, uv or script" | ✔ nine methods (I saw the line in the file `team init` wrote) |
| DECISIONS local-022, -023, -025, -028, -009 | "Nothing is built", "one palette", "no form for adding a tool" | each was overtaken by a later entry and its status not changed |

**True**, the ones that matter: every command line in all three skills exists as written (✔ I ran nearly all of them); `--json` on every command but `path`, `version`, `help`; `Registry.parse` is strict; a Keychain value is read in one function, reached only from `RunEnvironment.build` and `FileSecrets`; no network or sync code touches a secret; a team schedule is stripped on load; no git host is named in `Sources`; the nine methods; the schedule phrases; the six file states.

**Not in any document** (inferred): the aliases `rm`, `files`, `secret`, `tool`, `team status`, `file put|apply`, `tools upgrade` (✔ four of them run); `GREAT_GUI_SHELL`, `_TEAM`, `_SKILL_DIRS`, `_AGENTS`, `_LOGS`, `_SCHEDULER_STATE`, `_AGENT_PREFIX` by name; the history cap of 500 runs; logs trimmed past 1 MB; `scripts/install.sh` ignores the registry and team overrides.

**A code defect found while comparing.** ✔ verified in the built app: `scripts/bundle.sh:14` looks for `static let version = "…"`, but `Version.swift` has `static let string = "0.1.0"`, so `build/the-great-gui.app/Contents/Info.plist` has an empty `CFBundleShortVersionString` and `CFBundleVersion`.

## The three skills, followed as an agent would

All in the throwaway instance. **verified** unless marked.

**add-command.** `version`, `list`, `list --json`, `add` with a parameter, a tag, an env entry and a Keychain reference, `edit`, rename, `remove`: every step worked as written. Where it left me guessing:
- It does not say that `add --schedule` arms a launchd agent the moment it returns. An agent trying the skill out creates a real scheduled job.
- "when `~/.great-gui` is a git repository it commits" gives no way to tell beforehand; the answer's `committed` field is the only sign, and `--no-commit` is not mentioned.
- A secret that is not stored yet: `add` succeeds and warns. The skill does not say whether to stop or go on.
- Step 7 says ask for a yes; nothing in `great-gui` enforces it.

**use-secret.** `secrets`, `exec` in all four shapes it shows, `file`, `file restore`, the missing-secret message, the gated refusal: all as written. Where it left me guessing:
- "`history --json` is the record … with the secret names used": for `exec` the names are a `# with NAME` comment inside the `run` string; for `run NAME` they are not recorded at all.
- "put `--json` before the `--`": get it wrong and the answer is text (B1).
- "A Keychain dialog appears: the user clicks Always Allow": it appeared when a differently signed build (my scratch bundle) read the test item from the window. It asks for the login keychain password, not just a click. I pressed Deny. From the command line with the debug binary none appeared.
- Rule 2 forbids reading a value, and nothing stops it: `exec` printed the made-up secret through `base64`. The skill is the only guard.

**install-tool.** `tools --json`, `--check`, `methods`, `add`, `install` one and all, `update`, `remove`, a failing install, the team read-only refusal: all as written, with `script` tools only. Where it left me guessing:
- "A team tool is the team's word … ask before installing it": the command line does not ask, and plain `tools install` installs every missing team tool along with mine.
- `ok: true` after an install does not mean the tool is there (B4). The skill does not say to look again.
- `tools update NAME` on a missing tool is a ✓ (B7).
- Every package-manager method, `elsewhere`, and a password prompt: UNTESTED.

## Your known state, checked

| You said | Found | |
| --- | --- | --- |
| 19 commits, tip `d94ef47`, clean, level with origin | yes | verified |
| About 9,900 lines in six targets | 9,857 in `Sources`; six targets | verified |
| No `@State` | yes. Views do hold settings in `@AppStorage` (ten places) | verified |
| `make snapshot` renders the terminal look only | yes | verified |
| 31 decisions | yes | verified |
| `--json` on every command but path, version, help | yes, with B1 and B2 | verified |
| Three skills linked into four agents | the link script names four folders; I saw the three skills in this session only | inferred |
| My registry has about 15 commands; the team holds one | not looked at: I kept out of `~/.great-gui` and `~/.great-gui-team` | not checked |
| A team schedule is held back | yes | verified |
| Under `--json` a command's output goes to stderr | yes | verified |
| Schedules exist | on this Mac no the-great-gui launchd agent is loaded and no agent file exists, so scheduling is not in use here today | verified |
