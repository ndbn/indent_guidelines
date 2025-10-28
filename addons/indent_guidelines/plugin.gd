@tool
extends EditorPlugin

signal sig_plugin_disabled
const META_KEY: String = "has_indent_guideline_plugin"

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
		var found: bool = code_edit.get_meta(META_KEY, false)
		if not found:
			code_edit.set_meta(META_KEY, true)
			CodeEditorGuideLine.new(code_edit, sig_plugin_disabled)

#---------------------------------------------

const SETTINGS_4_3: IndentGuidelinesSettings = preload("./Settings_4_3.tres")
const SETTINGS_4_4: IndentGuidelinesSettings = preload("./Settings_4_4.tres")


# Based on https://github.com/godotengine/godot/pull/65757
class CodeEditorGuideLine extends Node:

	var SETTINGS: IndentGuidelinesSettings = SETTINGS_4_3 if Engine.get_version_info().hex <= 0x040300 else SETTINGS_4_4

	# Some consts
	const OffsetsFactor: Array[float] = [0.0, 0.5, 1.0]
	const editor_scale: int = 100 # Used to scale values, but almost useless now


	var code_edit: CodeEdit # Reference to CodeEdit
	func _init(p_code_edit: CodeEdit, exit_sig: Signal)-> void:
		code_edit = p_code_edit

		exit_sig.connect(func()->void:
			p_code_edit.remove_meta(META_KEY)
			self.queue_free()
		)

		code_edit.add_child(self)
		code_edit.draw.connect(_draw_appendix)
		code_edit.queue_redraw()

	# Return value scaled by editor scale
	func scaled(p_val: float)-> float:
		return p_val * (float(editor_scale) / 100.0)

	func _draw_appendix()-> void:
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
		var indent_size: int = code_edit.indent_size

		# X Offset
		var guideline_offset: float = OffsetsFactor[SETTINGS.guideline_drawside] * space_width

		var caret_idx: int = code_edit.get_caret_line()
		var caret_indent: int = code_edit.get_indent_level(caret_idx)

		# // Let's avoid guidelines out of view.
		var visible_lines_from: int = maxi(code_edit.get_first_visible_line() , 0)
		var visible_lines_to: int = mini(code_edit.get_last_full_visible_line() + int(code_edit.scroll_smooth) + 10, lines_count)

		# V scroll bugged when you fold one of the last block
		var vscroll_delta: float = v_scroll - floorf(v_scroll)

		# Include last ten lines
		if lines_count - visible_lines_to <= 10: visible_lines_to = lines_count

		# Generate lines
		var output: Array[LineInCodeEditor] = []
		var foldedlines: PackedInt32Array = []
		build_lines(code_edit, visible_lines_from, visible_lines_to, output, foldedlines)

		if SETTINGS.guideline_keep_caret:
			var caret_lines: Array[LineInCodeEditor] = []
			var _foldedlines: PackedInt32Array = []

			if caret_idx < visible_lines_from:
				build_lines(code_edit, maxi(caret_idx - 1, 0), visible_lines_from + 1, caret_lines, _foldedlines)

			# Used get_last_full_visible_line cuz visible_lines_to can be == caret_idx
			if caret_idx > code_edit.get_last_full_visible_line(): #visible_lines_to:
				build_lines(code_edit, maxi(visible_lines_to - 1, 0), caret_idx + 1, caret_lines, _foldedlines)

			caret_lines = caret_lines.filter(func(l: LineInCodeEditor) -> bool:
				return l.lineno_from <= caret_idx and caret_idx <= l.lineno_to and l.indent == caret_indent - indent_size
			)

			if caret_lines.size() == 1:
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

			pass


		# Prepare draw
		var points: PackedVector2Array
		var colors: PackedColorArray
		var block_ends: PackedInt32Array

		for line: LineInCodeEditor in output:
			if not SETTINGS.guideline_draw_root_guides and line.indent == 0: continue
			
			var _x: float = xmargin_beg - h_scroll + guideline_offset + line.indent * space_width
			# Hide lines under gutters
			if _x < xmargin_beg: continue

			#	Line color
			var color: Color = SETTINGS.guideline_color
			if caret_idx >= line.lineno_from and caret_idx <= line.lineno_to and caret_indent == line.indent + indent_size:
				# TODO: If caret not visible on screen line will not highlighted
				color = SETTINGS.guideline_active_color

			# // Stack multiple guidelines.
			var line_no: int = line.lineno_to
			var offset_y: float = scaled(minf(block_ends.count(line_no) * 2.0, font.get_height(font_size) / 2.0) + 2.0)
			var point_start: Vector2 = Vector2(_x, row_height * (line.start_x - vscroll_delta) + SETTINGS.guideline_y_offset)
			var point_end: Vector2 = point_start + Vector2(0.0, row_height * line.height - offset_y + SETTINGS.guideline_y_offset)
			points.append_array([point_start, point_end])
			colors.append(color)

			if SETTINGS.guidelines_style == SETTINGS.GuidelinesStyle.LINE_CLOSE and line.close_width > 0:
				var point_side: Vector2 = point_end + Vector2(line.close_width * space_width - guideline_offset, 0.0)
				points.append_array([point_end, point_side])
				colors.append(color)
				block_ends.append(line_no)

		var rid: RID = code_edit.get_canvas_item()
		# Draw lines
		if points.size() > 0:
			# As documentation said, no need to scale line width
			RenderingServer.canvas_item_add_multiline(rid, points, colors, SETTINGS.guideline_width)

		if SETTINGS.draw_fullheight_line:
			var _x: float = xmargin_beg + SETTINGS.fillheight_x_offset
			RenderingServer.canvas_item_add_line(rid, Vector2(_x, 0), Vector2(_x, code_edit.size.y), SETTINGS.fillheight_line_color, 2.0 )
			pass

		if SETTINGS.draw_foldmarks:
			var _x: float = xmargin_beg + SETTINGS.foldmark_x_offset
			var folded_lines: Array[int] = code_edit.get_folded_lines()

			var fm_points: PackedVector2Array
			var fm_colors: PackedColorArray
			for internal_line: int in foldedlines:
				var point_start: Vector2 = Vector2(_x, row_height * (internal_line - vscroll_delta) + SETTINGS.foldmark_y_offset)
				var point_end: Vector2 = point_start + Vector2(0.0, row_height + SETTINGS.foldmark_y_offset)
				fm_points.append_array([point_start, point_end])
				fm_colors.append(SETTINGS.foldmark_color)
			if fm_points.size() > 0:
				RenderingServer.canvas_item_add_multiline(rid, fm_points, fm_colors, SETTINGS.foldmark_width)
		pass # /_draw_appendix



	# Lines builder
	func build_lines(code_edit: CodeEdit, p_lines_from: int, p_lines_to: int, output: Array[LineInCodeEditor], foldedlines: PackedInt32Array ) -> void:
		var indent_size: int = code_edit.indent_size
		var skiped_lines: int = 0
		var internal_line: int = -1
		var tmp_lines: Array[LineInCodeEditor] = []
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
						or (current_indent_level <= tmp_lines.size() and code_edit.is_in_comment(line) != -1 and code_edit.is_in_comment(line) == code_edit.get_first_non_whitespace_column(line)):
							# Lines with same indent count as part of scope
							skiped_lines += 1
							line += 1
							continue

			# Close lines with indent > current line_indent
			for i:int in range(current_indent_level, tmp_lines.size()):
				var v: LineInCodeEditor = tmp_lines[i]
				v.lineno_to = line - skiped_lines - 1
				v.close_width = code_edit.get_indent_level(v.lineno_to) - v.indent
				if skip_was_folded: v.close_width -= indent_size # Decrease indend when skipping folded lines
				output.append(v)

			if current_indent_level < tmp_lines.size(): tmp_lines.resize(current_indent_level)

			# Create new line or extend existing
			for i: int in current_indent_level:
				if tmp_lines.size() - 1 < i: # Create
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
		for i:int in tmp_lines.size():
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

# Used as struct representing line
class LineInCodeEditor:
	var start_x: int = 0 # Line start X
	var height: int = 1 # Line height from start
	var indent: int = -1 # Line indent
	var lineno_from: int = -1 # Line "from" number in CodeEdit
	var lineno_to: int = -1 # Line "to" number in CodeEdit
	var close_width: int = 0 # Side/Close line length
