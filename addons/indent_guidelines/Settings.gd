extends Resource
class_name IndentGuidelinesSettings

# Guidelines
enum GuidelinesStyle { LINE, LINE_CLOSE}
enum GuidelinesOffset {LEFT = 0, MIDDLE, RIGHT}

@export_category("Guidelines")
@export var draw_guidelines: bool = true
@export var guideline_color: Color = Color(0.8, 0.8, 0.8, 0.3)
@export var guideline_active_color: Color = Color(0.8, 0.8, 0.8, 0.55)
@export var guidelines_style: GuidelinesStyle = GuidelinesStyle.LINE_CLOSE
@export var guideline_drawside: GuidelinesOffset = GuidelinesOffset.MIDDLE

@export var guideline_width: float = 1.0
@export var guideline_keep_caret: bool = true
@export var guideline_y_offset: float = -2.0 if Engine.get_version_info().hex >= 0x040400 else -1.0 # Used for draw guidelines a bit upper
@export var guideline_draw_root_guides: bool = false # Draw level 0 guides

# Fullheight line
@export_category("Full height line")
@export var draw_fullheight_line: bool = true
@export var fillheight_line_color = Color(0.9, 0.9, 0.9, 0.1)
@export var fillheight_x_offset: float = -2.0

# Folded code marks
@export_category("Foldmarks")
@export var draw_foldmarks: bool = true
@export var foldmark_color = Color(0.9, 0.9, 0.9, 0.9)
@export var foldmark_width: float = 3.0
@export var foldmark_x_offset: float = -3.0
@export var foldmark_y_offset: float = 0.0 if Engine.get_version_info().hex >= 0x040400 else 2.0

# CodeEdit Tweaks
@export_category("CodeEdit tweaks")
@export var tweak_completion_lines: int = 7
@export var tweak_completion_max_width: int = 50


#################################################

const settings_group: String = "plugins/indent_guidelines"
func S_NAME(p_setting: String)->String:	return settings_group + "/" + p_setting

func editor_settings_setget_init(p_setting_name: String, p_var_name: String, p_init: bool = false, p_info: Dictionary = {}) -> void:

	var default: Variant = self[p_var_name]

	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()

	if not editor_settings.has_setting(p_setting_name):
		editor_settings.set_setting(p_setting_name, default)

	if p_init: editor_settings.set_initial_value(p_setting_name, default, false)

	if not p_info.is_empty():
		p_info.name = p_setting_name
		editor_settings.add_property_info(p_info)

	self[p_var_name] = editor_settings.get_setting(p_setting_name)


func PropertyInfo(p_name: String, p_type: Variant.Type, p_hint: PropertyHint, p_hint_str: String) -> Dictionary:
	return {
		"name": p_name,
		"type": p_type,
		"hint": p_hint,
		"hint_string": p_hint_str
		}

func _init() -> void:
	update_settings(true)

func update_settings(p_init: bool)->void:
	editor_settings_setget_init(S_NAME("guidelines/draw_guidelines"), "draw_guidelines", p_init)
	editor_settings_setget_init(S_NAME("guidelines/color"), "guideline_color", p_init)
	editor_settings_setget_init(S_NAME("guidelines/active_color"), "guideline_active_color", p_init)
	editor_settings_setget_init(S_NAME("guidelines/style"), "guidelines_style", p_init, PropertyInfo("", TYPE_INT, PROPERTY_HINT_ENUM, "Line, Closed line"))
	editor_settings_setget_init(S_NAME("guidelines/draw_side"), "guideline_drawside", p_init, PropertyInfo("", TYPE_INT, PROPERTY_HINT_ENUM, "Left, Middle, Right"))
	editor_settings_setget_init(S_NAME("guidelines/width"), "guideline_width", p_init)
	editor_settings_setget_init(S_NAME("guidelines/keep_caret"), "guideline_keep_caret", p_init)
	editor_settings_setget_init(S_NAME("guidelines/y_offset"), "guideline_y_offset", p_init)
	editor_settings_setget_init(S_NAME("guidelines/draw_root_guides"), "guideline_draw_root_guides", p_init)

	editor_settings_setget_init(S_NAME("full_height_line/draw_fullheight_line"), "draw_fullheight_line", p_init)
	editor_settings_setget_init(S_NAME("full_height_line/line_color"), "fillheight_line_color", p_init)
	editor_settings_setget_init(S_NAME("full_height_line/x_offset"), "fillheight_x_offset", p_init)

	editor_settings_setget_init(S_NAME("foldmarks/draw_foldmarks"), "draw_foldmarks", p_init)
	editor_settings_setget_init(S_NAME("foldmarks/color"), "foldmark_color", p_init)
	editor_settings_setget_init(S_NAME("foldmarks/width"), "foldmark_width", p_init)
	editor_settings_setget_init(S_NAME("foldmarks/x_offset"), "foldmark_x_offset", p_init)
	editor_settings_setget_init(S_NAME("foldmarks/y_offset"), "foldmark_y_offset", p_init)

	editor_settings_setget_init(S_NAME("tweaks/tweak_completion_lines"), "tweak_completion_lines", p_init)
	editor_settings_setget_init(S_NAME("tweaks/tweak_completion_max_width"), "tweak_completion_max_width", p_init)
