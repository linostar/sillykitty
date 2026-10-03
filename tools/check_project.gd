extends SceneTree
## Project gate. Enforces the jam's mandatory "Movement Input Only" restriction:
## - the project defines no input actions besides move_* and overrides no ui_* action,
## - no script (standalone or embedded in .tscn/.tres) reads raw devices, pointer
##   state or any non-move_* action, enables physics picking or creates clickable Controls,
## - no scene contains a clickable or focusable Control.
## Also compiles every script: project.godot raises GDScript warnings to errors,
## so any warning fails here.
## Usage (from repo root): "$GODOT" --headless --path sillykitty --script "$PWD/tools/check_project.gd"
## Exits 1 and prints every violation; SCRIPT ERROR lines above them give compile details.

const ALLOWED_ACTIONS: Array[String] = ["move_left", "move_right", "move_up", "move_down"]
## Raw-device, pointer and picking APIs that bypass the movement action map.
const FORBIDDEN_TOKENS: Array[String] = [
	"InputEventMouse", "InputEventScreen", "InputEventKey", "InputEventJoypad",
	"InputEventGesture", "InputEventMagnifyGesture", "InputEventPanGesture",
	"is_key_pressed", "is_physical_key_pressed", "is_key_label_pressed", "is_mouse_button_pressed",
	"is_joy_button_pressed", "get_joy_axis", "mouse_position", "get_last_mouse_velocity",
	"_gui_input", "_unhandled_key_input", "_shortcut_input", "_input_event",
	# Event callbacks and any-key checks would allow "press any key" style input.
	"func _input", "func _unhandled_input", "is_anything_pressed", "is_pressed()",
	"mouse_entered", "mouse_exited", "physics_object_picking",
]
const ACTION_CALL_PATTERN := "\\b(?:is_action\\w*|get_action_\\w*strength|get_axis|get_vector|action_press|action_release)\\s*\\(([^)]*)\\)"
## Every argument of an action call must be a literal move_* name, a number or a bool.
const ACTION_ARG_PATTERN := "^\\s*(?:&?\"(?:move_left|move_right|move_up|move_down)\"|-?[0-9.]+|true|false)\\s*$"
const CLICKABLE_NEW_PATTERN := "\\b(?:\\w*Button|LineEdit|TextEdit|CodeEdit|SpinBox|[HV]Slider|[HV]ScrollBar|ItemList|Tree|TabBar|TabContainer|ColorPicker|GraphEdit|FileDialog|PopupMenu)\\.new\\s*\\("
const UI_OVERRIDE_PATTERN := "(?m)^ui_\\w+\\s*="
const SOURCE_EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]

var _violations: Array[String] = []


func _init() -> void:
	_check_actions()
	var files: Array[String] = []
	_collect_files("res://", files)
	for path in files:
		if path.ends_with(".gd"):
			_check_compiles(path)
		if path.get_extension() in SOURCE_EXTENSIONS:
			_check_source(path)
		if path.ends_with(".tscn"):
			_check_scene(path)
	if _violations.is_empty():
		print("check_project: OK (%d files scanned)" % files.size())
		quit(0)
		return
	for violation in _violations:
		printerr("check_project: " + violation)
	printerr("check_project: FAILED with %d violation(s)" % _violations.size())
	quit(1)


func _check_actions() -> void:
	for property in ProjectSettings.get_property_list():
		var name: String = property["name"]
		if not name.begins_with("input/") or name.begins_with("input/ui_"):
			continue
		var action := name.trim_prefix("input/")
		if action not in ALLOWED_ACTIONS:
			_violations.append("project.godot defines non-movement action '%s'" % action)
	var project_text := _read_text("res://project.godot")
	for override in RegEx.create_from_string(UI_OVERRIDE_PATTERN).search_all(project_text):
		_violations.append("project.godot overrides built-in action: %s" % override.get_string().trim_suffix("="))


func _check_compiles(path: String) -> void:
	var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null or not script.can_instantiate():
		_violations.append("%s: fails to compile (warnings count as errors)" % path)


func _check_source(path: String) -> void:
	var source := _read_text(path)
	for token in FORBIDDEN_TOKENS:
		if token in source:
			_violations.append("%s: uses forbidden input API '%s'" % [path, token])
	for clickable in RegEx.create_from_string(CLICKABLE_NEW_PATTERN).search_all(source):
		_violations.append("%s: creates a clickable Control at runtime: %s" % [path, clickable.get_string()])
	var arg_regex := RegEx.create_from_string(ACTION_ARG_PATTERN)
	for call_match in RegEx.create_from_string(ACTION_CALL_PATTERN).search_all(source):
		for arg in call_match.get_string(1).split(","):
			if arg_regex.search(arg) == null:
				_violations.append("%s: action call argument '%s' is not a literal move_* action in: %s" % [path, arg.strip_edges(), call_match.get_string()])


func _read_text(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_violations.append("%s: cannot read file (error %d)" % [path, FileAccess.get_open_error()])
	return text


func _check_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_violations.append("%s: failed to load scene" % path)
		return
	var scene_root := packed.instantiate()
	if scene_root == null:
		_violations.append("%s: failed to instantiate scene" % path)
		return
	_check_node(path, scene_root)
	scene_root.free()


func _check_node(path: String, node: Node) -> void:
	var control := node as Control
	if control != null:
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_violations.append("%s: Control '%s' must use mouse_filter IGNORE" % [path, control.name])
		if control.focus_mode != Control.FOCUS_NONE:
			_violations.append("%s: Control '%s' must use focus_mode NONE" % [path, control.name])
	for child in node.get_children():
		_check_node(path, child)


func _collect_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_violations.append("%s: cannot open directory (error %d)" % [dir_path, DirAccess.get_open_error()])
		return
	for file in dir.get_files():
		out.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_collect_files(dir_path.path_join(sub), out)
