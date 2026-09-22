# Calm for Omarchy

Meditation and de-stress for [Omarchy](https://omarchy.org), built for near-zero friction: **one keypress or one click starts a breathing session**, curated open-licensed soundscapes play locally, and gentle break reminders arrive only when you have actually paused.

Plugin id: `ribattrw.calm`

- **Breathing sessions** — a minimal fullscreen session with a paced visual, **3 minutes by default, no setup screen and no decisions after launch**. The breath runs 4 s in / 6 s out, which makes every whole-minute length a whole number of breaths, so a session always ends on a completed exhale. `Esc` ends it early and it still counts.
- **Ambient audio** — five seamless CC0 soundscapes shipped in the repo (`rain`, `waves`, `forest`, `wind`, `fire`), played locally with `mpv`. Nothing streams, nothing is fetched. Your own files can override or extend them.
- **Break reminders** — a quiet low-urgency heads-up on a fixed interval (every 50 minutes, 09:00–20:00 local by default). **There is no skip button and no postpone button.** The session starts only when you actually pause, or when you choose to click the notice. If you are already away, it does not nudge at all.

Plus a compact bar widget that coexists with everything else in your bar: one click starts a session, the same ring shows live session progress, and a single quiet dot appears once today is kept.

## Install

```bash
omarchy plugin add https://github.com/RibatTRW/omarchy-calm.git --enable
```

That is the whole installation. The plugin runs unsandboxed inside `omarchy-shell`, like every other Omarchy plugin — read the code first if you would rather.

Add it to the bar if it is not already there:

```bash
omarchy bar put ribattrw.calm --section right
```

## Remove

```bash
omarchy plugin remove ribattrw.calm
```

Remove the keybinding you added (see below). Nothing else is touched; your config is never rewritten. If you want the local state gone too:

```bash
rm -f ~/.local/state/omarchy/calm.json
rm -rf ~/.config/omarchy/calm
```

## Keybinding

Calm cannot bind a key by itself — Omarchy plugins run **no install hooks**, so nothing you install can quietly edit your Hyprland config. The whole setup is this **one exact line**; paste it once:

```bash
sed 's/--.*//' ~/.config/hypr/bindings.lua 2>/dev/null | grep -q 'o\.bind.*ribattrw\.calm' || echo 'o.bind("SUPER + ALT + M", "Calm — breathing session", [[omarchy-shell shell summon ribattrw.calm "{}"]])' >> ~/.config/hypr/bindings.lua
```

Hyprland reloads its config when a sourced file changes, so the binding is live immediately — press `Super + Alt + M` and a session starts. Until the line is in place, Calm shows a **one-time notification** on first run pointing at it, so the setup is discoverable without the README. The line is idempotent: pasting it twice adds nothing.

To remove the binding:

```bash
sed -i '/ribattrw\.calm/d' ~/.config/hypr/bindings.lua
```

> **Why not `SUPER + SHIFT + M`?** That combination is already taken by Omarchy's default
> **Music** binding (`default/hypr/bindings/applications.lua` → Spotify), so `SUPER + ALT + M`
> is the closest free equivalent and keeps the same `M`. It is free in Omarchy's defaults.

Pass options in the payload if you ever want them: `{"minutes":5,"sound":"waves"}`. Omit it and the session uses your saved settings.

## Settings

Every setting lives in one place — the widget's entry in `~/.config/omarchy/shell.json`, written by `omarchy bar set`:

```bash
omarchy bar set ribattrw.calm minutes 3          # session length, 1-60
omarchy bar set ribattrw.calm sound rain         # rain | waves | forest | wind | fire | none
omarchy bar set ribattrw.calm volume 70          # 0-100
omarchy bar set ribattrw.calm reminders true     # gentle break reminders
omarchy bar set ribattrw.calm reminderMinutes 50 # cadence, 10-240
omarchy bar set ribattrw.calm dayStart 09:00     # first reminder from
omarchy bar set ribattrw.calm dayEnd 20:00       # last reminder before
```

## Ambient audio

Pick a sound with `omarchy bar set ribattrw.calm sound <name>`, then either start a session (the loop plays for the length of the session) or **middle-click the widget** to toggle the loop on its own while you work. All five bundled loops are loudness-matched to the same level, so switching sounds never jumps in volume.

Your own files live in:

```
~/.config/omarchy/calm/audio/
```

A file there with the same name as a bundled one **overrides** it; any other name is simply a new choice you can select with `omarchy bar set ribattrw.calm sound yourname`. Supported extensions: `.ogg .oga .opus .mp3 .wav .flac .m4a`.

## How the reminders behave

- Fixed intervals from an **absolute wall-clock deadline**, so suspending the machine cannot make a burst of missed nudges fire on wake, and the schedule stays correct across sleep.
- Idle awareness is Omarchy's own `omarchy.idle` service — **Calm does not watch your input, log keystrokes, or track screen time**, and it never polls in the background. The service is consulted only at a deadline, and once every few seconds while a heads-up is waiting for you to pause.
- No nudges outside your configured window, and none while you are already idle.
- No skip button anywhere. Ignoring the heads-up simply lets it expire; the next one comes at the next interval.

If Omarchy's idle detection is switched off (**Stay Awake**), Calm cannot tell when you have paused, so the heads-up still arrives on schedule but starting a session is a click or a keypress rather than automatic.

## Progress and stats

The bar widget shows live session progress as a filling ring, and **one quiet dot** once today is kept. That is the entire stats surface: no counts, no numbers, no history view, no dashboard. The day is marked kept the moment a session starts, so leaving early always counts.

## Notifications

Do-not-disturb is engaged for the duration of a session and your previous state is restored afterwards — before any completion notice, so you actually see it. If DND was already on when a session began, it is left alone.

## Roadmap — recommended next improvements

Not implemented yet; ordered by what the research and the shipped competitors
suggest users actually feel.

1. **Breathing pattern presets as a config key** — `pattern = calm | box | 478`.
   Kalm ships seven techniques and Zen three; keeping it a *config* key rather
   than an in-session menu preserves the zero-decision launch.
2. **Completion cue and a soundscape fade** — a soft bell on completion
   (Zen and Stretchly both do this) and a ~4 s fade-out of the loop instead of
   it stopping dead when the session ends. Opt-in, off by default.
3. **Wheel-to-change sound, and the sound name in the tooltip** — today
   picking a soundscape needs `omarchy bar set`; a wheel step on the widget
   would make the shipped loops discoverable without the CLI.
4. **Weekday-aware quiet hours** — e.g. no heads-ups at weekends, in the spirit
   of Stretchly's schedules. Today it is one window for every day.
5. **Reduced-motion mode** — Kalm ships one. A `motion = full | reduced` key
   holding the disc at a fixed size and filling the ring instead of scaling
   would suit anyone the breathing motion bothers.
6. **Cross-monitor sessions** — the widget already shows progress on every bar,
   but the session surface only covers the focused output; spanning all of them
   (Kalm shares state cross-monitor) would make the fullscreen claim literal.
7. **Suspend-aware pause** — deadlines are absolute by design (spec: suspend
   safety), so a session ends on wake. An opt-in `pauseOnSuspend` would hold it
   open instead, leaving absolute deadlines the default.
8. **A configurable pause threshold** — how long you must stop before a
   heads-up starts the session is currently derived from Omarchy's own
   `idle.screensaver`/`idle.lock` so it can never disagree with the compositor;
   surfacing it as `reminderGraceSeconds` would let people tune it.

## Dependencies

Everything is local and unprivileged. No network requests, no elevated privileges, no install hooks.

| Dependency | Why | Present on Omarchy? |
|---|---|---|
| `mpv` | loops the local audio file gaplessly | yes — `omarchy-base` package |
| `omarchy-shell`, `omarchy-notification-send` | IPC and quiet notices | yes — first-party |
| PipeWire stack | audio output | yes — first-party |

## Credits

The bundled soundscapes are CC0 recordings; every source, author, and licence page is listed in [CREDITS.md](CREDITS.md). No AI-generated audio is included.

## License

[MIT](LICENSE). The bundled audio is CC0 and is credited separately in [CREDITS.md](CREDITS.md).
