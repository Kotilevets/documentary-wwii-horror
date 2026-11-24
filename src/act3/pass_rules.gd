class_name PassRules
extends RefCounted
## Act III pass check (GAMEPLAY_AND_SHADERS.md, 4): a forged pass passes
## the checkpoint only if its stamp (shape and place), date (still valid
## today) and route (includes the destination) match the genuine sample.
## Data: assets/data/act3/passes.json (game data, not a historical form).

const DATA_PATH := "res://assets/data/act3/passes.json"


static func load_data() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func find(data: Dictionary, id: String) -> Dictionary:
	for c in data.get("candidates", []):
		if c.get("id", "") == id:
			return c
	return {}


## Names of what is wrong with the pass: "stamp", "date", "route".
static func flaws(pass_data: Dictionary, data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if pass_data.is_empty():
		out.append("missing")
		return out
	var sample: Dictionary = data.get("sample", {})
	if pass_data.get("stamp_shape") != sample.get("stamp_shape") \
			or pass_data.get("stamp_side") != sample.get("stamp_side"):
		out.append("stamp")
	# ISO dates compare as strings.
	if str(pass_data.get("valid_until", "")) < str(data.get("today", "")):
		out.append("date")
	if not (pass_data.get("route", []) as Array).has(data.get("destination", "")):
		out.append("route")
	return out


static func is_valid(pass_data: Dictionary, data: Dictionary) -> bool:
	return flaws(pass_data, data).is_empty()


## "1942-10-31" -> "31.10.1942"
static func human_date(iso: String) -> String:
	var p := iso.split("-")
	return "%s.%s.%s" % [p[2], p[1], p[0]] if p.size() == 3 else iso
