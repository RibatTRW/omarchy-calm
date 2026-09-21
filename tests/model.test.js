const fs = require('fs');
const path = require('path');

// CalmModel.js is a QML `.pragma library` module; strip the pragma and load it
// as plain CommonJS so the pure logic can be tested without a QML runtime.
const repo = path.resolve(__dirname, '..');
const src = fs.readFileSync(path.join(repo, 'CalmModel.js'), 'utf8')
  .replace(/^\.pragma library\s*$/m, '');

const names = [
  'INHALE_SECS', 'EXHALE_SECS', 'CYCLE_SECS', 'DEFAULT_MINUTES', 'SOUNDS',
  'defaultConfig', 'configFromShell', 'normaliseConfig', 'sessionEndMs',
  'progressOf', 'breathAt', 'minutesOfDay', 'firstAllowedAtOrAfter',
  'inAllowedHours', 'nextDeadline', 'reminderGraceMs', 'parseState',
  'emptyState',
  'keepDay', 'isKept', 'withSession', 'withAmbient', 'dayKey',
  'audioCommand', 'headsUpCommand', 'noticeCommand', 'stateJson',
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
  bar: { layout: { left: [{ id: 'omarchy.menu' }], right: [{ id: 'ribattrw.calm', minutes: 7, sound: 'waves', volume: 55, reminders: false, reminderMinutes: 25, dayStart: '10:00', dayEnd: '18:30' }] } },
  plugins: []
});
const c = M.configFromShell(shellCfg, 'ribattrw.calm');
ok('reads minutes', c.minutes === 7, c);
ok('reads sound', c.sound === 'waves');
ok('reads volume', c.volume === 55);
ok('reads reminders bool', c.reminders === false);
ok('reads window', c.dayStart === '10:00' && c.dayEnd === '18:30');
ok('reads omarchy idle thresholds', c.idleScreensaver === 120, c);
const bad = M.configFromShell('not json', 'ribattrw.calm');
ok('bad json -> defaults', bad.minutes === 3 && bad.reminders === true, bad);
const viaPlugins = M.configFromShell(JSON.stringify({ plugins: [{ id: 'ribattrw.calm', minutes: 11 }] }), 'ribattrw.calm');
ok('reads plugins[] entry too', viaPlugins.minutes === 11, viaPlugins);
const clamped = M.configFromShell(JSON.stringify({ bar: { layout: { right: [{ id: 'ribattrw.calm', minutes: 9999, dayStart: 'bogus', volume: -4 }] } } }), 'ribattrw.calm');
ok('clamps minutes', clamped.minutes === 60, clamped);
ok('clamps volume', clamped.volume === 0, clamped);
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

console.log(fails === 0 ? '\nALL TESTS PASS' : '\n' + fails + ' FAILURE(S)');
process.exit(fails ? 1 : 0);
