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

Calm does not bind any key on install — it only tells you the line to add.

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + M", "Calm — breathing session",
  [[omarchy-shell shell summon ribattrw.calm '{}']])
```

> **Why not `SUPER + SHIFT + M`?** That combination is already taken by Omarchy's default
> **Music** binding (`default/hypr/bindings/applications.lua` → Spotify), so `SUPER + ALT + M`
> is the closest free equivalent and keeps the same `M`.

Pass options in the payload if you ever want them: `{"minutes":5,"sound":"waves"}`. Omit it and the session uses your saved settings.

## Settings

Every setting lives in one place — the widget's entry in `~/.config/omarchy/shell.json`, written by `omarchy bar set`:

```bash
omarchy bar set ribattrw.calm minutes 3          # session length, 1-60
omarchy bar set ribattrw.calm sound rain         # rain | waves | forest | wind | fire | none
omarchy bar set ribattrw.calm volume 40          # 0-100
omarchy bar set ribattrw.calm reminders true     # gentle break reminders
omarchy bar set ribattrw.calm reminderMinutes 50 # cadence, 10-240
omarchy bar set ribattrw.calm dayStart 09:00     # first reminder from
omarchy bar set ribattrw.calm dayEnd 20:00       # last reminder before
```

## Ambient audio

Pick a sound with `omarchy bar set ribattrw.calm sound <name>`, then either start a session (the loop plays for the length of the session) or **middle-click the widget** to toggle the loop on its own while you work.

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
