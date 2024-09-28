@tool
extends EditorPlugin

signal sig_plugin_disabled

# Draw indent guidelines
const draw_guidelines: bool = true

# Draw sible line gutter
const draw_linegutter: bool = true

func _enter_tree() -> void:
  if not Engine.is_editor_hint(): return
  var script_editor: ScriptEditor = EditorInterface.get_script_editor()
  if not script_editor.editor_script_changed.is_connected(_editor_script_changed):
    script_editor.editor_script_changed.connect(_editor_script_changed)
    script_editor.editor_script_changed.emit(script_editor.get_current_script())

func _exit_tree() -> void:
  sig_plugin_disabled.emit()

func _editor_script_changed(_s: Script)->void:
  var script_editor: ScriptEditor = EditorInterface.get_script_editor()
  if not script_editor: return
  var editor_base: ScriptEditorBase = script_editor.get_current_editor()
  if not editor_base: return
  var base_editor: Control = editor_base.get_base_editor()
  if base_editor is CodeEdit:
    var code_edit: CodeEdit = base_editor

    # Gutter
    if draw_linegutter:
      var found: bool = false
      for n: Node in code_edit.get_children():
        if n is CodeEditorGutterLine:
          found = true
          break
      if not found: CodeEditorGutterLine.new(code_edit, sig_plugin_disabled)

    # Guideline
    if draw_guidelines:
      var found: bool = false
      for n: Node in code_edit.get_children():
        if n is CodeEditorGuideLine:
          found = true
          break
      if not found: CodeEditorGuideLine.new(code_edit, sig_plugin_disabled)

#---------------------------------------------

# Based on https://github.com/godotengine/godot/pull/65757

class CodeEditorGuideLine extends Node:

  enum CodeblockGuidelinesStyle {
    CODEBLOCK_GUIDE_STYLE_NONE,
    CODEBLOCK_GUIDE_STYLE_LINE,
    CODEBLOCK_GUIDE_STYLE_LINE_CLOSE,
  }

  enum CodeblockGuidelinesOffset {
    CODEBLOCK_GUIDE_OFFSET_LEFT,
    CODEBLOCK_GUIDE_OFFSET_MIDDLE,
    CODEBLOCK_GUIDE_OFFSET_RIGHT,
  }

  const codeblock_guideline_color = Color(0.8, 0.8, 0.8, 0.3)
  const codeblock_guideline_active_color = Color(0.8, 0.8, 0.8, 0.55)
  const codeblock_guidelines_style: CodeblockGuidelinesStyle = CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_LINE_CLOSE
  const codeblock_guideline_drawside: CodeblockGuidelinesOffset = CodeblockGuidelinesOffset.CODEBLOCK_GUIDE_OFFSET_MIDDLE

  const editor_scale: int = 100 # Used to scale values, but almost useless now

  var code_edit: CodeEdit # Reference to CodeEdit

  func _init(p_code_edit: CodeEdit, exit_sig: Signal)-> void:
    code_edit = p_code_edit
    exit_sig.connect(func()->void: self.queue_free())

    code_edit.add_child(self)
    code_edit.draw.connect(_draw_appendix)
    code_edit.queue_redraw()

  # Return value scaled by editor scale
  func scaled(p_val: float)-> float:
    return p_val * (float(editor_scale) / 100.0)

  func _draw_appendix()-> void:
    if codeblock_guidelines_style == CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_NONE: return

    # Per draw "Consts"
    var lines_count: int = code_edit.get_line_count()
    var style_box: StyleBox = code_edit.get_theme_stylebox("normal")
    var font: Font = code_edit.get_theme_font("font")
    var font_size: int = code_edit.get_theme_font_size("font_size")
    var xmargin_beg: int = style_box.get_margin(SIDE_LEFT) + code_edit.get_total_gutter_width()
    var row_height: int = code_edit.get_line_height()
    var space_width: float = font.get_char_size(" ".unicode_at(0), font_size).x
    var v_scroll: float = code_edit.scroll_vertical
    var h_scroll: float = code_edit.scroll_horizontal

    # X Offset
    var guideline_offset: float
    if codeblock_guideline_drawside == CodeblockGuidelinesOffset.CODEBLOCK_GUIDE_OFFSET_LEFT:
      guideline_offset = 0.0
    elif codeblock_guideline_drawside == CodeblockGuidelinesOffset.CODEBLOCK_GUIDE_OFFSET_MIDDLE:
      guideline_offset = space_width / 2.0
    elif codeblock_guideline_drawside == CodeblockGuidelinesOffset.CODEBLOCK_GUIDE_OFFSET_RIGHT:
      guideline_offset = space_width

    var caret_idx: int = code_edit.get_caret_line()

    # // Let's avoid guidelines out of view.
    var visible_lines_from: int = maxi(code_edit.get_first_visible_line() , 0)
    var visible_lines_to: int = mini(code_edit.get_last_full_visible_line() + int(code_edit.scroll_smooth) + 10, lines_count)

    # V scroll bugged when you fold one of the last block
    var vscroll_delta: float = maxf(v_scroll, visible_lines_from) - visible_lines_from

    # Inlude last ten lines
    if lines_count - visible_lines_to <= 10:
      visible_lines_to = lines_count

    # Generate lines
    var lines_builder: LinesInCodeEditor = LinesInCodeEditor.new(code_edit)
    lines_builder.build(visible_lines_from, visible_lines_to)

    # Prepare draw
    var points: PackedVector2Array
    var colors: PackedColorArray
    var block_ends: PackedInt32Array
    for line: LineInCodeEditor in lines_builder.output:
      var _x: float = guideline_offset + xmargin_beg - h_scroll + line.indent * code_edit.indent_size * space_width
      # Hide lines under gutters
      if _x < xmargin_beg: continue

      # Line color
      var color: Color = codeblock_guideline_color
      if caret_idx > line.lineno_from and caret_idx <= line.lineno_to and lines_builder.indent_level(caret_idx) == line.indent + 1:
        # TODO: If caret not visible on screen line will not highlighted
        color = codeblock_guideline_active_color

      # // Stack multiple guidelines.
      var line_no: int = line.lineno_to
      var offset_y: float = scaled(minf(block_ends.count(line_no) * 2.0, font.get_height(font_size) / 2.0))

      var point_start: Vector2 = Vector2(_x, row_height * (line.start - vscroll_delta))
      var point_end: Vector2 = point_start + Vector2(0.0, row_height * line.length - offset_y)
      points.append_array([point_start, point_end])
      colors.append(color)

      if codeblock_guidelines_style == CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_LINE_CLOSE and line.close_length > 0:
        var line_indent: int = code_edit.get_indent_level(line_no) / code_edit.indent_size + 1
        var point_side: Vector2 = point_end + Vector2(line.close_length * code_edit.indent_size * space_width - guideline_offset, 0.0)

        points.append_array([point_end, point_side])
        colors.append(color)
        block_ends.append(line_no)

    # Draw lines
    if points.size() > 0:
      # As documentation said, no need to scale line width
      RenderingServer.canvas_item_add_multiline(code_edit.get_canvas_item(), points, colors, 1.0)
    pass

# Lines builder
class LinesInCodeEditor:
  var output: Array[LineInCodeEditor] = []
  var lines: Array[LineInCodeEditor] = []

  var ce: CodeEdit

  func _init(p_ce: CodeEdit) -> void:
    self.ce = p_ce

  # Check if line is empty
  func is_line_empty(p_line: int)-> bool:
    return ce.get_line(p_line).strip_edges().length() == 0

  # Return indent level 0,1,2,3..
  func indent_level(p_line: int)-> int:
    return ce.get_indent_level(p_line) / ce.indent_size

  # Return comment index in line
  func get_comment_index(p_line: int)-> int:
    return ce.is_in_comment(p_line)

  # Check if first visible character in line is comment
  func is_line_full_commented(p_line: int)->bool:
    return get_comment_index(p_line) == ce.get_first_non_whitespace_column(p_line)

  # Main func
  func build(p_lines_from: int, p_lines_to: int)->void:
    var line: int = p_lines_from
    var skiped_lines: int = 0
    var internal_line:int = -1
    while line < p_lines_to:
      internal_line += 1
      #If line empty, count it and pass to next line
      if is_line_empty(line):
        skiped_lines += 1
        line += 1
        continue

      # Current line indent
      var line_indent: int = self.indent_level(line)
      if line_indent == 0:
        if is_line_full_commented(line):
          skiped_lines += 1
          line += 1
          continue

      # Close lines with indent > current line_indent
      for i:int in range(line_indent, lines.size()):
        var v: LineInCodeEditor = lines[i]
        v.lineno_to = line - skiped_lines - 1
        v.close_length = self.indent_level(v.lineno_to) - v.indent
        output.append(v)

      if line_indent < lines.size():
        lines.resize(line_indent)

      # Create new line or extend existing
      for i: int in line_indent:
        if lines.size() - 1 < i: # Create
          var l: LineInCodeEditor = LineInCodeEditor.new()
          # Extend start line up
          l.start = internal_line - skiped_lines
          l.length = 1 + skiped_lines
          l.indent = i
          l.lineno_from = line
          l.lineno_to = line
          lines.append(l)
        else:
          # Extend existing line
          lines[i].length += 1 + skiped_lines

      skiped_lines = 0

      # Skip folded lines and regions
      if ce.is_line_folded(line):
        if ce.is_line_code_region_start(line):
          # Folded region
          for subline: int in range(line + 1, p_lines_to):
            if not ce.is_line_code_region_end(subline): continue
            line = subline
            break # Break for cycle
          pass
        else:
          # Usual fold
          var skipped_sublines: int = 0
          for subline: int in range(line + 1, p_lines_to):
            if is_line_empty(subline):
              skipped_sublines += 1
              continue
            var subline_indent: int = self.indent_level(subline)
            if subline_indent > line_indent:
              skipped_sublines = 0 # Line not empty
              continue
            line = subline - skipped_sublines - 1
            break # Break for cycle
      line += 1
    #End of cycle

    # Output all other lines
    for i:int in lines.size():
      var v: LineInCodeEditor = lines[i]
      if p_lines_to == ce.get_line_count():
        v.lineno_to = (p_lines_to - 1) - skiped_lines
        v.close_length = ce.get_indent_level(v.lineno_to) / ce.indent_size - v.indent
        v.length += 1 - skiped_lines
      else:
        v.lineno_to = p_lines_to - 1
        v.length += 1
      output.append(v)
    lines.resize(0)

# Used as struct representiing line
class LineInCodeEditor:
  var start: int = 0 # Line start X
  var length: int = 1 # Line length from start
  var indent: int = -1 # Line indent
  var lineno_from: int = -1 # Line "from" number in CodeEdit
  var lineno_to: int = -1 # Line "to" number in CodeEdit
  var close_length: int = 0 # Side/Close line length

# Single line gutter
class CodeEditorGutterLine extends Node:

  const gutter_color = Color(0.8, 0.8, 0.8, 0.5)

  var code_edit: CodeEdit
  var new_gutter: int = -1

  func _init(p_code_edit: CodeEdit, exit_sig: Signal)-> void:
    code_edit = p_code_edit
    exit_sig.connect(
      func()->void:
        if new_gutter > -1: code_edit.remove_gutter(new_gutter)
        self.queue_free()
    )
    code_edit.add_child(self)

    new_gutter = code_edit.get_gutter_count()
    code_edit.add_gutter(new_gutter)
    code_edit.set_gutter_type(new_gutter, TextEdit.GUTTER_TYPE_CUSTOM)
    code_edit.set_gutter_width(new_gutter, 1)
    code_edit.set_gutter_name(new_gutter, "Line gutter")
    code_edit.set_gutter_custom_draw(new_gutter, _gutter_custom_draw)
    code_edit.set_gutter_draw(new_gutter, true)

  func _gutter_custom_draw(line: int, gutter: int, p_region: Rect2) -> void:
    code_edit.draw_line(p_region.position, p_region.position + p_region.size, gutter_color, 1.0, false )
