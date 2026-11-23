# Decisions

Local decisions for the-great-gui, newest last. Format as in ds-next.

## local-001: A native SwiftUI app

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** A GUI manager for Clark's personal terminal commands, drawn like ds-next (the look only),
  on two Macs (home and work; the work machine is moving to a Mac), with macOS Keychain integration and
  security as requirements. No agent integration is wanted.
- **Options considered:**
  1. **Node server + React kit in a browser**: reuses ds-cli-design's React primitives verbatim; a localhost
     server that runs commands and would hand out secrets over a socket.
  2. **Python server + React kit in a pywebview window**: the same, in the language of ds-next and atlas;
     Keychain through `keyring`. Started, then withdrawn when Keychain and security were named.
  3. **Tauri or Electron**: the React kit in a native shell; Rust toolchain or a heavy runtime; still a web UI.
  4. **SwiftUI with Keychain Services and LocalAuthentication**: chosen. No listening port, secrets stay in
     process, Touch ID gating is first-class, builds with the command-line tools alone.
- **Decision:** One Swift package: `TerminalDesign` (the design system), `GreatGUI` (the app), with the
  registry, runner and secrets to follow as targets. VS Code with the Swift extension; Xcode optional.
- **Consequences:** The design system is ported rather than reused: a generator for the tokens and a
  rewrite of the primitives. Swift is a new language in Clark's repositories. The React kit stays the
  reference for the look.
- **Validation:** `swift build` and `swift test` pass with the command-line tools on macOS 27.2; the
  gallery snapshot matches the web kit's session page by eye.
- **Review date:** when the registry and runs are in.

## local-002: Tokens generated, primitives hand-ported

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** The design system's values exist once in ds-cli-design's `tokens.json`; dashboard-style
  builds its CSS theme from the same file.
- **Decision:** `scripts/gen_tokens.py` writes `Tokens.swift`; `make check` fails when it is stale. The
  primitives are written by hand as SwiftUI views on a fixed line grid, one `AttributedString` per row,
  with the grid arithmetic in pure functions (`Draw`) that the tests cover. Names: `ResultLine`,
  `SlashMenu`, `Draw.key`. Deviations: `Banner` takes a name; its `┬` aligns with `┴`. Kept for fidelity:
  the menu footer's `▼`, retired in the tokens, to be raised in ds-cli-design.
- **Consequences:** A new export is `make tokens` plus a read of the component diffs; the primitives do not
  regenerate. ds-cli-design's `check.py` compares canon-lib to the tokens; a Swift check is a follow-up.
- **Review date:** the next design export.

## local-003: JetBrains Mono installed per machine, not bundled

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** The design names JetBrains Mono as its one typeface, with Menlo and SF Mono as fallbacks.
  A native app has to choose how to get it. Clark chose, when asked.
- **Decision:** Installed on each Mac (`brew install --cask font-jetbrains-mono`); the app asks for it by
  name and falls back to SF Mono when it is missing. Nothing is downloaded by the build.
- **Consequences:** A per-machine step, which fits updater's registry. Without it the look is close, not
  exact.

## local-004: Build and signing

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** No Xcode and no signing identity on the home Mac; the work Mac unknown. Keychain binds items
  to the identifier and the signing certificate.
- **Decision:** `swift build` plus `scripts/bundle.sh`, which wraps the binary as an `.app` and signs with
  `SIGN_IDENTITY` (ad-hoc by default). A self-signed code-signing certificate per Mac gives a stable
  identity. `BUNDLE_ID` defaults to `com.cwkoenigs.the-great-gui`; change it before any secret exists.
- **Consequences:** The default build re-prompts Keychain after each rebuild until a certificate is made.

## local-005: macOS 26 floor, Swift language mode 5

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** Clark set macOS 26 as the oldest release the app must run on. The Swift 6 toolchain's strict
  concurrency would slow a scaffold.
- **Decision:** `platforms: [.macOS(.v26)]`; `swiftLanguageModes: [.v5]`.
- **Review date:** before the Keychain and runner targets, which are where concurrency matters.

## local-006: The command-line tools build, and `@State`

- **Status:** Accepted (the rule is open to review; Clark decides whether to keep it)
- **Date:** 2026-11-09
- **Context:** The package was promised to build with the command-line tools alone, so the work Mac needs no
  Xcode. The first such build failed: on the macOS 26 SDK, SwiftUI's `@State` is a macro whose plugin
  (`libSwiftUIMacros.dylib`) ships in Xcode and not in the tools (`/Library/Developer/CommandLineTools/usr/
  lib/swift/host/plugins/` has only the Observation and Swift macros). A probe package showed `@State` is
  the only affected wrapper: `@Environment`, `@AppStorage`, `@Binding`, `@StateObject`, `@Observable`,
  `@FocusState` and `@SceneStorage` all compile with the tools. Xcode 27.2 was installed on the home Mac
  during the session, so both toolchains are available here.
- **Options:** require Xcode on every Mac and use `@State` freely; or keep the tools-only build by holding
  view state in `@StateObject` / `@Observable` models.
- **Decision:** For now the second: `Term`'s measured width moved to a `@StateObject`; `make check` is run
  under both toolchains. Whether to keep this rule as the app grows is Clark's call.
- **Validation:** `DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build --scratch-path .build-clt`
  passes; `swift build` and `swift test` pass under Xcode 27.2.
- **Review date:** when the registry views are written.

## local-007: TOMLKit and SwiftTerm

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** The registry is TOML, like updater's and ds-next's config; interactive commands need a real
  terminal. Clark chose both, when asked, over an in-house TOML subset parser, a JSON registry, and
  handing interactive commands to Terminal or iTerm.
- **Decision:** TOMLKit (full TOML, toml++ core) decodes `commands.toml` strictly: an unknown key is an
  error. SwiftTerm's `LocalProcessTerminalView` is the embedded terminal, drawn in the design's colours
  (`TerminalPane`). The app links only SwiftTerm itself: its swift-png dependency applies to other
  platforms and swift-argument-parser to its own executables.
- **Consequences:** Two third-party packages to watch. The decoder reports a wrong type as a missing key,
  so `Registry.parse` consults the TOML table and a small schema to say "must be true or false" instead.
- **Validation:** `RegistryTests` (messages, substitution, quoting, filter, the example file);
  `RunnerTests` (order, exit code, redaction, colour off, cwd, a failed launch). Both toolchains build.

## local-008: Where things live, which shell runs

- **Status:** Accepted (defaults, stated before the step and not objected to)
- **Date:** 2026-11-09
- **Decision:** The registry is `~/.great-gui/commands.toml`, written from the example on first launch,
  `GREAT_GUI_REGISTRY` overrides; it is watched and reloaded on change. Plain commands run in the login
  shell (`$SHELL -lc`, `GREAT_GUI_SHELL` overrides) with colour off and escapes stripped; interactive
  ones in an interactive login shell (`-lic`) inside SwiftTerm. History is `~/Library/Application
  Support/the-great-gui/history.json`, newest first, 500 entries, never a secret value.
- **Consequences:** Aliases work in the terminal frame, not in plain runs. `terminate` sends SIGTERM to
  the shell; children it started may outlive it (a process group is a follow-up). A command with a
  `keychain:` value or `gate = true` was refused until local-009.

## local-009: Secrets in the login keychain, Touch ID only where asked

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** Secrets must live in the macOS Keychain and never in the registry, the history or a log;
  some commands must ask for Touch ID. Clark chose, when asked: Touch ID only for `gate = true` commands,
  a ⌘K section in the main window for the secrets screen.
- **Options considered:**
  1. **Data-protection keychain with SecAccessControl**: per-item biometrics, but it needs an application
     identifier entitlement and provisioning, which a SwiftPM build signed with a self-made certificate
     does not have.
  2. **Generic-password items in the login keychain**: chosen. Service = the bundle identifier, account =
     the secret's name. Access is the Keychain's own: tied to the identifier and the signing certificate.
  3. **Touch ID on every secret use**: offered, declined; the Keychain guards the items, the gate is explicit.
- **Decision:** `Secrets.SecretStore` (names, get, set/replace, delete; listing reads attributes only so it
  never prompts). `AppModel.launch` fetches each `keychain:` value into the environment and the redaction
  list; a missing or denied secret refuses the run with the fix. `Gate.ask` wraps LocalAuthentication's
  `deviceOwnerAuthentication`: Touch ID with the password as fallback, every run, the command's name in
  the prompt; cancel means no run. The embedded terminal cannot be redacted and the README says so.
- **Consequences:** With ad-hoc signing the Keychain asks again after every rebuild (local-010). Secret
  values exist in the app's memory while a run is prepared and in the child's environment; a program that
  prints them in the terminal frame shows them.
- **Validation:** `SecretsTests` round-trips against the login keychain under a throwaway service and
  removes its items. The live window was driven with a test instance under its own service.

## local-010: A self-made signing certificate, kept out of git

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** Keychain access follows the signing certificate; this Mac had none, and Clark chose to make
  one in Keychain Access rather than have it generated from the command line.
- **Decision:** `scripts/bundle.sh` signs with `SIGN_IDENTITY`, else the first line of a git-ignored
  `.sign-identity` file, else ad-hoc. `make identity` lists the Mac's code-signing certificates and what
  the file names. README gives the three Keychain Access steps.
- **Consequences:** Each Mac makes its own certificate; nothing about signing is shared or committed.

## local-011: Three doors, one writer

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** Adding a command meant editing TOML by hand. Clark asked whether that was a repeatable
  process and chose, when asked, all three doors: a ⌘N form, a `great-gui add` command line, and an
  `add-command` agent skill in the style of updater's add-package.
- **Options considered:** rewriting the whole file through TOMLKit's encoder (loses comments and order);
  appending a rendered block (chosen); swift-argument-parser for the flags (declined: a few flags, no new
  dependency).
- **Decision:** `RegistryWriter` builds a command from text, validates it by rendering and parsing it with
  the loader (so every rule and message is the loader's), appends one block to the file as it is, re-parses
  before writing, and refuses an existing name. The form, `CLI.add` and the skill (which drives the CLI) all
  go through it. `bin/great-gui` runs the binary inside the app bundle so the Keychain sees the same app;
  `make install` links it into `~/.local/bin` and the skills into the agents' skill folders.
  `great-gui run` refuses gated commands: Touch ID belongs to the window.
- **Consequences:** Editing and deleting a command remained file edits until local-014. Hand-parsed flags:
  `--help` is the reference. The CLI prints the design's glyphs without colour.
- **Validation:** `RegistryWriterTests` (specs, quoting, round trip, append, duplicates, hand-written text
  kept, auto-commit only in a repository); the form and the CLI driven live on a test instance.

## local-012: The registry is its own private repository, and every add is a commit

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** The registry lives in `~/.great-gui`, outside the app repo, and has to reach the work Mac.
- **Decision:** `~/.great-gui` is a git repository pushed to the private `cwkoenigs/great-gui-registry`
  (chosen name and visibility). When the folder is a repository, the writer commits `add NAME` after a
  successful add; it never pushes. Secrets are never in the file, only their names.
- **Consequences:** The work Mac clones the registry to `~/.great-gui` before first launch; otherwise the
  app writes its example there and the clone would conflict. History and the signing file stay out of it.

## local-013: A second, native look over the same model

- **Status:** Accepted
- **Date:** 2026-11-09
- **Context:** Clark meant a modern UI that follows the terminal design, as native to macOS 27 as possible,
  on a Mac fleet where 26.7 must still run it. The SDK showed what 27 adds to SwiftUI: 35 declarations
  (document APIs, `reorderable`, `TabsPickerStyle`, navigation transitions) against 319 for 26.0, the
  Liquid Glass release. Clark chose: the terminal design's roles for palette and type, modern as the
  default look, the menu-bar extra later, the floor kept at 26.
- **Decision:** `Sources/GreatGUI/Modern`: `NavigationSplitView` (sidebar · commands · detail), stock
  glass chrome, `.glassProminent` Run and `.glass` Stop, `ToolbarSpacer`, `scrollEdgeEffectStyle`,
  `glassEffect` capsules for the status chip and the history stats, `ContentUnavailableView` for empty
  states, `Table` for secrets and history, sheets for ⌘N and for a secret, a `Settings` scene; the
  detail's Output · Terminal · History picker is `.tabs` under `#available(macOS 27, *)` and segmented
  otherwise. `Palette` maps the terminal roles onto what the app draws itself. The look is an
  `@AppStorage("look")` the Look menu and Settings switch; the window's content swaps.
- **Consequences:** Two looks means two views per new feature until one wins. Offscreen snapshots do
  not draw glass, so the modern look is verified live. The sidebar selection is bound through an
  optional so SwiftUI never picks a row on its own.
- **Validation:** Driven live on a test instance: run with streamed output and the status chip, a
  parameter run, the terminal tab with the shell and its end, the Secrets and History tables, the ⌘N
  sheet. Tests unchanged (34); both toolchains build.

## local-014: Edit, delete and reorder rewrite one block, not the file

- **Status:** Accepted
- **Date:** 2026-11-10
- **Context:** Clark found no way to edit a command in the window and the + easy to miss. He chose, when
  asked: the same form as New, filled in; Delete (asked first) and reordering by drag, not Duplicate; both
  looks; `great-gui edit` and `remove` for the skill; a New Command button at the foot of the sidebar.
- **Options considered:** regenerating the file from the model through TOMLKit's encoder (drops comments,
  hand formatting and order); editing in place in the detail pane (more native, more work, two looks
  diverge); rewriting only the block named (chosen).
- **Decision:** `RegistryWriter` reads the file as a preamble and `[[command]]` blocks, each block the
  comment lines directly above its header through the line before the next block, named by the TOML
  parser. `replace` renders the new command between the old block's comments and trailing blank lines;
  `remove` drops the block and its comments; `reorder` takes every name once and puts the blocks in that
  order with one blank line between. All three re-parse the whole file before an atomic write, as `append`
  does, and auto-commit `edit NAME`, `rename A to B`, `remove NAME` or `reorder commands`. The form's text
  fields are filled by the inverses of the spec parsers (`paramSpec`, `envSpec`). In the window: ⌘E and
  an Edit toolbar button open the form filled; a row's context menu has Run, Edit…, Delete…; ⌘⌫ asks in
  a confirmation dialog (modern) or an approval frame (terminal); drag reorders the modern list while no
  filter hides rows, ⌥↑↓ move the selected command within its group in the terminal look. Edit Registry
  File moved to ⌥⌘E. `great-gui edit` overlays the flags given on the command as it is.
- **Consequences:** A parameter description containing `=` or `;` does not round-trip through the form's
  text notation; the CLI and the file do. History stays under the old name after a rename. Reordering
  normalises the blank lines between blocks to one. A block the splitter cannot name (unusual shape) is
  refused with a pointer to the file, never guessed at.
- **Validation:** `RegistryEditTests` (split keeps every byte; replace keeps comments, spacing and the rest
  of the file and refuses unknown or duplicate names; remove takes the comment too and leaves one trailing
  newline; reorder keeps blocks whole and needs every name once; spec round trips). Both looks driven live
  on a test instance with its own registry, history and Keychain service.

## local-015: Updating is a pull and a rebuild, from the shell or the app menu

- **Status:** Accepted
- **Date:** 2026-11-10
- **Context:** Clark asked how the app updates itself. It did not: the bundle lives in the checkout and
  only `make app` renews it, while the shim and the skills are symlinks. He chose a `make update` target
  plus a menu item that runs it from inside the app.
- **Options considered:** a Sparkle-style updater with signed releases (far too much for one person's app
  on two Macs); a copy in /Applications that an update step recopies (one more thing to drift); pulling
  and rebuilding in place (chosen).
- **Decision:** `scripts/update.sh` notes whether the app is running (`pgrep -a`: from the app's own
  terminal the app is an ancestor, which macOS pgrep skips by default), pulls fast-forward only (stopping,
  with nothing rebuilt, when it cannot), runs `make install`, and, when run from a shell with the app open,
  quits it by Apple event, falls back to a signal, and reopens it. Run from the app (the environment says
  so), the script leaves the relaunch to the app: an Apple event from inside the app's own shell does not
  reach it, so the app quits itself when the run exits 0 and a detached shell reopens the bundle a second
  later. The app menu's Update…
  (and a button in Settings) runs `make update` in the checkout the bundle was built in, found two levels
  above `Bundle.main.bundleURL`, as an interactive run: the terminal look shows it on the rail, the modern
  look in a sheet that cannot be dismissed while the shell runs, because tearing the terminal down would
  kill the build. A build that is not inside a checkout gets a note saying where to update.
- **Consequences:** `start` no longer needs a loaded registry, so updating works when the registry file is
  broken. The history records the update as a tty run. A pull over uncommitted local changes is attempted
  and reported, not refused.
- **Validation:** `make update` from a shell with the app open; Update… from the app menu in the modern
  look, watched to the relaunch.

## local-016: Teammates install by building; no Apple account anywhere

- **Status:** Accepted
- **Date:** 2026-11-10
- **Context:** Clark wants his team to use the app as end users, and the agreement from the start was no
  Apple account. A downloaded app needs a Developer ID and notarization to pass Gatekeeper on current
  macOS, whatever it is written in; that is a platform rule, not a cost of Swift.
- **Options considered:** a Developer ID through the company's or a personal Apple Developer membership
  (not now); a downloadable zip with Sparkle and the self-signed certificate (Open Anyway once per Mac,
  hosting without a login, a public zips-only repository or a company server; kept as the next step if the
  install command proves too much); installing by building on each Mac (chosen).
- **Decision:** `scripts/install.sh`, run once from a terminal: checks macOS 26, installs Apple's free
  command-line tools when absent, clones over HTTPS (port 22 is often closed on office networks; the gh
  login or a token authenticates the private repository), pulls, installs JetBrains Mono through Homebrew
  when Homebrew is there, runs `make install`, makes `~/.great-gui` a git repository, and opens the app.
  `make install` also links the bundle into `~/Applications` so Spotlight launches it. From then on the
  app menu's Update… keeps the copy current. Registries stay personal: the example on first launch, or a
  clone.
- **Consequences:** Each Mac compiles its own copy (about a minute) and needs read access to the private
  repository, so teammates are added as collaborators. The Keychain's one-time prompts per secret remain
  unless the Mac makes the self-signed certificate. The same installer serves the work Mac.
- **Validation:** Run from outside any checkout with `GREAT_GUI_HOME` pointing at a scratch folder: cloned,
  built and linked in 45 seconds; the links were then pointed back at the real checkout with `make install`.

## local-017: Scheduled commands are launchd agents written from the registry

- **Status:** Accepted
- **Date:** 2026-11-10
- **Context:** Clark asked whether the app could run commands on a schedule, or act as a scheduler. He
  chose, when asked: launchd from the registry, readable phrases, pause and resume, the last run's log in
  the window, and a notification on failure. The self-signed certificate went in first (local-010's step,
  done from the command line with two system dialogs), because background runs read the Keychain and only
  a stable signature keeps it from asking after every rebuild.
- **Options considered:** an in-app timer (nothing runs with the window closed: not a scheduler); cron
  syntax (familiar, less readable, and some forms do not map onto launchd's calendar intervals); launchd
  agents from a `schedule` phrase (chosen).
- **Decision:** `Schedule` in the Registry module parses `every 15m`, `hourly [:MM]`, `daily HH:MM`,
  `weekdays|weekends HH:MM`, `mon,thu HH:MM` and `monthly D HH:MM`, reads back as English and gives the
  next calendar occurrence; a gated, interactive or default-less-parameter command cannot carry one, loudly.
  The `Scheduler` module writes one LaunchAgent per scheduled command (program: the app's own binary, `run
  NAME`; the GREAT_GUI_* overrides and the shell in its environment; stdout and stderr to one log per
  command), and `sync` makes the agents folder match the registry: written and loaded, rewritten after
  unloading, unloaded and removed, or left alone. A paused command is remembered in Application Support and
  stays unloaded through syncs. The app syncs on every registry reload and the command line after every
  write. `great-gui run` records every run in the history (`cli` or `sched`), frames a scheduled run's
  output with a header and footer, trims the log past a megabyte, and posts a notification on a non-zero
  exit; the window asks for notification permission once a schedule exists. Labels, folders and the state
  file follow environment overrides so a test instance never touches the real agents.
- **Consequences:** The history file is now written by two processes, so both go through `append`
  (load, insert, save) and the window watches the file. An interval's next run is only known after its
  first run; the window says "within 15 minutes" until then. Logs are plain files anyone can read; a
  scheduled command that prints a secret prints it into its log. Removing the app leaves the agents until
  `great-gui schedule sync` or `make uninstall` is extended to remove them (a follow-up).
- **Validation:** `ScheduleTests` (phrases, English, errors, next occurrence, registry conflicts) and
  `SchedulerTests` against a fake launchd (plist content, sync idempotence, rewrite and removal, pause and
  resume, log sections and trimming). Live: a one-minute schedule on the test registry, watched to its
  first run in the window and in launchd.

## local-018: The app icon is drawn by code and committed

- **Status:** Accepted
- **Date:** 2026-11-10
- **Context:** The bundle had no icon, so Finder, the Dock and Spotlight showed the generic app. Clark
  asked for one and chose, when asked, a prompt glyph over the framed list and over another tool's mark.
- **Decision:** `assets/make-icon.swift` draws a prompt (❯ in the "you" voice, strong shading to accent,
  and a block cursor in the text colour) on a dark tile with one rule for a frame, in the design system's
  dark roles. `assets/make-icon.sh` turns it into `assets/AppIcon.icns` and `assets/icon.png`, both
  committed; `scripts/bundle.sh` copies the `.icns` into the bundle and names it in `Info.plist`.
- **Consequences:** A build needs no drawing step, so the command-line-tools build is unchanged. The six
  colours are repeated in the script, not read from `Tokens.swift`: a new token export that changes them
  means editing the script and running `assets/make-icon.sh`. One icon serves light and dark.
- **Validation:** `make app`, the signature verified, and the icon read back through `NSWorkspace` as
  Finder shows it.

## local-019: Whole credential files in the Keychain, as a path or as an environment

- **Status:** Accepted
- **Date:** 2026-11-10
- **Context:** Clark asked for a way to hold a whole `.env` or a Snowflake `connections.toml` securely.
  Secrets were single values placed in a command's environment (local-009). The app goes to teammates,
  and he ruled that a secret's value must never move between Macs.
- **Options considered:** an env file only, never on disk (fits `.env`, not a file a tool reads from a
  fixed path); a file restored to its path (fits `connections.toml`); both (chosen, when asked). A second
  registry file for the pointers (two files to keep in step; declined) or `[[file]]` in `commands.toml`
  (chosen). A digest in a Keychain attribute so the list never reads a value (it would let anyone running
  as the user test guesses against a short file offline; declined) or comparing bytes (chosen).
- **Decision:** `[[file]]` (name, path, mode, desc) is a pointer; the bytes are one generic-password item
  under the name, in the same service as every secret. `Secrets.FileSecrets` compares, stores and
  restores: an atomic write through a private temporary file, mode 600 by default, folders it creates
  700, 1 MB at most, a file that differs left alone unless forced. A command's `env_file = "keychain:NAME"`
  is parsed by `DotEnv` at run time and joins the environment under the command's own `env`.
  `RunEnvironment.build` is the one place a run's environment is made, for the window and for
  `great-gui run`. `great-gui file [add|store|restore|remove]`, the secrets screen in both looks, and the
  `env_file` field of the form are the doors. The block splitter knows `[[file]]` headers, so editing,
  removing or reordering a command leaves the file blocks alone.
- **Consequences:** Listing the files reads their Keychain copies to compare, so an ad-hoc signed build is
  asked once per file after a rebuild (the certificate of local-010 quiets it); listing plain secrets still
  reads attributes only. Env-file values under six characters are not redacted. A restored file is on
  disk in the clear, as the tool that reads it requires. There is no export, import or sync, by rule.
- **Validation:** `RegistryFilesTests` (parsing, refusals, the writer, command edits beside file blocks)
  and `FileSecretsTests` against the login keychain under a throwaway service (every state, bytes that are
  not text, private folders, no temporary file left, refusals, the `.env` grammar, errors that never quote
  a line). Live: the command line against a scratch registry, service and folder.

## local-020: Agents use secrets by name: `secrets`, `exec`, masked output, a skill

- **Status:** Accepted
- **Date:** 2026-11-11
- **Context:** Clark asked whether his agents could easily use the store, as in "use key x to connect to
  database y". An agent could only reach a secret through a registered command, could not list what was
  stored, had no skill for it, and `great-gui run` printed output unmasked.
- **Options considered:** an approval (Touch ID) the first time an agent uses each key, or none. Clark
  chose none for now: the point is to keep values out of plain text, chats and shell environments, not to
  gate each use.
- **Decision:** `great-gui secrets [--json]` lists names (secrets and files), stored or missing, and their
  users; no flag prints a value. `great-gui exec [--env KEY=keychain:NAME]… [--env-file keychain:NAME]
  [--cwd DIR] -- COMMAND…` runs one unregistered command through `RunEnvironment.build`, so the value goes
  from the Keychain to the child's environment only. `CLI.runMasked` passes stdout and stderr through the
  redactor line by line, for `exec` and for non-interactive `run` (so a scheduled run's log is masked
  too); a value of several lines is also masked per line. Each `exec` lands in the history as mode `exec`
  with the secret names it used. `skills/use-secret` tells agents the three rules and the shapes.
- **Consequences:** Anything that can run `great-gui` as the user can use any stored secret without a
  prompt. Masking stops accidental display, not a command that sends the value elsewhere or writes it to
  a file; approval per key remains the follow-up if that matters. With something to mask, output reaches
  the terminal a line at a time and a prompt without a newline waits for the end; a run with no secrets,
  and an interactive one, keep the terminal as before.
- **Validation:** Live against a scratch registry and Keychain service: `secrets` and `--json`, `exec`
  with a secret, with an env file, with several words and with one shell line, the exit code, the mask on
  stdout and stderr, a missing secret, and the history entry.

## local-021: The app looks for a newer version daily and installs nothing

- **Status:** Accepted
- **Date:** 2026-11-11
- **Context:** Updating was a pull and a rebuild on request (local-015), so a second Mac or a teammate
  had to know there was something to pull. Clark asked whether it self-updates and, offered a quiet check
  that shows Update available without installing, said yes.
- **Decision:** `UpdateCheck.run` does `git fetch --quiet` in the checkout the bundle was built from and
  counts `HEAD..@{u}`, with `GIT_TERMINAL_PROMPT=0`, a batch-mode ssh and a timeout, off the main thread.
  The model looks at launch and when the app becomes active with the last look a day old. A result shows
  as Update available in the sidebar's foot (modern) or a line above the toolbar (terminal), with the
  subjects on hover; clicking is Update…. Settings has the switch (`checkForUpdates`, on), the status and
  Check Now; the app menu has Check for Updates; `great-gui update-check [DIR]` exits 0, 10 or 1.
- **Consequences:** A fetch changes the checkout's remote-tracking refs and nothing else. A Mac without
  network or access sees no notice and no error outside Settings. Installing stays a deliberate click.
- **Validation:** `great-gui update-check` against a scratch clone made one, then seven, commits behind
  (count, subjects, "and N more"), after a pull, on a folder with no upstream, and on this checkout.

## local-022: Team tooling: a shared registry, registered installs, data back

- **Status:** Proposed (to implement)
- **Date:** 2026-11-11
- **Context:** Clark stated what the app is for: agents will use it most; it is a safe spot for people's
  secrets, a secure way to interact with their machine, and the way the team pushes its tooling to them.
  Pushing tooling does not exist: an update delivers the app and its skills only. He also wants to push a
  command to one specific person, with installs registering and reporting back so pushes can be targeted.
- **Decision so far:** recorded in `docs/team-tooling.md`. Chosen: a personal command wins a clash of
  names; team entries arrive automatically each day; a push carries commands, secret checklists (names
  only), agent skills and tool installs (folding in `updater`); an install reports install facts, tool
  inventory, team command runs and secret checklist status, shown in Settings and on by default.
- **Open:** where the team registry lives (its own repository or this one), and the hub that installs
  register with and report to (git only, a small web service, or Snowflake at work). Clark left the hub
  as a to-implement on purpose.
- **Consequences:** Nothing is built. No install reports anything today.

## local-023: The command line answers agents in JSON

- **Status:** Accepted
- **Date:** 2026-11-11
- **Context:** Clark said agents will use the app most. Only `secrets` had `--json`; everything else
  printed lines made for a person, and errors were text on stderr.
- **Decision:** `--json` on every command that reports (`list`, `show`, `check`, `file`, `schedule`,
  `history`, `secrets`, `update-check`): one object on stdout through `CLI.emit`. In that mode `CLI.fail`
  prints `{"ok": false, "error", "fix"}` on stdout too. `show NAME` is new: one command in full, with
  `runnable_from_cli` and its parameters. `history [NAME] [-n N]` is new: what ran, with `exec` runs and
  the secret names they used, which is the record of what agents did. Exit codes are one set: 0 fine, 1
  not as it should be, 2 wrong or refused, 10 an update waiting. The file states carry their advice
  (`FileSecrets.State.advice`), in JSON and in the window alike.
  A word that is not a command now fails with exit 2; it used to fall through and open the window, where
  an agent with a typo would wait forever.
- **Consequences:** The JSON keys are now an interface: rename one and an agent breaks. `run` and `exec`
  stream the command's output as it is, with no envelope; `add`, `edit` and `remove` still answer in text.
- **Validation:** Each command with `--json` against the real registry, parsed by `python3 -m json.tool`;
  the error object for a missing name and for an invalid registry file.

## local-024: Agents use stored secrets without approval

- **Status:** Accepted
- **Date:** 2026-11-11
- **Context:** local-020 left approval per key open ("none for now"). Asked again whether any stored
  secret should need his approval before an agent uses it, Clark said: "no it doesnt need my approval".
- **Decision:** No approval, prompt or Touch ID when an agent uses a stored secret through `exec` or a
  registered command. This is settled, not a stopgap. `gate = true` stays what it was: a per-command
  choice by the person, and such a command runs only from the window.
- **Consequences:** The protection is what local-020 built: values stay in the Keychain, reach only the
  child's environment, and are masked in output. The record of what agents did is `great-gui history`.
  Do not add an approval step or a per-secret "ask" flag without Clark asking for one.
- **Validation:** None needed; no code changed.

## local-025: The Data Science theme was tried and taken out

- **Status:** Rejected
- **Date:** 2026-11-11
- **Context:** Clark found the app drab and asked for the team's look. The team's Data Science system
  (teal and navy, Georgia titles, square panels, a navy sidebar) was built as a second theme
  and made the default.
- **Decision:** Clark saw it and preferred the look the app had: the ds-next terminal design system. The
  theme and its Settings choice were removed the same day; no code from it remains.
- **Consequences:** The app has one palette, the generated `Tokens.swift`. Do not bring the teal and navy
  theme back unless Clark asks. "Less drab" is still open and wants a different answer.

## local-026: The Paper and Ink theme, chosen in Settings and on by default

- **Status:** Accepted
- **Date:** 2026-11-11
- **Context:** After local-025 Clark showed the look he had meant: the theme of an app on his work
  machine, in photos of its stylesheet and of the app. Here it is called Paper and Ink (local-041). It shares the Data Science colours but is a light theme: paper ground, white square cards with
  a hairline, ink text, Georgia headings, mono uppercase labels and tags, teal-dark links.
- **Decision:** `TermPalette` names the token set: `paperInk` (the default) or `dsNext`, stored under
  `palette`, chosen in Settings › Look › Theme. `PaperInkTokens` puts the theme on the thirteen roles,
  so the terminal look takes it as it is. In the modern look the theme also brings its shapes, through
  `Palette`: `heading` (Georgia 500, -0.035em), `sectionLabel` and `pill` (mono, bold, 10pt, uppercase,
  0.12em), `panel` and `codeBlock` (white, square, hairline; no glass), `ground` (paper behind the list
  and the detail), and the link colour as the tint. The sidebar is the system's. The theme is light, so
  Appearance › System shows it light; Dark is the theme's ink section, derived.
- **Consequences:** The values were read off photos, not the file: check them against
  the theme's stylesheet on the work machine and copy changes here by hand. `Tokens.swift` stays
  generated. The theme has no outcome colours: ok / warn / err are ds-next's.
- **Validation:** `make check`; `make snapshot` of the terminal look. The modern look was not seen by the
  agent that built it (window access was declined): Clark checks it by eye.

## local-027: The team's registry is a separate repository, joined by address

- **Status:** Accepted
- **Date:** 2026-11-11
- **Context:** docs/team-tooling.md part 1 was planned with one question open: a separate team repository
  or a file in this one. Clark chose the separate repository, "as long as this can easily be ported to my
  work computer", where the git host is the company's and not GitHub.
- **Decision:** A second `commands.toml`, same format, in a clone at `~/.great-gui-team` (`GREAT_GUI_TEAM`
  overrides; a test registry gets its own `-team` folder). `great-gui team join ADDRESS` or Settings › Team
  clones it; the address is kept only as the clone's remote, so no host is named in the app.
  `Registry.loadAll` merges it behind the person's own: a personal command wins a clash and is marked
  `overridesTeam`; team commands are `origin == .team` and read-only, and editing one adds a personal copy.
  The daily look also runs `TeamSync.sync`: fetch, parse the incoming file, fast-forward only if it loads,
  then report added, changed and removed names. Team `[[file]]` pointers and the secrets team commands
  name are a checklist. `skills/NAME/` folders are linked into the agents, never over a skill that is there.
  `great-gui team init DIR` starts a team repository.
- **Consequences:** A team `schedule` is not armed (`teamSchedule` holds it): the agent chose this, since
  daily delivery plus a schedule is unattended remote execution; Clark may reverse it. A team command can
  still change under a name a person trusts, and they run it by hand. Tool installs are not in the push
  yet. Nothing is reported back (part 2). Leaving moves the clone to the Trash.
- **Validation:** `make check` (TeamTests: the merge, the held schedule, a broken team file). By hand,
  against a throwaway repository and a test registry: join, list, run, a refused edit and remove, a
  changed push, a push that does not parse, an override, leave. The window's Team views were not seen by
  the agent.


## local-028: Tools are listed by the registry and installed only when asked

- **Status:** Accepted
- **Date:** 2026-11-12
- **Context:** The fourth thing a team push carries (docs/team-tooling.md) was tool installs, which the
  separate `updater` project did for one person. Clark chose, on 2026-11-12: a pushed tool installs on a
  click and never by the sync; the methods are brew, cask, uv and script at first; a person can list their
  own tools as well as the team's; updates are reported daily and applied on a click.
- **Decision:** A `[[tool]]` entry in `commands.toml`, the person's or the team's: `name`, `desc`, `method`,
  `pkg`, `bin`, `requires`, and for `script` its own `install` and `update` lines. The package managers
  derive their lines; `pkg` and `bin` are held to plain names so nothing else reaches a shell. A personal
  tool wins a clash and the team's are marked. `ToolProbe` writes one shell script that asks Homebrew, uv
  and PATH what is there, and parses the answer; `ToolRunner` runs it in the login shell. The daily look
  asks what is behind with `versions: false`, so it executes no line and no program a registry names.
  Installing and updating are `great-gui tools install|update` or the Tools screen (⌘U), where the run is
  in an embedded terminal so a password prompt can be answered. A sync reports new team tools by name.
- **Consequences:** `updater` (`cwkoenigs/update-gui`) is superseded and can be retired once its registry
  is copied over as `[[tool]]` entries. A script tool cannot be told to be behind, so it is updated only
  when named, or by `tools update` when it has its own `update` line. A tool found on PATH that its
  package manager did not install is shown and left alone. A team `script` tool is a shell line from the
  team that runs when the person installs it: the window shows the line first (hover), `--json` carries it.
  There is no form for adding a tool in the window; the command line and the file do it. pipx, pip, npm,
  cargo and go are not methods yet.
- **Validation:** `make check` (ToolsTests: loading and its named mistakes, the status parse, a missing
  manager, the quiet daily look, requirement order, the team merge, add and remove). By hand against a
  test registry: status, `--check`, `--json`, add, remove, install, update, a failing installer. That
  hand test used real `brew` and `uv` entries and so changed Clark's Mac (ripgrep installed then removed,
  uv and one uv tool's packages upgraded); AGENTS.md now says to test with `echo` script tools.

## local-029: Every command answers in JSON; a run's own output goes to stderr

- **Status:** Accepted
- **Date:** 2026-11-12
- **Context:** local-023 gave `--json` to the commands that report. The ones that act (`add`, `edit`,
  `remove`, `pause`, `resume`, the `file` actions, `schedule sync`) still answered in text, and `run` and
  `exec` had no result an agent could parse.
- **Decision:** `--json` on every command but `path`, `version` and `help`, one object on stdout each.
  `add` and `edit` answer with the command as it now is; `file store` and `restore` answer with one result
  per file. With `--json`, `run`, `exec` and `tools install|update` send the command's own output to stderr,
  masked as before, and print `{"ok", "code", "seconds", …}` when it ends. For `exec`, only a `--json`
  before the `--` is ours. The exit code is unchanged.
- **Consequences:** The output is not inside the object: the agent chose a stream on stderr over a captured
  string, so long or binary output is not buffered and nothing changes for a command that needs a terminal.
  An agent that wants only the result reads stdout; one that wants the output reads stderr. Clark may
  prefer the output captured in the object instead.
- **Validation:** `make check`. By hand in a test instance: each command with `--json` parsed as one
  object, with its exit code; `exec -- echo --json` passes the flag through.

## local-030: Nine install methods, a form for tools, team changes spelled out, ink buttons

- **Status:** Accepted
- **Date:** 2026-11-12
- **Context:** Clark asked the agent to keep going through the open list without stopping to ask. These
  are the choices made on the way; each is small and can be reversed.
- **Decision:** (1) `pipx`, `pip`, `npm`, `cargo` and `go` join the tool methods, with the lines `updater`
  used; `great-gui tools methods` prints every method's lines. npm can say a tool is behind; the others
  cannot. A `go` tool is found on PATH by `bin`, which defaults to the last part of its module path.
  (2) A tool can be listed and taken off the list in the window: a sheet in the modern look, three fields
  (name, method, package or install line) on the terminal look's tools screen. (3) After a sync,
  `TeamSync.what` says what changed in each changed team command: the run line both ways, secrets gained
  or lost, the suggested schedule, the gate. (4) In Paper and Ink the one button a panel or sheet is for is
  the theme's ink button (`primaryButton`), a second one is outlined (`secondaryButton`), and a mono
  kicker sits above each detail title. Toolbar buttons stay the system's.
- **Consequences:** The ink button's sizes (12pt semibold, 14 by 7 padding, a 1pt outline) are the agent's
  guess, not read from the theme's stylesheet; they are to be checked with the colours on the work Mac.
  The pipx, pip and cargo parsers were written from the tools' documented output and are tested on
  sample text only: this Mac has none of them installed with anything in them.
- **Validation:** `make check` (ToolsTests gained the other managers, with npm's real output from this
  Mac). `make snapshot` shows the terminal look's tools screen with the form. The team change was tried
  against a throwaway repository. The modern look was not seen by the agent.

## local-031: A mirror on the team's own git host

- **Status:** Accepted
- **Date:** 2026-11-12
- **Context:** Clark's company will not use GitHub. He can pull from it on the work Mac; teammates
  install and update from the company's git host, which he sets up himself.
- **Decision:** `scripts/mirror.sh` (`make mirror TO=ADDRESS`) keeps a second remote named `mirror` in
  the checkout, pulls from the checkout's own remote and pushes the same branch and tags there. It never
  forces a push and refuses a checkout with uncommitted changes. The address lives only in that
  checkout's git config. The team's registry needs no tool: its remote is changed with git and each Mac
  joins the new address. The installer's message when a clone fails no longer names GitHub.
- **Consequences:** A teammate's copy follows the mirror, so a new version reaches them only after
  `make mirror` is run again; a scheduled personal command can do that. Whoever runs it needs their git
  sign-in for the company host to work without a prompt.
- **Validation:** Tried against a bare repository standing in for the company host: first push, a
  second run, `--where`, and a clone of the mirror that tracks it. Not tried against a real company host.

## local-032: One look; the terminal look and the gallery are removed

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** The app had two looks over one model and the rule that a feature needs both. An audit
  (docs/state/) found the modern look half unseen and three of its screens unreadable, while every screen
  item cost twice. Clark: "remove terminal look".
- **Decision:** The window is the native one in `Sources/GreatGUI/Modern`. Removed: `Views/MainView.swift`
  (the 80-column window), `GalleryView.swift`, `GallerySession.swift`, the Look menu, the `look` and
  `theme` settings, ⌘T and ⌘⇧G, and the model state only the terminal look used (the parameter form,
  `secretsOpen`, `toolsOpen`, `cancel`, `activate`, `move`, `moveSelected`). `TerminalPane.swift`, the
  embedded terminal an interactive command runs in, moved to `Modern/`. `Sources/TerminalDesign` is kept
  whole: the window reads its colour roles, its mono face and the terminal palette from it, and its tests
  still run.
- **Consequences:** ⌥↑ and ⌥↓ reordering is gone; drag in the list remains. Esc no longer walks back
  through panes. A saved `look = terminal` setting is ignored. The grid primitives in `TerminalDesign`
  (Banner, Frame, SlashMenu and the rest) are now drawn by nothing in the app; cutting them is a later
  choice. local-006 to local-030 describe both looks where they say "the terminal look"; they are history.
- **Validation:** `swift build`, `swift test` (74 tests). The window was opened from a scratch bundle and
  clicked through after the change (docs/state/LOG.md).

## local-033: `make snapshot` draws the window, off screen

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** `make snapshot` drew only the terminal look, which is gone (local-032). Three screens of the
  window had shipped without anyone seeing them.
- **Decision:** `GreatGUI --snapshot DIR` builds the window in an `NSWindow` that is never shown, lets it
  lay out, and writes its view tree to a PNG: seven screens (commands, a finished run, a failed run, tools,
  secrets, history, an empty registry) in both themes, light and dark. Theme and appearance reach the
  views through the argument domain, so no setting is read or written. Each screen has its own model over
  the example registry with made-up status, a Keychain service nothing is stored under, and
  `AppModel.stage(...)` for rows and runs; a staged model never asks the Keychain.
- **Consequences:** What macOS draws with glass or vibrancy does not come out off screen: the sidebar's
  rows, glass toolbar buttons, the selected segment's label. Sheets are not drawn. A snapshot shows layout
  and theme, not those; the real window is still the proof.
- **Validation:** 28 files written and looked at; content and detail columns match the real window.

## local-034: The installer names no host; a build says what it was built from

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** The README and `install.sh` pointed at one git host; teammates clone from another. The
  built app's Info.plist had an empty version, because `bundle.sh` looked for a name `Version.swift` does
  not have. The work Macs can read from github.com, so the build may fetch its packages there.
- **Decision:** `install.sh` has no default address: run from a checkout it uses that; otherwise it needs
  `GREAT_GUI_REPO`. The README's install line says `ADDRESS`. The wait for Apple's command-line tools
  ends after twenty minutes with a message. When `~/.local/bin` is not on PATH the installer asks, in a
  terminal, whether to add one line to `~/.zprofile`. It honours `GREAT_GUI_REGISTRY` and `GREAT_GUI_TEAM`.
  `bundle.sh` reads `static let string`, fails loudly when it finds no version, and writes the short commit
  (with `+changes` for a tree with uncommitted tracked changes) as `GreatGUICommit`; `great-gui version`
  and Settings show `0.1.0 (commit)`.
- **Consequences:** `great-gui version` prints more than a bare number. A debug binary outside a bundle
  shows the bare version. The packages still come from github.com at build time.
- **Validation:** `sh -n` on the scripts; the no-address refusal and the PATH question's three answers run
  in a throwaway home folder (the terminal check stubbed); the version lines run on their own; a scratch
  bundle with the key printed `0.1.0 (d94ef47+changes)`. `bundle.sh` and `install.sh` were not run whole:
  they replace the app Clark is running.

## local-035: The Keychain is read off the main thread; `make install` makes a signing identity

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** A Keychain dialog froze the window: the read for a run, and the comparison of each
  credential file on the Secrets screen, were on the main thread. An ad-hoc signed build is a new app to
  the Keychain after every rebuild, so every update asked again, per secret. At work no Apple ID,
  account or email may be involved (Clark).
- **Decision:** A run that needs a secret goes to a new status, `unlocking` ("reading the Keychain"),
  while `RunEnvironment.build` runs detached; the answer is matched to the run by a new `RunState.id`.
  The Secrets screen's look runs detached and only the newest answer is taken. `scripts/identity.sh`,
  run by `make install`, makes a self-signed code-signing certificate on the Mac with `openssl`, imports
  it into the login keychain and names it in `.sign-identity`; a Mac that has one keeps it. No trust
  setting is added: `codesign` signs with a self-signed identity that is named outright.
- **Consequences:** Run is disabled while a run is unlocking, so a second click cannot queue a second
  dialog. Rows on the Secrets screen arrive a moment after the screen. Store, Restore and Save in the
  Secrets screen still call the Keychain on the main thread. The first build signed with a new identity
  asks for the login password once, so `codesign` may use the key.
- **Validation:** In a scratch bundle with a made-up secret: with the Keychain dialog up, a click on
  another row selected it; after Deny the command said why it did not run. The identity script was run
  whole against a throwaway keychain (made, named, found again); an app was signed with such a
  certificate. Not run against a real login keychain: this Mac already has `the-great-gui dev`.

## local-036: One visual language, drawn from the theme

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** The window showed three styles at once under Paper and Ink: the theme's square ink buttons
  and pills, the system's blue selection and sidebar icons, glass Run and Stop, rounded sheets and grouped
  forms. Secrets, History and Tools squeezed their rows into a 320-point column beside a wide help panel,
  with names cut and buttons off the edge. Clark: "it just feels blah", and of committing to the theme,
  "ok I commit".
- **Decision:** Everything the app draws comes from `Palette` and a new `Modern/Kit.swift`: row selection
  (`selected`), fields (`fieldBox`, `LabeledField`, `formSection`), sheets (`SheetFrame`), full-width
  screens with their table rows (`Screen`, `HeaderRow`, `tableRow`), tabs (`Tabs`), the status chip
  (`chip`), row actions, notes and empty states. The window is two columns: the sidebar, and beside it
  either the command list with the detail or one full-width screen; Tools, Secrets and History are such
  screens, with their how-to behind a "?". Run, Stop and Edit sit beside the command's name as the
  theme's buttons; the toolbar holds only the search field. Sheets scroll inside a fixed frame with their
  actions always in view, and labels sit above left-aligned fields. Settings is drawn in the theme and
  follows its own Appearance. Three small touches Clark was offered and took by saying go: the two pixel
  animals on empty screens and in a new About sheet; a band of the accent colour that crosses the status
  chip while a run is going; a mark on each row of the list for how its last run ended.
- **Consequences:** The system's `Table`, grouped `Form`, segmented picker and list selection are no
  longer used; column sorting and resizing go with `Table`. ↑, ↓ and Return in the list are handled by
  the app. A team command in the group `team` shows one pill, not two. The system still draws the window
  frame, the sidebar's material, menus, pop-up buttons, switches and the search field. glass remains only
  inside `Palette`, for ds-next's buttons and panels. local-013 and local-030's "toolbar buttons stay the
  system's" no longer hold. The Paper and Ink colours and the ink button's sizes are still unchecked against
  the theme's stylesheet, which is on the work Mac.
- **Validation:** Every screen and sheet opened in a scratch bundle and looked at: commands, a run in
  progress, Tools, Secrets, History, the command form, the copy of a team command, Settings, About, in
  Paper and Ink light and dark and in ds-next light. `make snapshot` draws seven of them off screen.

## local-037: A team command's schedule stays held back; a copy offers it as a switch that starts off

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** A team schedule was never armed by a sync (local-027), but the form that copies a team
  command was prefilled with the team's schedule, so Save armed it without saying so. Clark had not
  confirmed either behaviour; he took the recommendation.
- **Decision:** The copy form's schedule field starts empty. The team's schedule is shown as a switch,
  "Also run it by itself on this Mac, daily at 03:00", off, with what on and off mean. Any non-empty
  schedule in the form shows "Saving arms it". The rest of local-027 stands.
- **Consequences:** Copying a scheduled team command and pressing Add gives a command that runs only
  when asked. `great-gui add NAME` for a team command's name never copied the schedule and still does not.
- **Validation:** `testACopyOfATeamCommandDoesNotCarryItsSchedule`; the form seen on screen with the
  switch off and the schedule empty; the scratch agents folder stayed empty.

## local-038: `--capture` puts a run's output in the result object

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** Under `--json`, `run` and `exec` stream the command's own output to stderr and the result
  object holds the exit code and the secret names. An agent had to capture stderr itself. Whether that
  was right had not been decided; Clark took the recommendation.
- **Decision:** The stream stays as it is. `run --json --capture` and `exec --json --capture -- …` also
  put the output in the object: `output` (masked exactly as the stream is, stdout and stderr in the order
  they arrived) and `output_truncated`. The newest 64 KB are kept, cut at a line. `--capture` without
  `--json` is refused (exit 2), as is `--capture` on an interactive command, whose output is a terminal's.
- **Consequences:** With `--capture` the child's stdout and stderr are pipes even when there is nothing
  to mask, so a program that checks for a terminal sees none. `tools install|update` do not take it.
- **Validation:** `testCaptureKeepsTheNewestBytesAndStartsAtALine`; run in the scratch instance: a plain
  run, a failing run, an `exec` with a made-up secret (`out •••••` and `err •••••` in `output`), 200 KB of
  output (65,531 bytes kept, `output_truncated` true, starting at a whole line), both refusals.

## local-039: The hub waits

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** Registered installs, targeted pushes and reporting back are designed in
  `docs/team-tooling.md` with three candidates for the hub and none chosen. The first Mac to get the app
  is Clark's work computer alone.
- **Decision:** Not built now. When three or four teammates are on part 1 and "who has this?" becomes a
  real question, start from the git-only candidate.
- **Consequences:** Until then `great-gui team --json` on each Mac answers it one Mac at a time.
- **Validation:** None needed.

## local-040: A Mac starts in dark ds-next; the dog and the cat stay in the window

- **Status:** Accepted
- **Date:** 2026-11-13
- **Context:** Paper and Ink light was the default (local-026). Clark, after seeing both, preferred the dark
  ds-next theme with the cat and the dog. The animals had been always on screen in the terminal
  look's header; after local-032 they showed only on empty screens and in About.
- **Decision:** Until a choice is made in Settings, the theme is ds-next (`TermPalette.fallback`) and the
  appearance is dark (`Palette.defaultAppearance`). The dog and the cat sit at the foot of the sidebar
  with the name and version, in every theme, and open About (`Mascots` in `Kit.swift` draws them at any
  height). ds-next got its own buttons and panels from the theme, rounded and in steel, so no view and
  no palette uses a glass effect any more.
- **Consequences:** A Mac that already chose a theme or an appearance keeps it. Paper and Ink is one setting
  away and unchanged. local-036's note that glass remains inside `Palette` for ds-next no longer holds.
- **Validation:** A scratch bundle with no saved settings opened in dark ds-next; a run, Tools and the
  command form were looked at in it. `make check`.

## local-041: The second theme is called Paper and Ink, and the repository is public

- **Status:** Accepted
- **Date:** 2026-11-17
- **Context:** Clark installs the app on a second Mac without signing in to a git host there, so anyone
  must be able to read the repository. The second theme carried the name of the place its look came
  from: in the code, in Settings and in these decisions.
- **Decision:** The theme is `paperInk`, "Paper and ink" in Settings, kept in
  `Sources/TerminalDesign/PaperInk.swift` (`PaperInkTokens`; `Palette.paper` where a view asks which
  shapes to draw). Its colours and shapes are unchanged. Earlier entries here were reworded to the new
  name. The public repository starts from one commit; the history before it is kept privately.
- **Consequences:** A Mac that had chosen the theme under its old stored name starts in ds-next again
  and picks Paper and Ink in Settings once; no code reads the old name. Nothing that names an employer,
  a work product or a file on a work machine goes into this repository, a commit message included.
- **Validation:** `make check`. No file and no commit in the public repository carries the old name.

## local-043: Set up reusable credentials once

- **Status:** Accepted
- **Date:** 2026-11-22
- **Context:** A user wants to set up a credential in Great GUI, test it, and reuse it from commands
  without re-entering its value. The initial validation target is a local build with an isolated
  registry and Keychain service.
- **Decision:** Give each reusable connection a label, destination, credential method, and
  references to its Keychain items. Let the user set it up and select it from the existing command
  editor. Reuse the existing secret and file storage paths. Keep connection settings in Keychain
  when the client can consume them at runtime. If a client requires a credential file, show its
  local file requirement during setup. Profiles are local presets scoped to the registry and
  Keychain service. Applying one copies its references into the command so the existing command-line
  and scheduler paths continue to run it.
- **Test behavior:** Use an explicit, provider-specific read-only check when available. Report
  Keychain availability separately from live authentication. A test result can show the check and
  its outcome. Credential values stay out of output, history, registry commits, and model context.
- **Scope:** CLI and API credentials. Browser logins need separate
  decisions about destination matching, browser autofill, and account sign-in policy.
- **Validation:** `make check` passed. Isolated tests reused one Keychain item in two commands,
  rotated it, and verified both commands received the replacement. The tests exercised a missing
  reference, a rejected check, and a credential file that needs restoring. In the signed app,
  a profile and an existing saved command checked a loopback API after rotation.

| Phase | State | Exit criteria |
| --- | --- | --- |
| Discovery | Complete | Existing Keychain storage, credential-file storage, and runtime injection provide the starting points. |
| Scope review | Complete | CLI and API credentials approved. |
| Implementation | Complete | Profile setup, selection, explicit checks, and rotation are available. |
| Local verification | Complete | Automated and signed-app checks passed with isolated credentials. |
| Cleanup | Complete | The README describes the workflow. |

## local-044: Open canon and team skills from Great GUI

- **Status:** Accepted
- **Date:** 2026-11-23
- **Context:** The knowledge base is already rendered by ds-next. People need one place to open
  it without starting a separate ds-next terminal session.
- **Decision:** Add Docs to the Library sidebar. Great GUI runs `ds-next docs` outside a project
  to build canon and team skills and hosts the completed static site on IPv4 loopback. macOS
  assigns a free port when the listener starts. The Docs screen opens the site in WebKit and
  offers a separate browser action.
- **Refresh:** Publish the completed output at the existing cache path and reload the open page.
  Keep the current site available during builds and after a build failure. Close the listener
  when Great GUI exits.
