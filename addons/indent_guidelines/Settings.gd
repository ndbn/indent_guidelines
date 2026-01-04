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
@export var guideline_y_offset: float = -2.0 # Used for draw guidelines a bit upper
@export var guideline_keep_caret: bool = true
@export var guideline_draw_root_guides: bool = true # Draw level 0 guides

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
@export var foldmark_y_offset: float = 0.0


# CodeEdit Tweaks
@export_category("CodeEdit tweaks")
@export var tweak_completion_lines: int = 7
@export var tweak_completion_max_width: int = 50
