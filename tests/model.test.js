const fs = require('fs');
const path = require('path');

// CalmModel.js is a QML `.pragma library` module; strip the pragma and load it
// as plain CommonJS so the pure logic can be tested without a QML runtime.
const repo = path.resolve(__dirname, '..');
const src = fs.readFileSync(path.join(repo, 'CalmModel.js'), 'utf8')
  .replace(/^\.pragma library\s*$/m, '');

const names = [
  'INHALE_SECS', 'EXHALE_SECS', 'CYCLE_SECS', 'DEFAULT_MINUTES', 'SOUNDS',
  'CONFIG_SCHEMA',
  'defaultConfig', 'configFromShell', 'normaliseConfig', 'sessionEndMs',
  'progressOf', 'breathAt', 'minutesOfDay', 'firstAllowedAtOrAfter',
  'inAllowedHours', 'nextDeadline', 'reminderGraceMs', 'parseState',
  'emptyState',
  'keepDay', 'isKept', 'withSession', 'withAmbient', 'withKeybindHint', 'dayKey',
  'audioCommand', 'cueCommand', 'CUE_SCRIPT', 'headsUpCommand', 'noticeCommand', 'stateJson',
  'mentionsPlugin', 'keybindHintCommand', 'breathingNoteVisibleAt',
  'BREATHING_NOTE_TEXT', 'BREATHING_NOTE_VISIBLE_MS',
  'clamp', 'soundLabel', 'AUDIO_SCRIPT'
];
const mod = { exports: {} };
new Function('module', 'exports', src + '\n;module.exports = {' + names.join(',') + '};')
  (mod, mod.exports);
const M = mod.exports;

let fails = 0;
function ok(name, cond, extra) {
  if (!cond) { fails++; console.log('FAIL: ' + name + (extra !== undefined ? '  -> ' + JSON.stringify(extra) : '')); }
  else console.log('ok   ' + name);
}

// --- breath: 10 s cycle so whole-minute sessions end on a breath boundary
ok('cycle is 10s', M.CYCLE_SECS === 10);
const s0 = M.breathAt(0);
ok('t=0 start of inhale', s0.label === 'Breathe in' && Math.abs(s0.fullness) < 1e-9, s0);
const s4 = M.breathAt(4);
ok('t=4 top of breath', s4.label === 'Breathe out' && Math.abs(s4.fullness - 1) < 1e-9, s4);
ok('t=10 wraps cleanly', M.breathAt(10).label === 'Breathe in' && M.breathAt(10).fullness < 0.01);
for (const m of [1, 3, 5, 7, 23, 60]) ok('minutes=' + m + ' = whole breaths', (m * 60) % M.CYCLE_SECS === 0);
let prev = -1, mono = true;
for (let t = 0; t < 4; t += 0.1) { const f = M.breathAt(t).fullness; if (f < prev - 1e-9) mono = false; prev = f; }
ok('inhale grows monotonically', mono);
let p2 = 2, dec = true;
for (let t = 4; t < 10; t += 0.1) { const f = M.breathAt(t).fullness; if (f > p2 + 1e-9) dec = false; p2 = f; }
ok('exhale shrinks monotonically', dec);
ok('exhale meets next inhale', Math.abs(M.breathAt(9.9999).fullness - M.breathAt(10).fullness) < 0.01);

// --- absolute session deadlines
const st = 1000000;
ok('3 min deadline is absolute', M.sessionEndMs(st, 3) === st + 180000);
ok('progress 0 at start', M.progressOf(st, st + 180000, st) === 0);
ok('progress 1 at end', M.progressOf(st, st + 180000, st + 180000) === 1);
ok('progress clamps after end', M.progressOf(st, st + 180000, st + 999999) === 1);
ok('progress clamps before start', M.progressOf(st, st + 180000, st - 5000) === 0);
ok('progress survives a long suspend', M.progressOf(st, st + 180000, st + 7200000) === 1);

// --- quiet hours
const D = (y, mo, d, h, mi) => new Date(y, mo - 1, d, h, mi, 0, 0).getTime();
const t08 = D(2026, 9, 22, 8, 0);
const t09 = D(2026, 9, 22, 9, 0);
const t1950 = D(2026, 9, 22, 19, 50);
const t2040 = D(2026, 9, 22, 20, 40);
ok('before window -> jumps to start', M.firstAllowedAtOrAfter(t08, '09:00', '20:00') === t09);
ok('inside window stays put', M.firstAllowedAtOrAfter(D(2026, 9, 22, 10, 0), '09:00', '20:00') === D(2026, 9, 22, 10, 0));
ok('after window -> next morning', M.firstAllowedAtOrAfter(t2040, '09:00', '20:00') === D(2026, 9, 23, 9, 0));
ok('interval crossing 20:00 -> next morning', M.nextDeadline(t1950, 50 * 60000, '09:00', '20:00') === D(2026, 9, 23, 9, 0));
ok('in-hours at 12:00', M.inAllowedHours(D(2026, 9, 22, 12, 0), '09:00', '20:00'));
ok('out at exactly 20:00', !M.inAllowedHours(D(2026, 9, 22, 20, 0), '09:00', '20:00'));
ok('out at 08:59', !M.inAllowedHours(D(2026, 9, 22, 8, 59), '09:00', '20:00'));
ok('reversed window falls back to always on', M.inAllowedHours(t08, '20:00', '09:00'));

// --- config: one file, the widget's shell.json entry
const shellCfg = JSON.stringify({
  version: 1,
  idle: { screensaver: 120, lock: 300 },
  bar: { layout: { left: [{ id: 'omarchy.menu' }], right: [{ id: 'ribattrw.calm', minutes: 7, sound: 'waves', volume: 55, cicadas: false, cicadaVolume: 45, breathCues: false, breathVolume: 60, reminders: false, reminderMinutes: 25, dayStart: '10:00', dayEnd: '18:30' }] } },
  plugins: []
});
const c = M.configFromShell(shellCfg, 'ribattrw.calm');
ok('reads minutes', c.minutes === 7, c);
ok('reads sound', c.sound === 'waves');
ok('reads volume', c.volume === 55);
ok('reads cicadas bool false', c.cicadas === false, c);
ok('reads cicadaVolume', c.cicadaVolume === 45, c);
ok('reads breathCues bool false', c.breathCues === false, c);
ok('reads breathVolume', c.breathVolume === 60, c);
ok('reads reminders bool', c.reminders === false);
ok('reads window', c.dayStart === '10:00' && c.dayEnd === '18:30');
ok('reads omarchy idle thresholds', c.idleScreensaver === 120, c);
const bad = M.configFromShell('not json', 'ribattrw.calm');
ok('bad json -> defaults', bad.minutes === 3 && bad.reminders === true, bad);
const viaPlugins = M.configFromShell(JSON.stringify({ plugins: [{ id: 'ribattrw.calm', minutes: 11 }] }), 'ribattrw.calm');
ok('reads plugins[] entry too', viaPlugins.minutes === 11, viaPlugins);
const clamped = M.configFromShell(JSON.stringify({ bar: { layout: { right: [{ id: 'ribattrw.calm', minutes: 9999, dayStart: 'bogus', volume: -4, cicadaVolume: 400, breathVolume: -3 }] } } }), 'ribattrw.calm');
ok('clamps minutes', clamped.minutes === 60, clamped);
ok('clamps volume', clamped.volume === 0, clamped);
ok('clamps cicadaVolume', clamped.cicadaVolume === 100, clamped);
ok('clamps breathVolume', clamped.breathVolume === 0, clamped);
ok('repairs bad dayStart', clamped.dayStart === '09:00', clamped);
const other = M.configFromShell(shellCfg, 'someone.else');
ok('ignores other plugins entries', other.minutes === 3, other);

// --- grace window tracks omarchy.idle instead of a hardcoded guess
ok('150s idle -> 210s grace', M.reminderGraceMs({ idleScreensaver: 150, idleLock: 300 }) === 210000);
ok('grace floor 180s', M.reminderGraceMs({ idleScreensaver: 30, idleLock: 60 }) === 180000);
ok('grace ceiling 900s', M.reminderGraceMs({ idleScreensaver: 3600, idleLock: 3600 }) === 900000);

// --- state: one quiet dot, never a history
const sBad = M.parseState('{bad');
ok('bad state -> empty', sBad.days && !sBad.session && sBad.ambient === false);
const kept = M.keepDay(M.emptyState(), '2026-09-22');
ok('keepDay sets today', M.isKept(kept, '2026-09-22'));
ok('keepDay leaves other days alone', !M.isKept(kept, '2026-09-21'));
let many = M.emptyState();
for (let i = 0; i < 200; i++) many = M.keepDay(many, '2026-0' + (i % 9) + '-' + String((i % 28) + 1).padStart(2, '0'));
ok('days map is trimmed, never a history', Object.keys(many.days).length <= 60, Object.keys(many.days).length);
const amb = M.withAmbient(kept, true, 'fire');
ok('withAmbient preserves kept', M.isKept(amb, '2026-09-22'));
ok('withSession preserves ambient', M.withSession(M.withAmbient(kept, true, 'fire'), { startedAt: 1 }).ambient === true);
const sess = M.withSession(kept, { startedAt: 1, endsAt: 2 });
ok('withSession preserves days', M.isKept(sess, '2026-09-22'));

// --- persistence: plain serialised JSON written by FileView.setText()
const rawState = { days: { 'a"; rm -rf /;': true }, session: null, ambient: false, sound: '' };
const json = M.stateJson(rawState);
ok('stateJson is valid JSON', JSON.stringify(JSON.parse(json)) !== undefined, json);
ok('round-trips hostile keys intact', M.parseState(json).days['a"; rm -rf /;'] === true, M.parseState(json).days);
ok('ends with a newline', json.endsWith('\n'));
ok('pretty-printed, not one long line', json.indexOf('\n') > 0);
const empty = M.parseState(M.stateJson(M.emptyState()));
ok('empty state round-trips', empty.ambient === false && empty.session === null && Object.keys(empty.days).length === 0, empty);

// --- audio: local only, gapless loop, user folder wins
const ac = M.audioCommand('rain', 40, '/u', '/s');
ok('audio argv shape', ac[0] === 'sh' && ac[3] === 'calm-audio' && ac[4] === 'rain' && ac[5] === '40' && ac[6] === '/u' && ac[7] === '/s', ac);
ok('no network tooling in audio path', !/curl|wget|https?:/.test(M.AUDIO_SCRIPT));
ok('gapless loop via mpv', /--loop-file=inf/.test(M.AUDIO_SCRIPT));
ok('no user mpv config / scripts', /--no-config/.test(M.AUDIO_SCRIPT) && /--load-scripts=no/.test(M.AUDIO_SCRIPT));
ok('user folder checked before bundled', M.AUDIO_SCRIPT.indexOf('"$ud/$n"') < M.AUDIO_SCRIPT.indexOf('"$sd/$n"'));
ok('volume is clamped', M.audioCommand('rain', 9999, '/u', '/s')[5] === '100');
ok('volume clamped low', M.audioCommand('rain', -5, '/u', '/s')[5] === '0');

// --- notifications
const hu = M.headsUpCommand('/omarchy', 'ribattrw.calm', 'H', 'B');
ok('heads-up is low urgency', hu.indexOf('-u') >= 0 && hu[hu.indexOf('-u') + 1] === 'low', hu);
ok('heads-up is clickable', hu.indexOf('--exec') >= 0 && hu[hu.indexOf('--exec') + 1] === '/omarchy/bin/omarchy-shell', hu);
ok('heads-up has no skip button args', !/skip|dismiss|postpone/i.test(hu.join(' ')));

// --- audible-by-default playback (bug: widget sessions were silent)
// Volume default follows the audio-science level table: assets are
// normalised to -36 LUFS at build time, so the default knob (mpv's cubic
// 60*log10 law) sets the mix, not a loudness rescue.
ok('default volume is the science-mix knob', M.defaultConfig().volume === 40, M.defaultConfig().volume);
ok('default sound always plays', M.defaultConfig().sound === 'rain');
ok('volume 100 must not clip the argv', M.audioCommand('rain', 100, '/u', '/s')[5] === '100');

// --- audio layers: cicada ambience + breath cues (three commissioned reports)
ok('cicadas default ON as a soft background', M.defaultConfig().cicadas === true, M.defaultConfig().cicadas);
ok('cicadaVolume default 30', M.defaultConfig().cicadaVolume === 30, M.defaultConfig().cicadaVolume);
ok('breathCues default ON', M.defaultConfig().breathCues === true, M.defaultConfig().breathCues);
ok('breathVolume default 20 (pw-play is linear, not mpv-cubic)', M.defaultConfig().breathVolume === 20, M.defaultConfig().breathVolume);
ok('cicadas is bool in schema', M.CONFIG_SCHEMA.cicadas === 'bool' && M.CONFIG_SCHEMA.breathCues === 'bool');
ok('layer volumes are int in schema', M.CONFIG_SCHEMA.cicadaVolume === 'int' && M.CONFIG_SCHEMA.breathVolume === 'int');
const cc = M.cueCommand('breath-in', 20, '/u', '/s');
ok('cue argv shape', cc[0] === 'sh' && cc[3] === 'calm-cue' && cc[4] === 'breath-in' && cc[5] === '0.2' && cc[6] === '/u' && cc[7] === '/s', cc);
ok('cue volume is linear percent/100', M.cueCommand('breath-out', 100, '/u', '/s')[5] === '1' && M.cueCommand('breath-out', 0, '/u', '/s')[5] === '0');
ok('cue volume clamped', M.cueCommand('breath-in', 9999, '/u', '/s')[5] === '1' && M.cueCommand('breath-in', -5, '/u', '/s')[5] === '0');
ok('cue plays via pw-play', /exec pw-play --volume="\$v"/.test(M.CUE_SCRIPT));
ok('no network tooling in cue path', !/curl|wget|https?:/.test(M.CUE_SCRIPT));
ok('cue user folder checked before bundled', M.CUE_SCRIPT.indexOf('"$ud/$n"') < M.CUE_SCRIPT.indexOf('"$sd/$n"'));
ok('cue script exits silently without pw-play', /command -v pw-play/.test(M.CUE_SCRIPT));
ok('cicada rides the mpv loop path too', /--loop-file=inf/.test(M.AUDIO_SCRIPT));
ok('AUDIO_SCRIPT takes the client name as $5', M.AUDIO_SCRIPT.indexOf('cn="$5"') >= 0 && /--audio-client-name="\$cn"/.test(M.AUDIO_SCRIPT));
ok('base layer default client name', M.audioCommand('rain', 40, '/u', '/s')[8] === 'omarchy-calm', M.audioCommand('rain', 40, '/u', '/s'));
ok('cicada layer gets its own client name', M.audioCommand('cicada', 30, '/u', '/s', 'omarchy-calm-cicadas')[8] === 'omarchy-calm-cicadas');

// --- keybind hint state: one-time, carried by every state rebuilder
ok('keybindHint defaults false', M.emptyState().keybindHint === false);
ok('parseState carries keybindHint', M.parseState('{"keybindHint":true}').keybindHint === true);
ok('parseState rejects non-boolean hint', M.parseState('{"keybindHint":"yes"}').keybindHint === false);
const hinted = M.withKeybindHint(M.emptyState());
ok('withKeybindHint sets flag', hinted.keybindHint === true);
ok('withKeybindHint preserves days', M.isKept(M.withKeybindHint(M.keepDay(M.emptyState(), '2026-09-22')), '2026-09-22'));
ok('keepDay preserves hint', M.keepDay(hinted, '2026-09-22').keybindHint === true);
ok('withSession preserves hint', M.withSession(hinted, { startedAt: 1 }).keybindHint === true);
ok('withAmbient preserves hint', M.withAmbient(hinted, true).keybindHint === true);
ok('hint round-trips through the state file', M.parseState(M.stateJson(hinted)).keybindHint === true);

// --- keybind discovery: README must ship the exact working one-liner
ok('mentionsPlugin finds the binding line', M.mentionsPlugin('o.bind("SUPER + ALT + M", "x", [[omarchy-shell shell summon ribattrw.calm "{}"]])'));
ok('mentionsPlugin false without binding', !M.mentionsPlugin('o.bind("SUPER + H", "x", "voxtype")'));
ok('mentionsPlugin false on empty', !M.mentionsPlugin(''));
ok('mentionsPlugin ignores a bare comment', !M.mentionsPlugin('-- tried ribattrw.calm, removed'));
ok('mentionsPlugin ignores a commented-out bind', !M.mentionsPlugin('-- o.bind("SUPER + ALT + M", "x", [[omarchy-shell shell summon ribattrw.calm "{}"]])'));
ok('mentionsPlugin ignores bind text after a comment', !M.mentionsPlugin('x = 1 -- o.bind ribattrw.calm'));
ok('mentionsPlugin keeps an active bind with a trailing comment', M.mentionsPlugin('o.bind("SUPER + ALT + M", "x", [[omarchy-shell shell summon ribattrw.calm "{}"]]) -- added'));
ok('mentionsPlugin needs o.bind, not just the id', !M.mentionsPlugin('ribattrw.calm'));

// --- breathing note: quiet line, visible from session start, gone after ~20 s
ok('note text is pursed-lip breathing', M.BREATHING_NOTE_TEXT === 'breathe in through your nose - out through pursed lips', M.BREATHING_NOTE_TEXT);
ok('note window is about 20 s', M.BREATHING_NOTE_VISIBLE_MS === 20000, M.BREATHING_NOTE_VISIBLE_MS);
ok('note visible at session start', M.breathingNoteVisibleAt(0) === true);
ok('note still visible mid-window', M.breathingNoteVisibleAt(19999) === true);
ok('note gone at the window edge', M.breathingNoteVisibleAt(20000) === false);
ok('note stays gone for the rest of the session', M.breathingNoteVisibleAt(60000) === false);
ok('note hidden for bad elapsed', M.breathingNoteVisibleAt(-1) === false && M.breathingNoteVisibleAt(NaN) === false);
const readme = fs.readFileSync(path.join(repo, 'README.md'), 'utf8');
const hintLine = M.keybindHintCommand();
ok('README ships the exact hint line', readme.indexOf(hintLine) >= 0, hintLine);
ok('hint line is idempotent (guarded by grep)', /grep -q/.test(hintLine) && /\|\| echo/.test(hintLine), hintLine);
ok('hint guard ignores Lua comments', hintLine.indexOf("s/--.*//") >= 0, hintLine);
ok('hint guard requires an active bind', hintLine.indexOf('o\\.bind') >= 0, hintLine);
ok('hint line never uses single-quoted JSON payload', hintLine.indexOf("'{}'") < 0, hintLine);
ok('README ships a matching removal line', readme.indexOf("sed -i '/ribattrw\\.calm/d' ~/.config/hypr/bindings.lua") >= 0);
ok('README documents the default volume', readme.indexOf('volume 40') >= 0);
ok('README documents the cicadas key', readme.indexOf('omarchy bar set ribattrw.calm cicadas true') >= 0);
ok('README documents the cicadaVolume key', readme.indexOf('omarchy bar set ribattrw.calm cicadaVolume 30') >= 0);
ok('README documents the breathCues key', readme.indexOf('omarchy bar set ribattrw.calm breathCues true') >= 0);
ok('README documents the breathVolume key', readme.indexOf('omarchy bar set ribattrw.calm breathVolume 20') >= 0);

console.log(fails === 0 ? '\nALL TESTS PASS' : '\n' + fails + ' FAILURE(S)');
process.exit(fails ? 1 : 0);
