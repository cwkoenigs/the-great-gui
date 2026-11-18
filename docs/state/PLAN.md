# What to improve

Nov 13, 2026 · proposal only; nothing here is built. Finding ids (F01…) are rows in `FINDINGS.md`.

You said two things that shape the order: it "feels blah and has no pizazz", and it goes to **your work
computer first**. So the order is: get it onto the work Mac, make it look like something, then make it
safe for the twenty.

**To approve:** name the items you want ("1–9", "all of stage A and B", "skip 14"). Four of them need an
answer from you first; they are marked **asks you** and collected at the end.

## The ranked list

Hours are my estimate for both looks, a test where one is possible, and a DECISIONS entry. Risk is the
chance the change breaks something that works today.

### Stage A · it runs on the work Mac

| # | Item | Why | Hours | Risk | What you would see change |
| --- | --- | --- | --- | --- | --- |
| 1 | **Build without GitHub** (F01). **Asks you:** option below. | The work Mac installs from the company's git host. Today the build fetches five packages from github.com, so if GitHub is closed there the install stops at the first build. | 3–5 | medium: touches how the package resolves | `make install` works with the network cable to GitHub pulled. |
| 2 | **Install text and defaults that name no host** (F10, F28, F29). The README's first step, `install.sh`'s default address, the PATH note, the wait-forever loop. | A teammate following the README is sent to GitHub and `gh auth login`. | 2 | low | README says "clone from the address you were given"; the installer adds `~/.local/bin` to PATH when asked, and gives up politely if the developer tools are not installed. |
| 3 | **A real version, and one you can pin** (F27). Fix the empty Info.plist version; `great-gui version` and Settings show the commit; `make update` says what it is about to build. | You cannot tell two Macs' builds apart, and "Update" builds whatever is at the tip. | 2 | low | About and Settings show `0.1.0 (d94ef47)`. |
| 4 | **Keychain without the freeze and without the repeat prompts** (F07, F08). Read the Keychain off the main thread; make a stable local signing identity part of `make install`. **Asks you:** the signing part changes the signing setup, which AGENTS.md says to ask about. | On the work Mac every update will otherwise ask for the login password once per secret, with the window frozen behind the dialog. | 4 | medium: signing is easy to get subtly wrong | One "Always Allow" per secret, once, instead of after every update. The window stays live while a dialog is up. |

**Item 1, the options:**

- **A. Carry the packages in the repository** (a `Vendor/` folder, path dependencies). One repository holds everything; `make mirror` stays one push. Costs a lot of someone else's code in the repo: the five checkouts are about 200,000 lines and 70 MB as fetched, tests and demo apps included (I have not measured what is left once trimmed to what the build needs), and updating them becomes a manual step. *Recommended, narrowly:* it is the only option with nothing to set up on each Mac. If that much vendored code bothers you, B is the one to take.
- **B. Mirror the five packages to the company host too** and have `make mirror` write SwiftPM's mirror settings from the address you give. Keeps the repo small; six repositories to keep in step, and the settings file is per checkout.
- **C. Hand out a built app** instead of a checkout. No build on the work Macs at all; changes the whole install and update model and needs a signing identity the other Macs trust.

First, one fact I do not have: **can the work Mac reach github.com at all?** If it can, item 1 drops to stage C.

### Stage B · it looks like something

Every item here changes the look, so each **asks you**. None adds a font, a dependency or a download.

| # | Item | Why | Hours | Risk | What you would see change |
| --- | --- | --- | --- | --- | --- |
| 5 | **See the modern look without a screen.** `make snapshot` renders the modern look too: every sidebar screen and every sheet, both themes, light and dark, from the example registry. | Nothing renders the modern look today, which is how three screens shipped unseen. Every later look item is checked with this. | 3 | low: additive | `build/snapshots/modern-*.png`, about twenty files. |
| 6 | **Give the data the room** (F11, F60). Secrets, History and Tools: the table takes the width; the how-to text moves into an empty-state and a help popover; no placeholder rows. | These three are unreadable at the default size: `AUDIT_…`, `in…`, buttons off the edge. | 5 | low | Full names, states and buttons in view at 1120 wide. |
| 7 | **One visual language** (F36, F37, F38). **Asks you:** direction below. | The blah. Square ink theme, system-blue selection, glass buttons and rounded sheets are all on screen at once; the theme's teal appears only in small labels. | 6–10 | medium: touches every modern screen | Depends on the direction. |
| 8 | **Check Paper and Ink against the theme's stylesheet.** | The colours and button sizes were guessed. The file is on the work Mac, not this one. | 1–2 | low | Colours that match the work pages. Needs you to copy the file here or run it there. |

**Item 7, the directions:**

- **A. Commit to the theme.** Selection, sidebar icons, Run and Stop, sheets and Settings all take their shape and colour from `Palette`: ink and teal, square corners, the serif headings carried into sheets and empty states. No system blue, no glass under Paper and Ink. *Recommended:* it is what AGENTS.md already says, and it is the version with a character of its own.
- **B. Go native.** Drop the square panels and ink buttons; keep only the serif heading, the kickers and the teal accent on an otherwise standard macOS 26 window. Least work (about 6 hours), least distinctive.
- **C. A for Paper and Ink, B for ds-next.** What the code half-does now, finished properly. Most work; two looks to keep right inside the modern look.

Pizazz that fits A, each small, each for you to pick or not: the two pixel animals from the terminal header as the empty state and the About box; a run's status pill that fills with the theme colour while it runs; the last exit of each command as a small mark in the list (✓, ✗, a clock for scheduled).

### Stage C · safe for the twenty

| # | Item | Why | Hours | Risk | What you would see change |
| --- | --- | --- | --- | --- | --- |
| 9 | **First run** (F09, F42). A neutral example registry (no `ds-next`, `atlas`, `gitlab-pipelines`); a first-launch panel: what this is, join your team (the address field, here, not in Settings), add your first command; `great-gui` works before the window was ever opened. | A new teammate sees your commands and no way in. | 4 | low | A welcome on an empty Mac; `great-gui list` answers on a fresh install. |
| 10 | **Team skills ask first** (F02). A new or changed team skill is listed, with its description, and linked when the person says yes; the banner counts skills. | Today a push puts instructions in front of every agent on every Mac with no click. | 4 | low | "The team added a skill: … Link it?" in the window and in `great-gui team`. |
| 11 | **A record of what the team changed** (F04, F05). Changes to commands, tools (including their install lines) and file pointers are kept until read, in the window and in `great-gui team --json`; a changed team command or tool shows "changed since you last ran it" at the moment of running. | A changed run line is shown once and lost on relaunch; a changed install line is never shown. | 5 | low | A "Changed by the team" list that survives a restart; a mark on the command. |
| 12 | **Team entries keep to their lane** (F03, F06). A team command may only use secrets the team's own registry declares it needs, shown as such before the first run; `file store` and `file restore` with no names skip team pointers; a team pointer cannot take the name of one of your secrets. | A team commit can name any secret you hold, and a pointer can overwrite one. | 5 | medium: a team command that relied on a personal secret's name stops until confirmed | "This team command reads: gitlab-token. Allow?" once per command and secret. |
| 13 | **Bulk tool actions say what will run** (F05, F34). Install Missing, Update All and `tools install` with no names list each line first and leave team tools out unless named or ticked; after an install, look again and say "still missing" when it is. | An agent or a click runs team shell lines unseen, and ✓ can be wrong. | 3 | low | A confirm list with the lines; `✗ still missing` instead of a false ✓. |
| 14 | **The gate means it** (F12). `edit --no-gate` and `remove` on a gated command are refused on the command line, like `run` is; the hint stops suggesting `gate = false`; the README says plainly what the gate is and is not. | An agent can take the gate off and run the command. | 1 | low | `✗ … is gated: change it from the window`. |
| 15 | **Team sync that recovers** (F14, F15, F16, F17). A rewritten push is followed (the clone is read-only anyway) with the change listed; `list` exits 1 when the team file is bad; the launch look stops running `--version`; the three "daily" checks remember when they last ran. | Every clone sticks after a force-push; the app fetches and runs `brew update` on every launch. | 4 | low | A launch that does not touch the network if it did so today. |

### Stage D · it stays working

| # | Item | Why | Hours | Risk | What you would see change |
| --- | --- | --- | --- | --- | --- |
| 16 | **History that does not lose runs** (F13). A file lock around read-modify-write; a file that fails to decode is set aside, not overwritten. | Ten of twenty simultaneous runs were lost. | 2 | low | Nothing, which is the point. A test with twenty writers. |
| 17 | **One run at a time, started once** (F19, F20, F21). The model starts interactive processes, not the view; Run is refused while another runs; output is capped; a run ends when its process ends. | By the code, an interactive command can start twice and two runs mix. I would confirm each on screen before changing it. | 5 | medium: the run path is the core of the app | Run greyed out while anything runs; no repeated prompt in the terminal. |
| 18 | **The command line keeps its word** (F35, F50, F51). `exec --json` errors as JSON; `ok` in every answer; one exit code for an invalid registry; `in 0s` becomes `just now`; ✓ only when it is true. With a contract test that runs every command under `--json`. | Agents are the main users and seven answers break the stated contract. | 4 | low | The same commands, consistent. |
| 19 | **Tests for the app target** (F32, F33). The JSON contract (from 18), `RunEnvironment`, the team diff, the history, the masked run; replace the three tests that check nothing. | 6,500 lines, including everything an agent calls, have no test. | 6 | none | `make check` goes from 74 to about 110 tests. |
| 20 | **Secrets, the loose ends** (F23, F24, F25, F41, F45). Mask multi-line values in the window; warn when `--env KEY=literal` looks like a secret; clear values from the model when a run ends; note in the skill that `-P` values are recorded. | Small, and each is a place a value could show. | 3 | low | A warning line on `add`; nothing else visible. |
| 21 | **Edits that keep your file** (F22). Round-trip tests with `;`, `=`, `!`, comments and multi-line strings, then fix what they show. | The form can split a value and drop a comment. | 4 | medium | Nothing, unless you have such a command today. |
| 22 | **One rule, one place** (F39, F40). The Update rule, the kind badge, file-state advice and team wording move into the model; both looks and the command line read them. | Three copies of the Update rule already disagree. | 4 | low | The same words in both looks. |
| 23 | **Documents catch up** (F43). README, AGENTS.md, the three skills, the help and five DECISIONS statuses. | About twenty stale claims and seven wrong ones. | 2 | none | Docs that match. Best done last. |

Stage A is 11–13 hours, B 15–20, C 26, D 30. I would not start C before A and B are in your hands on the work Mac.

Left out on purpose, all "nice": F46–F49, F52–F59, F61, F62. Say if you want any pulled in.

## The open decisions

### 1 · A team command's schedule

Today it is held back until the person copies the command, and the copy form quietly carries the schedule (F18).

| Option | What it costs | |
| --- | --- | --- |
| **A. Keep it held back, and say so at Save.** The copy form shows "this will run daily at 03:00 on this Mac" with the schedule as a switch that starts off. | 1 hour. | **Recommended** |
| B. A button that arms the team's command as it is, without copying. | 3 hours, and it puts a run line the team can change under a job that runs with nobody watching. Needs item 11 first. | |
| C. Arm on sync. | No work. A push then runs on twenty Macs at 03:00 with no click. | No |

A copy is frozen, so what runs on a schedule is something the person saw. That is worth keeping.

### 2 · Under `--json`, where a command's own output goes

Today: streamed to stderr, masked; the result object has the exit code and the secret names.

| Option | What it costs | |
| --- | --- | --- |
| A. Leave it. | Nothing. An agent has to capture stderr itself and cannot tell the command's stderr from its stdout. | |
| **B. Keep the stream, and add `--capture`**: the object then also carries `output` (masked, stdout and stderr in order, last 64 KB, with `truncated`). | 2 hours. | **Recommended** |
| C. Always put the output in the object. | 2 hours. Long runs show nothing until they end, and a large output bloats every answer. | |

B keeps today's behaviour for anything already written against it and gives an agent one thing to parse when it asks.

### 3 · The hub

Registered installs, targeted pushes, reporting back. The three candidates are in `docs/team-tooling.md`.

| Option | What it costs | |
| --- | --- | --- |
| **Not yet.** | Nothing now. | **Recommended** |
| Git only: an install commits a small file about itself to the team repository. | About 15 hours. Every teammate needs push access, which today they do not need, and it reverses "never write in the team clone". | Second, when the time comes |
| Snowflake at work. | About 20 hours, only reaches people with Snowflake access, stays inside company systems. | |
| A small web service. | 30 hours or more, a service to host and secure, and company approval to send data to it. | |

With one work Mac as the first user there is nothing to register. Build it when three or four teammates are on part 1 and you find yourself asking "who has this?". Until then `great-gui team --json` on each Mac already answers it one Mac at a time.

## Three things it does not do

1. **`great-gui doctor`.** One command, with `--json`, that says whether this Mac is in working order: on PATH, built and signed how, registry valid, team reachable and when last synced, secrets the commands need that are missing, schedules loaded and their last exit, tools missing. *Why:* it is the first thing an agent should run and the first thing you would ask a teammate to paste, and today it takes six commands. About 3 hours.
2. **What the last run printed.** Keep each command's last output (masked, capped) beside its history entry; `great-gui last NAME` and the History tab show it. *Why:* history today is exit codes only, so "what did the 08:30 run say?" has no answer unless it was scheduled, and an agent that ran something an hour ago cannot look back. About 4 hours.
3. **A menu-bar item.** The scheduled commands with their last result, anything that failed since you last looked, and type-to-run for any command without opening the window. *Why:* the window is something you go to; this is there when a run fails at 08:30, and it is the most direct answer to using it more. About 6 hours, and it is a change to the look, so it asks you.

## What to cut

| Thing | Why | What I would do |
| --- | --- | --- |
| The Gallery window in the shipped app (⌘⇧G) | A design-system demo. Teammates have no use for it and `make snapshot` already renders it. | Keep the code for snapshots; take it out of the app's menu. |
| The `pip` method | `pip install --user` is refused by Homebrew's Python, and `uv` and `pipx` cover the case. Never run on the real thing. | Cut it. Mark `cargo` and `go` "untried" in `tools methods` until someone runs them. |
| The undocumented aliases (`file put`, `file apply`, `tools upgrade`, `team status`, `--tty`, `--description`) | In no document and no skill; each is one more thing the contract test must cover. | Cut all but `rm`. |
| Unused code (F62) | `Palette.codeSurface`, `Palette.monoBold`, `ProcessRun.isRunning`, the `started` event, two `Scheduler.Status` fields. | Delete. |
| Your personal examples in the example registry | See item 9. | Replace. |
| **A question, not a recommendation: the terminal look as an equal.** | "A feature needs both looks" roughly doubles every screen item above, and the modern look is the default. | Keep it, but decide whether new screens (Scheduled, History, Team) must exist there. My suggestion: freeze it at what it has, so it stays a way to run and browse, and build new screens in the modern look only. |

Not a cut: scheduling. No scheduled command exists on this Mac today, but it works end to end and the work Mac is where it earns its keep.

## What I need from you

1. Can the work Mac reach github.com? If not: item 1, option A, B or C.
2. Item 4: may `make install` create and use a local signing identity?
3. Item 7: direction A, B or C, and which of the small touches.
4. The terminal look: equal, or frozen at what it has?
5. The three decisions: say "as recommended" or pick.
6. Which items to build, in what order if not this one.

## Clark's answers so far (Nov 13)

1. **GitHub:** the work Macs can pull from github.com; nothing is pushed there. Clark pulls the app once and pushes it to the internal GitLab. So the build can fetch its packages, and **item 1 is dropped**. Item 2 (install text that names no host) stays.
2. **Signing (item 4):** yes. No Apple ID, Apple account or email may be involved at work: the identity is a self-signed certificate made locally in the login keychain, nothing from Apple.
3. **Look (item 7):** direction A, commit to the theme. The small touches are not picked yet.
4. **The terminal look:** remove it. This becomes a new item, **24 · Remove the terminal look**: the terminal window (`Views/MainView.swift`, 786 lines), the Look menu and setting, the model state only it uses, and its snapshots. It keeps the embedded terminal that interactive commands run in, and the colour tokens the modern look reads from `TerminalDesign`. About 4–6 hours, medium risk (it touches the app model). Every later screen item is then built once, so the hours in stages B to D drop by roughly a third. Open: whether the Gallery window and the terminal primitives it shows go too.
5. **The three decisions:** not answered yet.
6. **Which items to build:** not answered yet.
