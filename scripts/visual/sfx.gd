class_name Sfx
extends Node
## Retro sound effects and looping chiptune music, all synthesized in code (no audio files).
## Music is built on a background thread so startup stays instant.

const RATE := 22050
const MUSIC_RATE := 16000
const MUSIC_DB := -15.0

# chord = [root, third, fifth] in Hz
const AM := [220.0, 261.63, 329.63]
const F := [174.61, 220.0, 261.63]
const C := [261.63, 329.63, 392.0]
const G := [196.0, 246.94, 293.66]
const DM := [146.83, 174.61, 220.0]
const BB := [233.08, 293.66, 349.23]
const GM := [196.0, 233.08, 293.66]
const A := [220.0, 277.18, 329.63]
const TRACKS := {
	"explore": {"bpm": 84.0, "chords": [AM, F, C, G], "drums": false, "arp": [0, 1, 2, 1]},
	"battle": {"bpm": 132.0, "chords": [AM, AM, F, G], "drums": true, "arp": [0, 2, 1, 2]},
	"boss": {"bpm": 148.0, "chords": [DM, BB, GM, A], "drums": true, "arp": [0, 1, 2, 3]},
}

var muted := false
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music := {}  # track name -> AudioStreamWAV, filled by the thread
var _music_player := AudioStreamPlayer.new()
var _music_db := MUSIC_DB
var _wanted_track := ""
var _playing_track := ""
var _thread := Thread.new()
var _music_mutex := Mutex.new()


func _ready() -> void:
	_music_player.volume_db = _music_db
	add_child(_music_player)
	_thread.start(_build_music)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_streams = {
		"hit": _wav(_mix(_noise(0.12, 0.8, 25.0, 0.5), _sweep(220, 80, 0.12, 0.45, true))),
		"hurt": _wav(_mix(_noise(0.15, 0.7, 18.0, 0.3), _sweep(320, 110, 0.15, 0.45, true))),
		"crit": _wav(_mix(_noise(0.24, 0.9, 12.0, 0.6), _sweep(900, 120, 0.24, 0.4, true))),
		"miss": _wav(_noise(0.2, 1.6, 0.0, 0.05, true)),
		"skill": _wav(_sweep(220, 1100, 0.22, 0.35, true)),
		"heal": _wav(_notes([523.0, 659.0, 784.0, 1047.0], 0.07, 0.4, false)),
		"defend": _wav(_mix(_sweep(180, 120, 0.18, 0.6, false), _noise(0.08, 0.3, 30.0, 0.2))),
		"levelup": _wav(_notes([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.09, 0.28, true)),
		"coin": _wav(_notes([988.0, 1319.0], 0.07, 0.25, true)),
		"death": _wav(_sweep(440, 55, 0.6, 0.4, true)),
		"boss": _wav(_mix(_noise(0.9, 2.5, 3.0, 0.02), _sweep(90, 45, 0.9, 0.6, false))),
		"appear": _wav(_sweep(300, 520, 0.1, 0.25, false)),
		"flee": _wav(_sweep(400, 900, 0.18, 0.3, false)),
		"click": _wav(_notes([660.0], 0.035, 0.18, true)),
	}


func _exit_tree() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()


func set_muted(value: bool) -> void:
	muted = value
	_music_player.stream_paused = muted


## Volumes are 0..1 (from the settings sliders).
func set_volumes(music: float, effects: float) -> void:
	_music_db = MUSIC_DB + linear_to_db(maxf(music, 0.001))
	_music_player.volume_db = _music_db
	for p in _players:
		p.volume_db = -8.0 + linear_to_db(maxf(effects, 0.001))


## Switch the background music, fading between tracks. Unknown or not-yet-built tracks start when ready.
func play_music(track: String) -> void:
	_wanted_track = track
	_music_mutex.lock()
	var stream: AudioStreamWAV = _music.get(track)
	_music_mutex.unlock()
	if stream == null or track == _playing_track:
		return
	_playing_track = track
	var tw := create_tween()
	if _music_player.playing:
		tw.tween_property(_music_player, "volume_db", -40.0, 0.35)
	tw.tween_callback(func() -> void:
		_music_player.stream = stream
		_music_player.play()
		_music_player.stream_paused = muted)
	tw.tween_property(_music_player, "volume_db", _music_db, 0.5)


func _music_ready() -> void:
	if _wanted_track != "":
		play_music(_wanted_track)


func _build_music() -> void:
	for track_name in TRACKS:
		var wav := _track(TRACKS[track_name])
		_music_mutex.lock()
		_music[track_name] = wav
		_music_mutex.unlock()
		call_deferred("_music_ready")


## One looping track: arpeggiated lead, bass on the beat, optional kick + hi-hat.
func _track(spec: Dictionary) -> AudioStreamWAV:
	var step := 60.0 / float(spec["bpm"]) / 4.0  # one 16th note
	var chords: Array = spec["chords"]
	var arp: Array = spec["arp"]
	var steps := 16 * chords.size()
	var n := int(steps * step * MUSIC_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var step_len := int(step * MUSIC_RATE)
	for s in steps:
		var chord: Array = chords[s / 16]
		var start := int(s * step * MUSIC_RATE)
		var tone_idx: int = arp[s % arp.size()]
		var lead: float = chord[tone_idx % 3] * (2.0 if tone_idx == 3 else 1.0)
		if spec["drums"] or s % 2 == 0:
			_add_tone(out, start, step_len * (1 if spec["drums"] else 2), lead * 2.0, 0.09, false)
		if s % 4 == 0:
			_add_tone(out, start, step_len * 4, chord[0] / 2.0, 0.13, true)
		if spec["drums"]:
			if s % 8 == 0:
				_add_kick(out, start)
			if s % 4 == 2:
				_add_hat(out, start)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(out[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MUSIC_RATE
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _add_tone(out: PackedFloat32Array, start: int, length: int, freq: float, vol: float, square: bool) -> void:
	for i in length:
		var idx := start + i
		if idx >= out.size():
			return
		var t := float(i) / MUSIC_RATE
		var phase := fmod(freq * t, 1.0)
		var s := (0.5 if phase < 0.5 else -0.5) if square else (4.0 * absf(phase - 0.5) - 1.0)
		out[idx] += s * vol * exp(-t * 5.0) * minf(1.0, i / 60.0)


func _add_kick(out: PackedFloat32Array, start: int) -> void:
	var phase := 0.0
	for i in int(0.12 * MUSIC_RATE):
		var idx := start + i
		if idx >= out.size():
			return
		var t := float(i) / MUSIC_RATE
		phase += TAU * (120.0 * exp(-t * 25.0) + 40.0) / MUSIC_RATE
		out[idx] += sin(phase) * 0.35 * exp(-t * 18.0)


func _add_hat(out: PackedFloat32Array, start: int) -> void:
	for i in int(0.03 * MUSIC_RATE):
		var idx := start + i
		if idx >= out.size():
			return
		out[idx] += randf_range(-1.0, 1.0) * 0.06 * exp(-float(i) / MUSIC_RATE * 90.0)


func play(sound: String, pitch_jitter: float = 0.06) -> void:
	if muted or not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# ------------------------------------------------------------------ synthesis

## Noise burst. decay = how fast it fades, alpha = low-pass amount (small = muffled),
## whoosh = fade in and out instead of a hard attack.
func _noise(dur: float, vol: float, decay: float, alpha: float, whoosh: bool = false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / dur) if whoosh else exp(-t * decay)
		y += (randf_range(-1.0, 1.0) - y) * alpha
		out[i] = y * vol * env
	return out


## Pitch glide from f0 to f1 Hz.
func _sweep(f0: float, f1: float, dur: float, vol: float, square: bool) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += TAU * f0 * pow(f1 / f0, k) / RATE
		var s := sin(phase)
		if square:
			s = 0.6 if s > 0.0 else -0.6
		out[i] = s * vol * minf(1.0, k * 40.0) * (1.0 - k)
	return out


## Short melody, one note per frequency.
func _notes(freqs: Array, each: float, vol: float, square: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		out.append_array(_sweep(f, f, each, vol, square))
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
