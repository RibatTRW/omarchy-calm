# CONTEXT — omarchy-calm

Project instructions for agents working on this repository. This file exists
**instead of** a root `AGENTS.md` or `CLAUDE.md`, and that is a hard
requirement, not a preference — see "Marketplace constraints" below.

## What this is

A single Omarchy shell plugin, `ribattrw.calm`, delivering three things:

1. fullscreen paced-breathing sessions (1 keypress/click, 3-minute default),
2. local CC0 ambient soundscapes (bundled + user-folder override),
3. non-coercive break reminders (quiet heads-up → session only on a real pause).

Cross-cutting: a compact bar widget with live session progress, DND engaged
and restored around sessions, and a stats surface limited to one "day kept"
dot.

## Layout

| Path | Role |
|---|---|
| `manifest.json` | plugin manifest; `barWidget.schema` **is** the config surface |
| `CalmOverlay.qml` | session surface + reminder scheduler + sole audio owner; `keepLoaded: true` |
| `BarWidget.qml` | bar widget (display + click handling only) |
| `CalmModel.js` | pure helpers: breath math, schedule/deadline math, state, audio argv |
| `assets/audio/*.ogg` | five bundled CC0 loops — see `CREDITS.md` |
| `README.md`, `CREDITS.md`, `LICENSE` | marketplace-required root docs |
| `CONTEXT.md` | this file |

State lives in one file: `~/.local/state/omarchy/calm.json`
(`days` booleans, current `session`, `ambient` flag). The overlay is its only
writer; the widget only reads it. Config lives only in the widget's inline
entry in `~/.config/omarchy/shell.json`.

The state file is deliberately **flat** in `~/.local/state/omarchy/`, not in a
`calm/` subdirectory: `FileView.setText()` never creates missing parent
directories, and a watcher that starts on a file which does not exist yet
never fires when it appears. The widget therefore watches the *directory*
(which always exists and survives the writer's `atomicWrites` rename) and
reloads the file from there — the same pattern first-party `bar/Bar.qml` uses
for its `bar-off` flag.

## Constraints that bind changes here

- **No root `AGENTS.md` or `CLAUDE.md`, ever.** The marketplace installs a
  full `git clone` with no install-time exclude, and rejects root-level
  agent-control files. Agent-relevant docs belong in `CONTEXT.md` (this file)
  or `docs/`. Evidence: marketplace issues #6984, #5123, #5062, #4839.
- **No network requests, no elevated privileges, no install hooks.** The
  category's READMEs and the marketplace security baseline both treat this as
  table stakes. Local file in, local playback out.
- **No input logging, no screen-time tracking.** Idle awareness must come from
  Omarchy's `omarchy.idle` service, never from a watcher of our own.
- **Absolute wall-clock deadlines for every timer**, never a decremented
  interval tick — suspend safety. `CalmModel.nextDeadline`,
  `sessionEndMs`, and the `startMs`/`endsAt` state fields are all epoch ms.
- **Do not add root-level agent docs, dashboards, history views, counts, or
  medical claims.** The stats surface is one dot by design.

## Omarchy plugin API facts (learned from source, easy to get wrong)

- `shell.serviceFor("omarchy.notifications")` from a third-party plugin returns
  **null**: `_serviceLookup` resolves only the plugin's *own* service
  (`pluginServiceFor` → `pluginOwnsTarget`). The `firstPartyServiceFor` path
  that exposes DND/idle is only handed to full `kind: "bar"` plugins.
  → DND and idle are reached through their **IPC targets**:
  `omarchy-shell notifications dndState|setDnd <bool>` and
  `omarchy-shell idle status`. Do not use `-q` when the answer matters — it
  suppresses stdout even on success.
- Bar widgets receive only `bar`, `moduleName`, `settings`. They summon via
  `omarchy-shell shell summon <id> '<json>'`.
- `keepLoaded: true` is what keeps the reminder scheduler alive between
  summons; without it the overlay is destroyed when closed.
- Fullscreen overlays normally use `ExclusionMode.Ignore`, which covers the
  bar. This plugin uses `ExclusionMode.Normal` on purpose so the bar — and
  therefore session progress in the widget — stays visible.
- **Imported JS is not hot-reloaded; only QML is.** After changing
  `CalmModel.js`, restart the shell (`omarchy restart shell`) and re-verify.
  Never treat a live-looking reload as proof the code took effect.

## Keybinding

Recommended and documented in `README.md`: **`SUPER + ALT + M`**.
`SUPER + SHIFT + M` was the original ask but collides with the default Music
binding (Spotify) in Omarchy's `default/hypr/bindings/applications.lua`, and
`SUPER + ALT + M` is free there. The plugin never edits the user's Hyprland
config itself.

## Marketplace submission notes (for whoever files it)

- Repo must keep: root `README.md` with install **and** removal instructions,
  root `LICENSE`, root `manifest.json`, no root `AGENTS.md`/`CLAUDE.md`.
- Request the still-missing **`wellness` tag** under "Suggest a missing tag" —
  three earlier submissions (#93, #819, #3894) asked for it and it still does
  not exist. Suggested category: `Other`.
- Document external dependencies (README has the table): `mpv`, plus
  first-party `omarchy-shell` / `omarchy-notification-send`.
- Every update needs a `[Verify]` issue against the exact 40-char SHA;
  snapshots show `Unverified` until re-checked.

## Verifying changes locally

- `omarchy plugin validate .` — same checks the shell runs at load.
- JS logic is testable standalone: strip the `.pragma library` line and run
  `CalmModel.js` under node with assertions.
- For anything visual, live verification on a shared desktop must: prove the
  focused window before synthesising any input (prefer not to synthesise at
  all — drive sessions through `omarchy-shell shell summon/hide`), keep the
  fullscreen overlay off the operator's working workspace, and close it in the
  same step that opened it. If safe UI verification is impossible, say so
  explicitly rather than skipping silently.
- After a shell restart, confirm behaviour from logs/IPC output, not from the
  screen looking right.
