class_name Storage
extends RefCounted
## Save files in user:// : the current run, the high score and meta progress.
## Tests call use_test_paths() so they never touch the player's real saves.

static var save_path := Config.SAVE_PATH
static var highscore_path := Config.HIGHSCORE_PATH
static var meta_path := Config.META_PATH
static var settings_path := "user://settings.cfg"


static func use_test_paths() -> void:
	save_path = "user://test_savegame.json"
	highscore_path = "user://test_highscore.json"
	meta_path = "user://test_meta.json"
	settings_path = "user://test_settings.cfg"


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


static func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Returns {} when there is no high score yet.
static func load_highscore() -> Dictionary:
	var d: Variant = _read(highscore_path)
	return d if d is Dictionary else {}


## Score = floor reached, then level, then kills; a win beats everything. Returns true if new best.
static func save_highscore(state: GameState) -> bool:
	var p := state.player
	var score := [1 if state.won else 0, state.floor_num, p.level, p.kills]
	var best := load_highscore()
	var best_score := [int(best.get("won", 0)), int(best.get("floor", 0)), int(best.get("level", 0)), int(best.get("kills", 0))]
	if best.is_empty() or score > best_score:
		_write(highscore_path, {"name": p.name, "class": p.char_class, "difficulty": state.difficulty,
				"won": score[0], "floor": state.floor_num, "level": p.level, "kills": p.kills})
		return true
	return false


static func save_game(state: GameState) -> void:
	_write(save_path, state.to_dict())


## Returns null when there is no (valid) save.
static func load_game() -> GameState:
	var d: Variant = _read(save_path)
	if not (d is Dictionary and d.has("player") and d.has("map") and d.has("floor_num")):
		return null  # missing, broken, or from an older version
	if not Config.CLASSES.has(d["player"].get("char_class", "")):
		return null
	return GameState.from_dict(d)


static func delete_save() -> void:
	_delete(save_path)


static func load_meta() -> MetaProgress:
	var d: Variant = _read(meta_path)
	return MetaProgress.from_dict(d) if d is Dictionary else MetaProgress.new()


static func save_meta(meta: MetaProgress) -> void:
	_write(meta_path, meta.to_dict())


## Test cleanup: remove all test files.
static func delete_test_files() -> void:
	for path in [save_path, highscore_path, meta_path, settings_path]:
		_delete(path)
