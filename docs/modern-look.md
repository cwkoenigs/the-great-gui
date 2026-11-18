# The modern look · plan (built 2026-11-09; see DECISIONS local-013)

> 2026-11-13: the terminal look and its gallery were removed (DECISIONS local-032). This page is the record of how the native window came about; where it says "both looks", there is now one.

A second presentation of the same app, native to macOS 26/27, chosen in the Look menu and remembered.
Nothing that acts changes: the model, the registry and its writer, the runner, the Keychain store,
the Touch ID gate, the command line and the skill are shared with the terminal look.

## What "27-looking" is, read from this Mac's SDK

| Release | New SwiftUI declarations | What they are |
|---|---|---|
| 26.0 | 319 | Liquid Glass: `Glass`, `.buttonStyle(.glass / .glassProminent)`, `ToolbarSpacer`, `scrollEdgeEffectStyle`, `backgroundExtensionEffect`, `searchToolbarBehavior`, `tabViewBottomAccessory`, `safeAreaBar` |
| 26.1 | 7 | toolbar item visibility priority |
| 26.4 | 10 | task executor preferences |
| 27.0 | 35 | document reader/writer APIs, `reorderable` lists, `TabsPickerStyle`, `AnyNavigationTransition` |

So the look is 26's glass, delivered mostly by system chrome. From 27, behind `#available`: the tabs
picker for the detail's Output · Terminal · History switch. Reordering came with local-014 through
`ForEach.onMove`, which drags on 26 and 27 alike, once the writer could reorder the file.

## The window

- **Sidebar** (system glass material): All · one row per group with a count · Secrets · History.
- **Content**: the commands of the selection in a `List`, search in the toolbar (`.searchable`,
  minimizing), rows of name, description and marks for tty / gate / key / parameters as SF Symbols in
  the roles' colours; `ContentUnavailableView` when nothing matches.
- **Detail**: header with name, description and group chip over a `backgroundExtensionEffect`; the run
  line on a code surface in JetBrains Mono; parameters as a grouped `Form`; **Run** as `.glassProminent`
  (⌘↩), Stop (⌘.), a gate badge; a picker between Output (monospaced log, live status chip, exit
  footer), Terminal (SwiftTerm pane) and History (a `Table` of that command's runs).
- **Secrets**: a sidebar destination with a `Table` (name · in Keychain · used by) and a sheet with a
  `SecureField` to add or replace; delete in place.
- **New command**: ⌘N opens a sheet with a grouped `Form` of the same ten fields; Enter validates through
  `RegistryWriter`, appends, commits, selects.
- **Settings** (⌘,): look, scheme, registry path, shell, signing note.
- **Menu-bar extra** (if chosen): the commands by group; picking a plain one runs it and shows the
  outcome; an interactive or gated one opens the window.
- Keyboard parity with the terminal look: ↑↓ · Enter · Esc · ⌘K · ⌘N · ⌘R · ⌘E · ⌘T · ⌘. .

## Palette and type: the choice

- **A. The terminal design's roles** (follows the look you have): the steel accent as the app tint,
  ok / warn / err for marks and outcomes, the neutral ramp for the code surface and the log; system
  materials for chrome; JetBrains Mono for anything that is a command or output; SF Pro for labels.
  No new generator: `Tokens.swift` already carries it.
- **B. The Data Science portal theme** (navy and teal, Georgia headings, square corners, rules not
  shadows): the team's web look. It fights glass, which is rounded, blurred and set in SF Pro; it would
  need a second generator from dashboard-style's tokens.json and would read as a web page in a window.

## Honest limits

- Glass takes the system's grounds: the dark ramp lives in content surfaces, not in the chrome.
- Offscreen snapshots do not render glass faithfully; the look is verified live.
- Two looks means two views per new feature until one wins.
- No `@State`, as before: `@Observable` models, `@Bindable`, `@FocusState`.

## Size

About 900 lines of SwiftUI and a 60-line palette mapping. No new dependencies. Model changes: a `look`
preference and a per-command history query. One session.

## Decisions taken (2026-11-09)

- Palette and type: **A**, the terminal design's roles. No new generator.
- Default look on launch: **modern**; the terminal look and its gallery stay in the Look menu.
- Menu-bar extra: **later**, a follow-up.
- Editing, deleting and reordering commands in both looks: **built 2026-11-10** (local-014).
- macOS floor: **stays 26** (`.macOS(.v26)`), because a Mac on 26.7 must run it; 27 APIs only behind
  `#available(macOS 27, *)`, with a 26 fallback on each.
