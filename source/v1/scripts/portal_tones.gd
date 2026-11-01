class_name HoldPortalTones
extends Node
## 2026-11-01 (Daniel): every portal plays a different, hypnotic / soothing tone.
## Soft pads in D major pentatonic, played as a slowly evolving melody (never the same
## note twice in a row) and cycling through three soft voices (glass pad, breathy pad,
## soft marimba). Higher combo adds a low harmony note (x3+) and a quiet shimmer octave (x6+).
## Everything is synthesized ONCE at startup (3 short mono buffers + 1 looping drone);
## notes are pitched with pitch_scale, echoes are quiet delayed re-plays (works with the
## web "sample" playback mode, where bus effects are not applied).
## build/tools/render_portal_preview.py mirrors these numbers to render a listening preview.

const RATE := 22050
const BASE_F := 293.66            ## D4: pitch_scale 1.0
const TONE_LEN := 3.6             ## seconds per voice buffer (pitched up = shorter)
const PENT := [0, 2, 4, 7, 9]     ## D E F# A B (major pentatonic: every note is consonant with every other)
## Melody as pentatonic steps from D4 (0 = D4, -2 = A3, 5 = D5). Phrase A then B, looping.
## No note repeats back-to-back, including across the A->B and B->A joins.
const MELODY := [0, 2, 3, 2, 1, 3, 4, 3, 2, 0, 1, 2, -1, 0, -2, -1,
		0, 1, 3, 5, 4, 3, 2, 4, 3, 1, 2, 0, 1, -1, 0, -2]
const VOICE_NAMES := ["glass", "breath", "marimba"]
## Per voice: attack s, decay rate (exp(-t*d)), partials [ratio, amp, extra decay]
const VOICES := [
	{"attack": 0.05, "decay": 1.1, "partials": [[1.0, 1.0, 0.0], [2.0, 0.18, 1.5], [3.0, 0.05, 3.0], [2.76, 0.04, 4.0]]},
	{"attack": 0.08, "decay": 0.9, "partials": [[1.0, 1.0, 0.0], [2.0, 0.10, 0.5], [3.0, 0.11, 0.8], [5.0, 0.03, 1.5]]},
	{"attack": 0.03, "decay": 1.9, "partials": [[1.0, 1.0, 0.0], [4.0, 0.12, 7.0], [10.0, 0.02, 14.0]]},
]
const DETUNE_CENTS := 4.0         ## two voices, +-4 cents = slow soft chorus
const PEAK := 0.55
const LAYER_DB := -6.0            ## main note level
const ECHO := [[0.43, -10.0], [0.86, -17.0]]   ## delay s, level dB (relative)
const DRONE_DB := -27.0
const POOL := 24

var buffers: Array[AudioStreamWAV] = []
var players: Array[AudioStreamPlayer] = []
var drone: AudioStreamPlayer
var _rr := 0
var _pending: Array = []          ## [time_left, voice, step, db]
var step := 0                     ## portals played this flight
var last_note := 0
var last_voice := -1
var note_hist: Array[int] = []
var voice_hist: Array[int] = []

func _ready() -> void:
	for v in VOICES.size():
		buffers.append(_make_voice(v))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	drone = AudioStreamPlayer.new()
	drone.stream = _make_drone()
	drone.volume_db = -60.0
	add_child(drone)

static func note_ratio(k: int) -> float:
	var o := floori(float(k) / 5.0)
	var semis: int = PENT[k - o * 5] + 12 * o
	return pow(2.0, semis / 12.0)

func reset() -> void:
	step = 0
	last_voice = -1
	note_hist.clear()
	voice_hist.clear()
	_pending.clear()

func start_drone() -> void:
	if not drone.playing:
		drone.play()
	var tw := create_tween()
	tw.tween_property(drone, "volume_db", DRONE_DB, 3.0)

## Called once per portal flown through. mult = current combo multiplier (1..8).
func play_portal(mult: int) -> void:
	var k: int = MELODY[step % MELODY.size()]
	var voice := step % VOICES.size()
	step += 1
	last_note = k
	last_voice = voice
	note_hist.append(k)
	voice_hist.append(voice)
	if note_hist.size() > 16:
		note_hist.pop_front()
		voice_hist.pop_front()
	_layer(voice, k, LAYER_DB, 2)
	if mult >= 3:
		_layer(1, k - 2, LAYER_DB - 9.0, 1)      # warm harmony below
	if mult >= 6:
		_layer(0, k + 5, LAYER_DB - 15.0, 1)     # shimmer octave above

func _layer(voice: int, k: int, db: float, echoes: int) -> void:
	_fire(voice, k, db)
	for e in echoes:
		_pending.append([ECHO[e][0], voice, k, db + ECHO[e][1]])

func _fire(voice: int, k: int, db: float) -> void:
	var p := players[_rr]
	_rr = (_rr + 1) % players.size()
	p.stream = buffers[voice]
	p.pitch_scale = note_ratio(k)
	p.volume_db = db
	p.play()

func _process(delta: float) -> void:
	var i := _pending.size() - 1
	while i >= 0:
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			var e: Array = _pending[i]
			_pending.remove_at(i)
			_fire(e[1], e[2], e[3])
		i -= 1

# ---------------------------------------------------------------- synthesis

func _make_voice(v: int) -> AudioStreamWAV:
	var spec: Dictionary = VOICES[v]
	var att: float = spec["attack"]
	var dec: float = spec["decay"]
	var parts: Array = spec["partials"]
	var n := int(TONE_LEN * RATE)
	var fade_n := int(0.4 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var det := [pow(2.0, -DETUNE_CENTS / 1200.0), pow(2.0, DETUNE_CENTS / 1200.0)]
	# per-partial phase increments / amplitudes, precomputed
	var incs := PackedFloat32Array()
	var amps := PackedFloat32Array()
	var decs := PackedFloat32Array()
	var phs := PackedFloat32Array()
	for d in 2:
		for pi_ in parts.size():
			var pr: Array = parts[pi_]
			incs.append(TAU * BASE_F * float(pr[0]) * det[d] / RATE)
			amps.append(float(pr[1]) * 0.5)
			decs.append(exp(-float(pr[2]) / RATE))   # per-sample decay factor
			phs.append(1.3 * d * (pi_ + 1))
	var m := incs.size()
	var peak := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for j in m:
			s += sin(phs[j] + incs[j] * i) * amps[j]
			amps[j] *= decs[j]
		var env := 0.5 - 0.5 * cos(PI * minf(t / att, 1.0))
		env *= exp(-t * dec)
		if v == 1:
			env *= 0.75 + 0.25 * minf(t / 0.4, 1.0)   # breathy slow bloom
		if i > n - fade_n:
			env *= 0.5 + 0.5 * cos(PI * float(i - (n - fade_n)) / fade_n)
		s *= env
		buf[i] = s
		peak = maxf(peak, absf(s))
	return _to_wav(buf, PEAK / maxf(peak, 0.0001), false)

func _make_drone() -> AudioStreamWAV:
	# 4 s seamless loop: every frequency has a whole number of cycles in 4 s.
	var n := 4 * RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	var fs := [73.5, 110.0, 146.75, 147.0, 220.0]
	var am := [0.5, 0.3, 0.25, 0.25, 0.12]
	var peak := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for j in fs.size():
			s += sin(TAU * fs[j] * t + j) * am[j]
		s *= 0.8 + 0.2 * sin(TAU * 0.25 * t)
		buf[i] = s
		peak = maxf(peak, absf(s))
	return _to_wav(buf, 0.6 / peak, true)

func _to_wav(buf: PackedFloat32Array, gain: float, loop: bool) -> AudioStreamWAV:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, clampi(int(buf[i] * gain * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
