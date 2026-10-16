class_name SoundBoard
extends Node
## Plays the game's sounds: one-shots through a small voice pool, one ambient
## loop and one music loop, each on its own bus with volumes from SoundSettings.
## Add one early in a view's _ready so every button built after it clicks.

const SFX_VOICES := 8
const STEP_GAP := 0.12  # seconds between footsteps, so a squad on the move does not machine-gun
const PITCH_JITTER := 0.06
const BUSES: Array[String] = ["sfx", "ambient", "music", "ui"]
const AUDIO_DIR := "res://assets/audio/"
const REQUEST_LOG := 64

var settings: SoundSettings = SoundSettings.load_from()
var current_ambient := ""
var current_music := ""
## The last sounds asked for, as {"name", "delay"} (tests read it; capped).
var requests: Array[Dictionary] = []
## How many voices have actually started (tests: a muted or delayed sound must not).
var started := 0
## How many loop starts were requested (ambient and music).
var loops_started := 0

var _built := false
var _voices: Array[AudioStreamPlayer] = []
var _ui_voice: AudioStreamPlayer
var _next_voice := 0
var _ambient: AudioStreamPlayer
var _music: AudioStreamPlayer
var _last_step := -10.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


static func load_stream(name: String) -> AudioStreamWAV:
	var path := ArtSkin.voice_path(name) if name.begins_with("voice_") else "%s%s.wav" % [AUDIO_DIR, name]
	if path == "" or not ResourceLoader.exists(path):
		return null
	var base := load(path) as AudioStreamWAV
	if base == null:
		return null
	var s := base.duplicate() as AudioStreamWAV
	if name.begins_with("amb_") or name.begins_with("music_"):
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(round(s.get_length() * s.mix_rate))  # the import compresses the data, so size/2 is not the sample count
	else:
		s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return s


func _ready() -> void:
	build()
	if is_inside_tree():
		get_tree().node_added.connect(_on_node_added)
		_connect_existing(get_tree().root)


## Creates the buses and players. Idempotent; tests call it directly because a node added to
## the tree before the first frame has not had _ready yet.
func build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = 7
	_ensure_buses()
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "sfx"
		add_child(p)
		_voices.append(p)
	_ui_voice = AudioStreamPlayer.new()
	_ui_voice.bus = "ui"
	add_child(_ui_voice)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "ambient"
	add_child(_ambient)
	_music = AudioStreamPlayer.new()
	_music.bus = "music"
	add_child(_music)
	apply_settings()


func _process(delta: float) -> void:
	_clock += delta


static func _ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func apply_settings() -> void:
	settings.normalise()
	AudioServer.set_bus_volume_db(0, settings.bus_db("master"))
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, settings.bus_db(bus))


func set_muted(on: bool) -> void:
	settings.muted = on
	settings.save()
	apply_settings()
	if on:
		stop_loops()
	else:
		_resume_loops()


## Plays a one-shot after `delay` seconds. Unknown names are ignored.
func play(name: String, delay: float = 0.0, bus: String = "sfx") -> void:
	if settings.muted:
		return
	requests.append({"name": name, "delay": delay})
	if requests.size() > REQUEST_LOG:
		requests.pop_front()
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(_start_voice.bind(name, bus))
	else:
		_start_voice(name, bus)


func _start_voice(name: String, bus: String) -> void:
	if settings.muted or _voices.is_empty():
		return
	var stream := load_stream(name)
	if stream == null:
		return
	var voice := _ui_voice if bus == "ui" else _voices[_next_voice]
	if bus != "ui":
		_next_voice = (_next_voice + 1) % _voices.size()
	started += 1
	if not voice.is_inside_tree():
		return  # a board built but not in a running tree (tests) counts the start and plays nothing
	voice.bus = bus
	voice.stream = stream
	voice.pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	voice.play()


## Sounds for a tick's visible events. Footsteps are thinned to one per STEP_GAP.
func play_events(events: Array[Dictionary]) -> void:
	if settings.muted:
		return
	var stepped := false
	for ev in events:
		for r: Dictionary in SoundMap.for_event(ev):
			if String(r["name"]).begins_with("sfx_step_"):
				if stepped or _clock - _last_step < STEP_GAP and _clock > 0.0:
					continue
				stepped = true
				_last_step = _clock
			play(r["name"], r["delay"])


func click() -> void:
	play("ui_click", 0.0, "ui")


func set_ambient(theme: String) -> void:
	var name := SoundMap.ambient_for(theme)
	current_ambient = name
	_play_loop(_ambient, name)


func set_music(act: int) -> void:
	var name := SoundMap.music_for(act)
	current_music = name
	_play_loop(_music, name)


func stop_loops() -> void:
	if _ambient != null:
		_ambient.stop()
	if _music != null:
		_music.stop()


func _resume_loops() -> void:
	if current_ambient != "":
		_play_loop(_ambient, current_ambient)
	if current_music != "":
		_play_loop(_music, current_music)


func _play_loop(player: AudioStreamPlayer, name: String) -> void:
	if player == null or settings.muted:
		return
	if player.playing and player.stream != null and player.get_meta("sound_name", "") == name:
		return
	var stream := load_stream(name)
	if stream == null:
		return
	loops_started += 1
	if not player.is_inside_tree():
		return
	player.stream = stream
	player.set_meta("sound_name", name)
	player.play()


# --- button clicks ---------------------------------------------------------------

func _connect_existing(node: Node) -> void:
	for child in node.get_children():
		_on_node_added(child)
		_connect_existing(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not (node as BaseButton).pressed.is_connected(click):
		(node as BaseButton).pressed.connect(click)
