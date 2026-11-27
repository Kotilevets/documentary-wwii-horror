class_name ArchiveUI
extends CanvasLayer
## "Witness Archive" (docs/GAMEPLAY_AND_SHADERS.md, section 3).
## Document inspection: a clean realistic "scan" with no distortion
## (Perception suppression), tabs "Документ" / "Архивная справка".
## Journal (J): list of collected documents.
## The game is paused while it is open.

signal opened
signal closed

const PAPER := Color(0.92, 0.90, 0.85)
const INK := Color(0.08, 0.08, 0.08)
const INK_FAINT := Color(0.35, 0.35, 0.35)

var is_open := false
## In a level closing the archive returns the mouse to the look; in the
## main menu it stays visible.
var recapture_mouse := true
var current_document := ""

var _root: Control
var _journal: ItemList
var _tabs: TabContainer
var _doc_text: RichTextLabel
var _note_text: RichTextLabel
var _journal_ids: Array[String] = []


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("archive_journal") \
			or event.is_action_pressed("interact"):
		if Flicker.allow_swap():  # the paper comes and goes no faster than a flash can bear
			close()
		get_viewport().set_input_as_handled()


func open_document(document_id: String) -> void:
	var doc := ArchiveDB.get_document(document_id)
	if doc.is_empty():
		push_error("ArchiveUI: unknown document %s" % document_id)
		return
	current_document = document_id
	_doc_text.text = render_document(doc)
	_note_text.text = render_archive_note(doc)
	_tabs.current_tab = 0
	_tabs.visible = true
	_journal.visible = false
	_show()


func open_journal() -> void:
	if is_open:
		close()
		return
	_journal.clear()
	_journal_ids.clear()
	for id in GameState.archive:
		var doc := ArchiveDB.get_document(id)
		_journal.add_item(_loc(doc.get("title", {}), id))
		_journal_ids.append(id)
	_tabs.visible = false
	_journal.visible = true
	_show()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Perception.pop_suppression()
	get_tree().paused = false
	if recapture_mouse and not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _show() -> void:
	if not is_open:
		is_open = true
		Perception.push_suppression()
		get_tree().paused = true
	_root.visible = true
	if not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


# --- text rendering (static: used by tests) ------------------------------------

static func render_document(doc: Dictionary) -> String:
	var out := "[font_size=26][b]%s[/b][/font_size]\n" % _loc(doc.get("title", {}), "")
	var de_title: String = doc.get("title", {}).get("de", "")
	if de_title != "":
		out += "[i]%s[/i]\n" % de_title
	if doc.has("date"):
		out += "[color=#595959]%s[/color]\n" % doc.date
	out += "\n"
	if doc.get("text_status", "") == "pending":
		out += "[color=#595959][Подлинный текст документа ещё не внесён. Источник — во вкладке «Архивная справка».][/color]\n"
		return out
	var text: Dictionary = doc.get("text", {})
	if text.get("de", "") != "":
		out += "[b]Original:[/b]\n%s\n\n" % text.de
	if text.get("ru", "") != "":
		out += "[b]Перевод:[/b]\n%s\n" % text.ru
	return out


static func render_archive_note(doc: Dictionary) -> String:
	var out := "[font_size=22][b]Архивная справка[/b][/font_size]\n\n"
	out += "%s\n" % _loc(doc.get("archive_note", {}), "")
	for ref_id in doc.get("related", []):
		var ref := ArchiveDB.get_document(ref_id)
		if ref.is_empty():
			continue
		out += "\n[b]%s[/b]\n%s\n" % [_loc(ref.get("title", {}), ref_id), _loc(ref.get("archive_note", {}), "")]
		out += _render_sources(ref.get("sources", []))
	out += "\n[b]Источники[/b]\n" + _render_sources(doc.get("sources", []))
	return out


## A source with a link is a link; a book without one is plain text (an empty link
## would open nothing).
static func _render_sources(sources: Array) -> String:
	var out := ""
	for s in sources:
		var url := str(s.get("url", ""))
		var title := str(s.get("title", url))
		out += ("• [url=%s]%s[/url]\n" % [url, title]) if url != "" else "• %s\n" % title
	return out


static func _loc(field, fallback: String) -> String:
	if field is Dictionary:
		var lang := TranslationServer.get_locale().substr(0, 2)
		return field.get(lang, field.get("ru", fallback))
	return str(field) if field != null else fallback


# --- layout --------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var paper := PanelContainer.new()
	paper.set_anchors_preset(Control.PRESET_CENTER)
	paper.custom_minimum_size = Vector2(860, 900)
	paper.position = -paper.custom_minimum_size * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	paper.add_theme_stylebox_override("panel", style)
	_root.add_child(paper)

	var box := VBoxContainer.new()
	paper.add_child(box)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_paper_controls(_tabs)
	box.add_child(_tabs)
	_doc_text = _make_text("Документ")
	_note_text = _make_text("Архивная справка")
	_tabs.add_child(_doc_text)
	_tabs.add_child(_note_text)

	_journal = ItemList.new()
	_journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal.add_theme_color_override("font_color", INK)
	_journal.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_journal.item_activated.connect(func(i: int) -> void: open_document(_journal_ids[i]))
	_journal.item_clicked.connect(func(i: int, _p: Vector2, _b: int) -> void: open_document(_journal_ids[i]))
	box.add_child(_journal)

	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.pressed.connect(close)
	_style_paper_controls(close_btn)
	box.add_child(close_btn)


## Paper look for default-theme controls: no grey panels, ink-colored text,
## thin ink frames for tabs and the button.
func _style_paper_controls(c: Control) -> void:
	var frame := func(bg: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = INK_FAINT
		s.set_border_width_all(1)
		s.set_content_margin_all(6)
		return s
	if c is TabContainer:
		c.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		c.add_theme_stylebox_override("tab_selected", frame.call(PAPER.darkened(0.12)))
		c.add_theme_stylebox_override("tab_unselected", frame.call(PAPER))
		c.add_theme_stylebox_override("tab_hovered", frame.call(PAPER.darkened(0.06)))
		c.add_theme_color_override("font_selected_color", INK)
		c.add_theme_color_override("font_unselected_color", INK_FAINT)
		c.add_theme_color_override("font_hovered_color", INK)
	elif c is Button:
		c.add_theme_stylebox_override("normal", frame.call(PAPER))
		c.add_theme_stylebox_override("hover", frame.call(PAPER.darkened(0.06)))
		c.add_theme_stylebox_override("pressed", frame.call(PAPER.darkened(0.12)))
		c.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		c.add_theme_color_override("font_color", INK)
		c.add_theme_color_override("font_hover_color", INK)
		c.add_theme_color_override("font_pressed_color", INK)


func _open_link(meta: Variant) -> void:
	if str(meta) != "":
		OS.shell_open(str(meta))


func _make_text(title: String) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.name = title
	t.bbcode_enabled = true
	t.selection_enabled = true
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.add_theme_color_override("default_color", INK)
	t.meta_clicked.connect(_open_link)
	return t
