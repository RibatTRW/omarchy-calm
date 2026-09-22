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
| `assets/audio/*.ogg` | eight bundled CC0 files (five soundscapes + cicada loop + two breath cues), all −36 LUFS — see `CREDITS.md` |
| `tools/verify-loops.py` | seam self-check for any loop re-encode |
| `tools/verify-mix.sh` | acceptance checks A1-A10 for the loudness/mix spec |
| `README.md`, `CREDITS.md`, `LICENSE` | marketplace-required root docs |
| `CONTEXT.md` | this file |

State lives in one file: `~/.local/state/omarchy/calm.json`
(`days` booleans, current `session`, `ambient` flag, `keybindHint` one-time
flag). The overlay is its only
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

## Audio loudness (three layers, build-time normalised mix)

Every shipped file in `assets/audio/` — five soundscapes, the cicada loop,
and the two breath cues — is **loudness-normalised to −36 LUFS integrated,
TP ≤ −1 dBTP** (two-pass EBU R128 measurement applied as one static gain).
−36 LUFS is the mean of the five original beds; the target and the level
table behind every volume default come from the commissioned
audio-science report (2026-09-22). Normalisation is what makes the knobs
mean what they say — the shipped files previously spanned 18.5 LU.

- **Loop seams must survive any re-master**: static gain only on loops, and
  re-check with `tools/verify-loops.py <dir>` (self-calibrating seam check;
  `--self-test` proves it has teeth; one-shot `breath-*` cues are skipped —
  they never loop). Never use a time-varying limiter/normaliser on a loop —
  its state does not survive the wrap.
- **Knob laws, measured — do not “fix” either**: mpv `--volume` is
  *cubic* (gain_dB = 60·log₁₀(v/100): 40 → −23.9 dB, 100 → 0 dB); pw-play
  `--volume` is *linear* 0.0–1.0 (gain_dB = 20·log₁₀(v/100): 20 → −14 dB).
  The defaults are mixed against those laws: `volume 40` (bed ≈ −60 LUFS at
  the sink; system volume sets the listening level — README says 40–55 dBA),
  `cicadaVolume 30` (bed −7.5 dB, a soft background), `breathVolume 20`
  (bed +9.9 dB, ≥ +7.7 dB in-band over the worst soundscape at defaults).
  The earlier −16 LUFS remaster + `volume 70` was superseded by this spec:
  at −36 LUFS assets a 70 knob would leave the breath cues under the bed.
- **Runtime layering** (no runtime EQ, no graph processing, no ducking):
  `CalmOverlay` owns `audioProc` (soundscape) and `cicadaProc` (cicadas,
  `--audio-client-name=omarchy-calm-cicadas`, only while cicadas on AND
  sound ≠ none), plus one owned `cueProc` (`pw-play`, ~13 ms start) fired on
  the `breathAt` label edge of the 50 ms session tick (~63 ms worst-case
  timing budget). PipeWire sums the streams. `sound=none` stays full silence;
  cues never run outside a session.
- Any future loudness work must re-measure the end-to-end tap
  (`parec … .monitor` during a live session), not just file loudness, and
  re-run `tools/verify-mix.sh` (the audio-science report's A1-A10 checks).

## Keybinding

Recommended and documented in `README.md`: **`SUPER + ALT + M`**.
`SUPER + SHIFT + M` was the original ask but collides with the default Music
binding (Spotify) in Omarchy's `default/hypr/bindings/applications.lua`, and
`SUPER + ALT + M` is free there. The plugin never edits the user's Hyprland
config itself.

**There is no plugin mechanism that can register a Hyprland binding.**
Verified facts: `omarchy plugin add` runs nothing from the plugin — no
install hooks exist (`manual/32-shell-plugins.md` states this outright), the
manifest schema validated by `shell/services/PluginRegistry.qml` has no
keybind field, and `luotao.zen`, the shipped exemplar, documents its binding
the same way. So v1.1 ships **shape B**: the README's instruction is one
exact idempotent copy-paste line (`grep -q … || echo 'o.bind(…)' >>
~/.config/hypr/bindings.lua`, held in `CalmModel.keybindHintCommand()` and
asserted against the README by the tests), plus a **one-time in-plugin
hint**: on first shell start the overlay checks `bindings.lua` for
`ribattrw.calm` and, if absent, sends one notification pointing at the line
and sets `keybindHint` in the state file so it never fires again. Do not
 "fix" this with a runtime `hyprctl keyword bind` injection: it is lost on
the next config reload, invisible to the documented config, and silently
diverges from what the user's files say.

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
