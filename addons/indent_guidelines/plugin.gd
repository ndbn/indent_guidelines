@tool
extends EditorPlugin

# Originally based on https://github.com/godotengine/godot/pull/65757

var ids_code_edits: Array[int]   # CodeEdit instance ID's
var rids_code_edits: Array[RID]	 # Corresponding canvas_item RID's

var settings: IndentGuidelinesSettings = IndentGuidelinesSettings.new()

func _enter_tree() -> void:
	if not Engine.is_editor_hint(): return

	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	var on_script_changed: Signal = script_editor.editor_script_changed
	if not on_script_changed.is_connected(_editor_script_changed):
		on_script_changed.connect(_editor_script_changed)
		on_script_changed.emit(script_editor.get_current_script())

func _exit_tree() -> void:
	for i: int in len(ids_code_edits):
		var code_edit: CodeEdit = instance_from_id(ids_code_edits[i])
		if code_edit != null:	code_edit.draw.disconnect(_draw_appendix)
		if rids_code_edits[i].is_valid():	RenderingServer.free_rid(rids_code_edits[i])
	ids_code_edits.clear()
	rids_code_edits.clear()

func _notification(what: int) -> void:
	if what == EditorSettings.NOTIFICATION_EDITOR_SETTINGS_CHANGED:
		var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
		if editor_settings.check_changed_settings_in_group(settings.settings_group):
			settings.update_settings(false)
			for i: int in len(ids_code_edits):
				var code_edit: CodeEdit = instance_from_id(ids_code_edits[i])
				if code_edit != null:
					code_edit.add_theme_constant_override("completion_lines", settings.tweak_completion_lines)
					code_edit.add_theme_constant_override("completion_max_width", settings.tweak_completion_max_width)
					code_edit.queue_redraw()

func try_get_code_edit() -> CodeEdit:
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	if not script_editor: return
	var editor_base: ScriptEditorBase = script_editor.get_current_editor()
	if not editor_base: return
	var code_edit: Control = editor_base.get_base_editor()
	if code_edit is CodeEdit:
		var found: bool = code_edit.draw.is_connected(_draw_appendix)
		if not found:
			return code_edit
	return null

func _editor_script_changed(_s: Script)->void:
	var code_edit: CodeEdit = try_get_code_edit()
	if not code_edit: return

	if Engine.get_version_info().hex >= 0x040600: code_edit.clip_contents = true # for >=4.6 set cliping true

	# Clean
	for i:int in range(len(ids_code_edits) - 1, 0, -1):
		var id: int = ids_code_edits[i]
		if instance_from_id(id) == null:
			ids_code_edits.remove_at(i)
			rids_code_edits.remove_at(i)

	var draw_rid: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(draw_rid, code_edit.get_canvas_item())

	ids_code_edits.push_back(code_edit.get_instance_id())
	rids_code_edits.push_back(draw_rid)

	# Override theme constants
	code_edit.add_theme_constant_override("completion_lines", settings.tweak_completion_lines)
	code_edit.add_theme_constant_override("completion_max_width", settings.tweak_completion_max_width)

	code_edit.draw.connect(_draw_appendix.bind(code_edit, draw_rid))
	code_edit.queue_redraw()


#---------------------------------------------

# Return value scaled by editor scale
func scaled(p_val: float)-> float:
	const editor_scale: int = 100 # Used to scale values, but almost useless now
	return p_val * (float(editor_scale) / 100.0)

# based on CodeEdit::fold_line
func get_next_unfolded_line(code_edit: CodeEdit, line: int) -> int:
	var p_lines_to: int = code_edit.get_line_count()

	if code_edit.is_line_code_region_start(line):
		var region_level: int = 0
		for i: int in range(line + 1, p_lines_to):
			if code_edit.is_line_code_region_start(i): region_level += 1
			if code_edit.is_line_code_region_end(i):
				if region_level == 0:
					line = i
					break
				region_level -= 1
	else:
		var start_in_comment: int = code_edit.is_in_comment(line)
		var start_in_string: int = code_edit.is_in_string(line) if start_in_comment == 1 else -1;
		if start_in_string != -1 or start_in_comment != -1:
			var end_line: int = code_edit.get_delimiter_end_position(line, code_edit.get_line(line).length() - 1).y
			if end_line == line:
				for i: int in range(line + 1, p_lines_to):
					if start_in_string != -1 and code_edit.is_in_string(i) == -1: break
					if start_in_comment != -1 and code_edit.is_in_comment(i) == -1: break
					line = i
		else:
			var start_indent = code_edit.get_indent_level(line);
			for i: int in range(line + 1, p_lines_to):
				if code_edit.get_line(i).strip_edges().is_empty(): continue
				if code_edit.get_indent_level(i) > start_indent:
					line = i
					continue
				elif code_edit.is_in_comment(i) == -1 and code_edit.is_in_string(i) == -1:
					break
	return line + 1

# Lines builder
func build_lines(code_edit: CodeEdit, p_lines_from: int, p_lines_to: int, output: Array[LineInCodeEditor], foldedlines: PackedInt32Array ) -> void:
	var indent_size: int = code_edit.indent_size
	var skiped_lines: int = 0
	var internal_line: int = -1
	var tmp_lines: Array[LineInCodeEditor]
	var skip_was_folded: bool = false
	var line: int = p_lines_from

	while line < p_lines_to:
		internal_line += 1
		var current_line_indent: int = code_edit.get_indent_level(line) # Current line indent
		var current_indent_level: int = current_line_indent / indent_size

			#If line empty, count it and pass to next line
		var current_line_folded: bool = code_edit.is_line_folded(line)
		if !current_line_folded:
			if code_edit.get_line(line).strip_edges().length() == 0 \
				or (current_indent_level <= len(tmp_lines) and code_edit.is_in_comment(line) != -1 and code_edit.is_in_comment(line) == code_edit.get_first_non_whitespace_column(line)):
							# Lines with same indent count as part of scope
					skiped_lines += 1
					line += 1
					continue

			# Close lines with indent > current line_indent
		for i:int in range(current_indent_level, len(tmp_lines)):
			var v: LineInCodeEditor = tmp_lines[i]
			v.lineno_to = line - skiped_lines - 1
			v.close_width = code_edit.get_indent_level(v.lineno_to) - v.indent
			if skip_was_folded: v.close_width -= indent_size # Decrease indend when skipping folded lines
			output.append(v)

		if current_indent_level < len(tmp_lines): tmp_lines.resize(current_indent_level)

			# Create new line or extend existing
		for i: int in current_indent_level:
			if len(tmp_lines) <= i: # Create
				var l: LineInCodeEditor = LineInCodeEditor.new()
					# Extend start line up
				l.start_x = internal_line - skiped_lines
				l.height = 1 + skiped_lines
				l.indent = i * indent_size
				l.lineno_from = line - skiped_lines
				l.lineno_to = p_lines_to - 1
				tmp_lines.append(l)
			else:
					# Extend existing line
				tmp_lines[i].height += 1 + skiped_lines

		skiped_lines = 0
			# Skip folded lines and regions
		skip_was_folded = current_line_folded
		if skip_was_folded:
			foldedlines.append(internal_line) # Store internal folded line
			line = get_next_unfolded_line(code_edit, line) - 1
		line += 1
		#End of cycle

	var lines_count = code_edit.get_line_count()
		# Output all other lines
	for i:int in len(tmp_lines):
		var v: LineInCodeEditor = tmp_lines[i]
		if p_lines_to == lines_count:
			v.lineno_to -= skiped_lines
			v.close_width = code_edit.get_indent_level(v.lineno_to) - v.indent
				# v.height += 1 - skiped_lines # At end of file there is bug with lines
			if skip_was_folded: v.close_width -= indent_size # Decrease indend when skipping folded lines
		else:
			v.lineno_to = p_lines_to - 1
			v.height += 1
		output.append(v)
		pass
	pass #/build_lines

func _draw_appendix(code_edit: CodeEdit, draw_rid: RID)-> void:

	# Per draw "Consts"
	var lines_count: int = code_edit.get_line_count()
	var style_box: StyleBox = code_edit.get_theme_stylebox("normal")
	var font: Font = code_edit.get_theme_font("font")
	var font_size: int = code_edit.get_theme_font_size("font_size")
	var xmargin_beg: int = style_box.get_margin(SIDE_LEFT) + code_edit.get_total_gutter_width()
	var row_height: int = code_edit.get_line_height()
	var space_width: float = font.get_char_size(" ".unicode_at(0), font_size).x
	var indent_size: int = code_edit.indent_size

	# X Offset
	var guideline_offset: float = [0.0, 0.5, 1.0].get(settings.guideline_drawside) * space_width

	var v_scroll: float = code_edit.scroll_vertical
	var h_scroll: float = code_edit.scroll_horizontal

	# Clear canvas item RID
	RenderingServer.canvas_item_clear(draw_rid)

	var caret_idx: int = code_edit.get_caret_line()
	var caret_indent: int = code_edit.get_indent_level(caret_idx)

	# // Let's avoid guidelines out of view.
	var visible_lines_from: int = maxi(code_edit.get_first_visible_line() , 0)
	var visible_lines_to: int = mini(code_edit.get_last_full_visible_line() + int(code_edit.scroll_smooth) + 10, lines_count)

	var vscroll_delta: float = v_scroll - floorf(v_scroll) # V scroll can be bugged when you fold one of the last block

	# Include last ten lines
	if lines_count - visible_lines_to <= 10: visible_lines_to = lines_count

	# Generate lines
	var output: Array[LineInCodeEditor]
	var foldedlines: PackedInt32Array
	build_lines(code_edit, visible_lines_from, visible_lines_to, output, foldedlines)

	var draw_guidelines_fn: Callable = (func()->void:
		if settings.guideline_keep_caret:
			var caret_lines: Array[LineInCodeEditor]
			var _foldedlines: PackedInt32Array

			var caret_from: int = 0
			var caret_to: int = 0
			if caret_idx < visible_lines_from:
				caret_from = maxi(caret_idx - 1, 0)
				caret_to = visible_lines_from + 1
			elif caret_idx > code_edit.get_last_full_visible_line():
				# Used get_last_full_visible_line cuz visible_lines_to can be == caret_idx
				caret_from = maxi(visible_lines_to - 1, 0)
				caret_to = caret_idx + 1


			if caret_from != caret_to:
				build_lines(code_edit, caret_from, caret_to, caret_lines, _foldedlines)

				caret_lines = caret_lines.filter(func(l: LineInCodeEditor) -> bool:
					return l.lineno_from <= caret_idx and caret_idx <= l.lineno_to and l.indent == caret_indent - indent_size
				)

				if len(caret_lines) == 1:
					var nl: LineInCodeEditor = caret_lines[0]
					# Update array with Lines
					for l: LineInCodeEditor in output:
						if l.lineno_from <= nl.lineno_from and	nl.lineno_from <= l.lineno_to and nl.indent == l.indent:
							l.lineno_from = mini(l.lineno_from, nl.lineno_from)
							l.lineno_to = maxi(l.lineno_to, nl.lineno_to)
							break
						if l.lineno_from <= nl.lineno_to and	nl.lineno_to <= l.lineno_to and nl.indent == l.indent:
							l.lineno_from = mini(l.lineno_from, nl.lineno_from)
							l.lineno_to = maxi(l.lineno_to, nl.lineno_to)
							break

		# Prepare draw
		var points: PackedVector2Array
		var colors: PackedColorArray
		var block_ends: PackedInt32Array

		for line: LineInCodeEditor in output:
			if not settings.guideline_draw_root_guides and line.indent == 0: continue

			var _x: float = xmargin_beg - h_scroll + guideline_offset + line.indent * space_width

			if _x < xmargin_beg: continue# Hide lines under gutters

			#	Line color
			var color: Color = settings.guideline_color
			if caret_idx >= line.lineno_from and caret_idx <= line.lineno_to and caret_indent == line.indent + indent_size:
				color = settings.guideline_active_color

			# // Stack multiple guidelines.
			var line_no: int = line.lineno_to
			var offset_y: float = scaled(minf(block_ends.count(line_no) * 2.0, font.get_height(font_size) / 2.0) + 2.0)
			var point_start: Vector2 = Vector2(_x, row_height * (line.start_x - vscroll_delta) + settings.guideline_y_offset)
			var point_end: Vector2 = point_start + Vector2(0.0, row_height * line.height - offset_y + settings.guideline_y_offset)
			points.append_array([point_start, point_end])
			colors.append(color)

			if settings.guidelines_style == settings.GuidelinesStyle.LINE_CLOSE and line.close_width > 0:
				var point_side: Vector2 = point_end + Vector2(line.close_width * space_width - guideline_offset, 0.0)
				points.append_array([point_end, point_side])
				colors.append(color)
				block_ends.append(line_no)

		# Draw lines
		# As documentation said, no need to scale line width
		if len(points) > 0:	RenderingServer.canvas_item_add_multiline(draw_rid, points, colors, settings.guideline_width)

		)

	var draw_fullheight_line_fn: Callable = (func()->void:
		var _x: float = xmargin_beg + settings.fillheight_x_offset
		RenderingServer.canvas_item_add_line(draw_rid, Vector2(_x, 0), Vector2(_x, code_edit.size.y), settings.fillheight_line_color, 2.0 )
		)

	var draw_foldmarks_fn: Callable = (func()->void:
		var _x: float = xmargin_beg + settings.foldmark_x_offset

		var fm_points: PackedVector2Array
		var fm_colors: PackedColorArray
		for internal_line: int in foldedlines:
			var point_start: Vector2 = Vector2(_x, row_height * (internal_line - vscroll_delta) + settings.foldmark_y_offset)
			var point_end: Vector2 = point_start + Vector2(0.0, row_height + settings.foldmark_y_offset)
			fm_points.append_array([point_start, point_end])
			fm_colors.append(settings.foldmark_color)
		if len(fm_points) > 0: RenderingServer.canvas_item_add_multiline(draw_rid, fm_points, fm_colors, settings.foldmark_width)
		)

	if settings.draw_guidelines:	draw_guidelines_fn.call()
	if settings.draw_fullheight_line: draw_fullheight_line_fn.call()
	if settings.draw_foldmarks: draw_foldmarks_fn.call()


# Used as struct representing line
class LineInCodeEditor:
	var start_x: int = 0 # Line start X
	var height: int = 1 # Line height from start
	var indent: int = -1 # Line indent
	var lineno_from: int = -1 # Line "from" number in CodeEdit
	var lineno_to: int = -1 # Line "to" number in CodeEdit
	var close_width: int = 0 # Side/Close line length
