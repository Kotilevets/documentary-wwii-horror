class_name PassView
extends Control
## A pass drawn as a clean "scan": paper, the printed form shown only as
## grey lines (the real form's wording is a document the author enters),
## the handwritten fields (number, date, route) and the stamp.

const PAPER := Color(0.9, 0.88, 0.82)
const PRINT := Color(0.62, 0.6, 0.56)
const INK := Color(0.1, 0.1, 0.12)
const STAMP := Color(0.25, 0.25, 0.3, 0.85)

var pass_data: Dictionary = {}:
	set(v):
		pass_data = v
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, PAPER)
	draw_rect(r, PRINT, false, 2.0)
	if pass_data.is_empty():
		return
	var font := get_theme_default_font()
	var w := size.x
	var h := size.y
	# Printed form: illegible grey lines.
	for i in 5:
		var y := h * (0.12 + i * 0.07)
		draw_line(Vector2(w * 0.1, y), Vector2(w * (0.9 - 0.1 * (i % 2)), y), PRINT, 3.0)
	# Handwritten fields.
	var fs := int(h * 0.06)
	draw_string(font, Vector2(w * 0.1, h * 0.55), str(pass_data.get("serial", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	draw_string(font, Vector2(w * 0.1, h * 0.65),
			"до " + PassRules.human_date(str(pass_data.get("valid_until", ""))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	draw_string(font, Vector2(w * 0.1, h * 0.75), " — ".join(pass_data.get("route", [])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	# Stamp.
	var cx := w * (0.75 if pass_data.get("stamp_side") == "right" else 0.25)
	var c := Vector2(cx, h * 0.87)
	var rad := h * 0.09
	if pass_data.get("stamp_shape") == "round":
		draw_arc(c, rad, 0, TAU, 48, STAMP, 3.0)
		draw_arc(c, rad * 0.72, 0, TAU, 48, STAMP, 1.5)
	else:
		draw_rect(Rect2(c - Vector2(rad, rad * 0.75), Vector2(rad * 2, rad * 1.5)), STAMP, false, 3.0)
		draw_rect(Rect2(c - Vector2(rad, rad * 0.75) * 0.72, Vector2(rad * 2, rad * 1.5) * 0.72), STAMP, false, 1.5)
	draw_line(c - Vector2(rad * 0.4, 0), c + Vector2(rad * 0.4, 0), STAMP, 2.0)
