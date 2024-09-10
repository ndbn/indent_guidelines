@tool
extends EditorPlugin

signal sig_plugin_disabled

const draw_guidelines: bool = true
const draw_linegutter: bool = false

func _enter_tree() -> void:
  if not Engine.is_editor_hint(): return
  var script_editor: ScriptEditor = EditorInterface.get_script_editor()
  if not script_editor.editor_script_changed.is_connected(_editor_script_changed):
    script_editor.editor_script_changed.connect(_editor_script_changed)
    script_editor.editor_script_changed.emit(EditorInterface.get_script_editor().get_current_script())

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
    CODEBLOCK_GUIDE_STYLE_LINE_CLOSE
  }

  const codeblock_guideline_color = Color(0.8, 0.8, 0.8, 0.1)
  const codeblock_guideline_active_color = Color(0.8, 0.8, 0.8, 0.25)
  const codeblock_guidelines_style: CodeblockGuidelinesStyle = CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_LINE_CLOSE

  var code_edit: CodeEdit

  func _init(p_code_edit: CodeEdit, exit_sig: Signal)-> void:
    code_edit = p_code_edit
    exit_sig.connect(func()->void: self.queue_free())

    code_edit.add_child(self)
    code_edit.draw.connect(_draw_appendix)
    code_edit.queue_redraw()

  #region CodeEdit bindings
  func is_in_string(p_line: int)->int: return code_edit.is_in_string(p_line)

  func is_in_comment(p_line: int)->int: return code_edit.is_in_comment(p_line)

  func is_line_folded(p_line: int)->bool: return code_edit.is_line_folded(p_line)

  func get_line(p_line: int)->String: return code_edit.get_line(p_line)

  func _is_line_hidden(p_line: int)->bool: return false #code_edit._is_line_hidden(p_line)

  func get_indent_level(p_line: int)->int: return code_edit.get_indent_level(p_line)

  func get_line_count()->int: return code_edit.get_line_count()

  func get_delimiter_end_position(line: int, column: int)->Vector2: return code_edit.get_delimiter_end_position(line, column)

  func get_total_gutter_width()->int: return code_edit.get_total_gutter_width()

  func style_normal()->StyleBox:
    return code_edit.get_theme_stylebox("normal", "CodeEdit")

  func font()->Font:
    return code_edit.get_theme_font("font", "CodeEdit") # ???

  func font_size()->int:
    return code_edit.get_theme_font_size("font_size", "CodeEdit") # ???

  func get_v_scroll()->int:
    return code_edit.scroll_vertical

  func get_h_scroll()->int:
    return code_edit.scroll_horizontal

  func get_first_visible_line()-> int:
    return code_edit.get_first_visible_line()

  func get_visible_line_count()->int:
    return code_edit.get_visible_line_count()

  func is_smooth_scroll_enabled()->bool:
    return code_edit.scroll_smooth

  func auto_brace_completion_pairs()-> Dictionary:
    return code_edit.auto_brace_completion_pairs

  func get_caret_line(caret_index: int = 0)-> int:
    return code_edit.get_caret_line(caret_index)

  func get_visible_line_count_in_range(from_line: int, to_line: int)-> int:
    return code_edit.get_visible_line_count_in_range(from_line, to_line)

  func get_line_height()->int:
    return code_edit.get_line_height()

  #endregion CodeEdit bindings

  func _draw_appendix()-> void:
    var row_height: int = get_line_height()
    var code_edit_ci: RID = code_edit.get_canvas_item()
    # /* Codeblock Guidelines */
    if codeblock_guidelines_style == CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_NONE: return
    var xmargin_beg: int = style_normal().get_margin(SIDE_LEFT) + get_total_gutter_width()
    var space_width: float = font().get_char_size(" ".unicode_at(0), font_size()).x
    var v_scroll: int = get_v_scroll()
    var h_scroll: int = get_h_scroll()

    # // Let's avoid guidelines out of view.
    var visible_lines_from: int = maxi(get_first_visible_line() - 1, 0)
    var visible_lines_to: int = mini(visible_lines_from + get_visible_line_count() + 1 + (1 if is_smooth_scroll_enabled() else 0), get_line_count())


    var points: PackedVector2Array
    var colors: PackedColorArray
    var block_ends: PackedInt32Array
    for i: int in visible_lines_to:
      if _is_line_hidden(i): continue

      if _can_fold_line(i):
        var block_start: int = i # // This is a line that can potentially fold.
        var block_end: int = _get_fold_line_ending(block_start)

        if block_end <= 0: continue

        var indent_level_start: int = get_indent_level(i)
        var indent_level_inner: int = get_indent_level(i + 1)

        # // Check if this codeblock contains the caret.
        var color: Color = codeblock_guideline_color
        var caret_idx: int = get_caret_line()

        if caret_idx > block_start and caret_idx <= block_end and get_indent_level(caret_idx) == indent_level_inner:
          color = codeblock_guideline_active_color

        var indent_guide_x: float = (indent_level_start * space_width + space_width / 2) + xmargin_beg - h_scroll

        var skipped_lines_to_start: int = block_start - get_visible_line_count_in_range(0, block_start)
        var skipped_lines_to_end: int = block_end - get_visible_line_count_in_range(0, block_end)
        var visible_indent_start: int = (block_start - v_scroll - skipped_lines_to_start)
        var visible_indent_end: int = (block_end - v_scroll - skipped_lines_to_end)

        # // Stack multiple guidelines.
        var offset_y: float = minf(block_ends.count(block_end) * 2.0, font().get_height(font_size()) / 2.0)

        #// Vertical line to the end.
        var point_start: Vector2 = Vector2(indent_guide_x, row_height * visible_indent_start)
        var point_end: Vector2 = Vector2(indent_guide_x, row_height * visible_indent_end - offset_y)

        #RenderingServer.canvas_item_add_line(code_edit_ci, point_start, point_end, color, 1.0)
        points.append_array([point_start, point_end])
        colors.append(color)


        if codeblock_guidelines_style == CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_LINE_CLOSE and block_end <= visible_lines_to:
          # // Horizontal guideline starting from the end,
          # // Drawn whenever a closing bracket underneath is unavailable, or already taken by a higher guideline.
          var line_below: String = get_line(block_end + 1).strip_edges()

          var bottom_begins_with_close_brace: bool = false
          var auto_brace_completion_pairs: Dictionary = auto_brace_completion_pairs()

          for pair_idx: String in auto_brace_completion_pairs:
            if line_below.begins_with(auto_brace_completion_pairs[pair_idx]):
              bottom_begins_with_close_brace = true

          if !bottom_begins_with_close_brace or block_ends.has(block_end):
            var indent_guide_side_x: float = indent_guide_x + (get_indent_level(block_end) - indent_level_start) * space_width
            var point_side: Vector2 = Vector2(indent_guide_side_x, row_height * visible_indent_end - offset_y)

            #RenderingServer.canvas_item_add_line(code_edit_ci, point_end, point_side, color, 1.0)
            points.append_array([point_end, point_side])
            colors.append(color)

        block_ends.append(block_end)
    if points.size() > 0 :
      RenderingServer.canvas_item_add_multiline(code_edit_ci, points, colors, 1.0)

  func _draw_appendix_old()-> void:
      var row_height: int = get_line_height()
      var code_edit_ci: RID = code_edit.get_canvas_item()
      # /* Codeblock Guidelines */
      if codeblock_guidelines_style == CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_NONE: return
      var xmargin_beg: int = style_normal().get_margin(SIDE_LEFT) + get_total_gutter_width()
      var space_width: float = font().get_char_size(" ".unicode_at(0), font_size()).x
      var v_scroll: int = get_v_scroll()
      var h_scroll: int = get_h_scroll()

      # // Let's avoid guidelines out of view.
      var visible_lines_from: int = maxi(get_first_visible_line() - 1, 0)
      var visible_lines_to: int = mini(visible_lines_from + get_visible_line_count() + 1 + (1 if is_smooth_scroll_enabled() else 0), get_line_count())

      var block_ends: PackedInt32Array
      for i:int in visible_lines_to:
        if _is_line_hidden(i): continue

        if _can_fold_line(i):
          var block_start: int = i # // This is a line that can potentially fold.
          var block_end: int = _get_fold_line_ending(block_start)

          if block_end <= 0: continue

          var indent_level_start: int = get_indent_level(i)
          var indent_level_inner: int = get_indent_level(i + 1)

          # // Check if this codeblock contains the caret.
          var color: Color = codeblock_guideline_color
          var caret_idx: int = get_caret_line()

          if caret_idx > block_start and caret_idx <= block_end and get_indent_level(caret_idx) == indent_level_inner:
            color = codeblock_guideline_active_color

          var indent_guide_x: float = (indent_level_start * space_width + space_width / 2) + xmargin_beg - h_scroll

          var skipped_lines_to_start: int = block_start - get_visible_line_count_in_range(0, block_start)
          var skipped_lines_to_end: int = block_end - get_visible_line_count_in_range(0, block_end)
          var visible_indent_start: int = (block_start - v_scroll - skipped_lines_to_start)
          var visible_indent_end: int = (block_end - v_scroll - skipped_lines_to_end)

          # // Stack multiple guidelines.
          var offset_y: float = minf(block_ends.count(block_end) * 2.0, font().get_height(font_size()) / 2.0)

          #// Vertical line to the end.
          var point_start: Vector2 = Vector2(indent_guide_x, row_height * visible_indent_start)
          var point_end: Vector2 = Vector2(indent_guide_x, row_height * visible_indent_end - offset_y)

          RenderingServer.canvas_item_add_line(code_edit_ci, point_start, point_end, color, 1.0)


          if codeblock_guidelines_style == CodeblockGuidelinesStyle.CODEBLOCK_GUIDE_STYLE_LINE_CLOSE and block_end <= visible_lines_to:
            # // Horizontal guideline starting from the end,
            # // Drawn whenever a closing bracket underneath is unavailable, or already taken by a higher guideline.
            var line_below: String = get_line(block_end + 1).strip_edges()

            var bottom_begins_with_close_brace: bool = false
            var auto_brace_completion_pairs: Dictionary = auto_brace_completion_pairs()

            for pair_idx: String in auto_brace_completion_pairs:
              if line_below.begins_with(auto_brace_completion_pairs[pair_idx]):
                bottom_begins_with_close_brace = true

            if !bottom_begins_with_close_brace or block_ends.has(block_end):
              var indent_guide_side_x: float = indent_guide_x + (get_indent_level(block_end) - indent_level_start) * space_width
              var point_side: Vector2 = Vector2(indent_guide_side_x, row_height * visible_indent_end - offset_y)

              RenderingServer.canvas_item_add_line(code_edit_ci, point_end, point_side, color, 1.0)

          block_ends.append(block_end)

  func _can_fold_line(p_line: int)-> bool:
    if p_line + 1 >= get_line_count() or get_line(p_line).strip_edges().length() == 0 :
      return false

    if (_is_line_hidden(p_line) or is_line_folded(p_line)):
      return false

    # /* Check for full multiline line or block strings / comments. */
    var in_comment: int = is_in_comment(p_line)
    var in_string: int = is_in_string(p_line) if in_comment == -1 else -1

    if in_string != -1 or in_comment != -1:
      if code_edit.get_delimiter_start_position(p_line, get_line(p_line).length() - 1).y != p_line:
        return false

      var delimter_end_line: int = code_edit.get_delimiter_end_position(p_line, get_line(p_line).length() - 1).y
      # /* No end line, therefore we have a multiline region over the rest of the file. */
      if delimter_end_line == -1:
        return true

      # /* End line is the same therefore we have a block. */
      if delimter_end_line == p_line:
        # /* Check we are the start of the block. */
        if p_line - 1 >= 0:
          if (in_string != -1 and is_in_string(p_line - 1) != -1) or (in_comment != -1 and is_in_comment(p_line - 1) != -1):
            return false

        # /* Check it continues for at least one line. */
        return (in_string != -1 and is_in_string(p_line + 1) != -1) or (in_comment != -1 and is_in_comment(p_line + 1) != -1)

      return (in_string != -1 and is_in_string(delimter_end_line) != -1) or (in_comment != -1 and is_in_comment(delimter_end_line) != -1)

    # /* Otherwise check indent levels. */
    var start_indent: int = get_indent_level(p_line)
    for i:int in range(p_line + 1, get_line_count()):
      if is_in_string(i) != -1 or is_in_comment(i) != -1 or get_line(i).strip_edges().length() == 0:
        continue
      return get_indent_level(i) > start_indent

    return false


  func _get_fold_line_ending(p_line: int)-> int:
    # /* Find the last line to be hidden. */
    var line_count: int = get_line_count() - 1
    var end_line: int = line_count

    var in_comment: int = is_in_comment(p_line)
    var in_string: int = is_in_string(p_line) if in_comment == -1 else -1
    if in_string != -1 or in_comment != -1:
      end_line = get_delimiter_end_position(p_line, get_line(p_line).length() - 1).y
      # /* End line is the same therefore we have a block of single line delimiters. */
      if end_line == p_line :
        for i: int in range(p_line + 1, line_count):
          if (in_string != -1 and is_in_string(i) == -1) or (in_comment != -1 and is_in_comment(i) == -1):
            break
          end_line = i
    else:
      var start_indent: int = get_indent_level(p_line)
      for i: int in range(p_line + 1, line_count):
        if get_line(i).strip_edges().length() == 0:
          continue

        if get_indent_level(i) > start_indent:
          end_line = i
          continue

        if is_in_string(i) == -1 and is_in_comment(i) == -1:
          break

    return end_line

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
