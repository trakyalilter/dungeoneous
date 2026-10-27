class_name UiKit
extends RefCounted
## Shared widget builders and the UI theme, so every screen looks the same.

const BG := Color("#15151d")
const PANEL := Color("#20202b")

static var _mono: SystemFont
static var _serif: SystemFont
static var sfx: Sfx  # set by main so every button can click


static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	return _mono


## Fantasy-flavored heading font (falls back to any serif).
static func serif() -> SystemFont:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
		_serif.font_weight = 700
	return _serif


## Big title text in the heading font, with an outline.
static func heading(text: String, size: int, hex: String = GameLog.YELLOW) -> Label:
	var l := label(text, size, hex)
	l.add_theme_font_override("font", serif())
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.add_theme_color_override("font_outline_color", Color("#1a0e06"))
	return l


static func click() -> void:
	if sfx:
		sfx.play("click", 0.1)


## Square button showing a GameIcon, with a tooltip.
static func icon_button(icon_id: String, tip: String, callback: Callable, px: int = 34) -> Button:
	var b := button("", callback)
	b.custom_minimum_size = Vector2(px, px)
	b.tooltip_text = tip
	var icon := GameIcon.make(icon_id, px - 12)
	icon.size = Vector2(px - 12, px - 12)
	icon.position = Vector2(6, 6)
	b.add_child(icon)
	return b


static func label(text: String, size: int, hex: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if hex != "":
		l.add_theme_color_override("font_color", Color(hex))
	return l


static func button(text: String, callback: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(click)
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


static func panel(color: Color = PANEL, margin: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func rich(size: int = 15, use_mono: bool = false) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	if use_mono:
		r.add_theme_font_override("normal_font", mono())
	return r


static func bar(height: int = 16) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#30303c")
	bg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", bg)
	return b


static func set_bar(b: ProgressBar, value: int, max_value: int, hex: String = "") -> void:
	b.max_value = max_value
	b.value = maxi(value, 0)
	var ratio := float(maxi(value, 0)) / maxi(max_value, 1)
	var fill := StyleBoxFlat.new()
	if hex != "":
		fill.bg_color = Color(hex)
	else:
		fill.bg_color = Color("#4caf50") if ratio > 0.5 else (Color("#e0b030") if ratio > 0.25 else Color("#e04040"))
	fill.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fill)


## Button styling for the whole UI: visible against the dark background, clear hover/disabled states.
static func make_theme() -> Theme:
	var t := Theme.new()
	var states := {"normal": "#2e2e3e", "hover": "#3d3d55", "pressed": "#4a4a6a", "disabled": "#1f1f28", "focus": "#00000000"}
	for state_name in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(states[state_name])
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		if state_name == "hover":
			sb.border_color = Color(GameLog.YELLOW)
			sb.set_border_width_all(1)
		if state_name == "focus":
			sb.draw_center = false
		if state_name == "pressed":  # also the look of a selected toggle button
			sb.bg_color = Color("#3a3352")
			sb.border_color = Color(GameLog.YELLOW)
			sb.set_border_width_all(2)
		t.set_stylebox(state_name, "Button", sb)
	t.set_color("font_disabled_color", "Button", Color("#5a5a66"))
	t.set_color("font_pressed_color", "Button", Color(GameLog.YELLOW))
	# tooltips: dark panel, readable text
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color("#101018")
	tip.border_color = Color("#5a5a7a")
	tip.set_border_width_all(1)
	tip.set_corner_radius_all(4)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Color("#e8e8f0"))
	t.set_font_size("font_size", "TooltipLabel", 14)
	return t


## A tiny sheet of the player's stats, gear and perks (BBCode).
static func character_sheet(state: GameState) -> String:
	var p := state.player
	var lines := PackedStringArray()
	lines.append("[font_size=20][b]%s[/b][/font_size]" % GameLog.esc(p.name))
	lines.append("Level %d %s   [color=%s]%d/%d EXP[/color]" % [p.level, p.char_class, GameLog.CYAN, p.xp, Config.exp_needed(p.level)])
	lines.append("[color=%s]HP %d/%d[/color]   ATK %d   Armor %d   Crit %d%%" % [
			GameLog.GREEN if p.hp > p.max_hp / 2 else GameLog.RED, p.hp, p.max_hp, p.atk, p.armor, roundi(p.crit_chance * 100)])
	lines.append("[color=%s]Gold %d[/color]   Potions %d" % [GameLog.YELLOW, p.gold, p.potions])
	lines.append("")
	lines.append("[color=%s]Gear[/color]" % GameLog.GRAY)
	for item in [p.weapon, p.armor_piece]:
		if item:
			lines.append("[color=%s]%s[/color]" % [Config.RARITY_COLORS[item.rarity], item.describe()])
	if not p.weapon and not p.armor_piece:
		lines.append("none")
	lines.append("")
	lines.append("[color=%s]Skills[/color]" % GameLog.GRAY)
	lines.append("%s, %s%s" % [p.skill_name, p.ult_name, "" if p.ult_unlocked else " (Lv%d)" % Config.ULT_LEVEL])
	lines.append("")
	lines.append("[color=%s]Perks[/color]" % GameLog.GRAY)
	if p.perks.is_empty():
		lines.append("none yet")
	for id in p.perks:
		lines.append("%s%s - %s" % [Config.PERKS[id]["name"], " x%d" % p.perk(id) if p.perk(id) > 1 else "",
				Config.PERKS[id]["desc"]])
	return "\n".join(lines)


## Loot comparison text: the new item, what it replaces, and the stat differences.
static func compare_item(item: Item, current: Item) -> String:
	var lines := PackedStringArray()
	lines.append("[font_size=20][color=%s]%s[/color][/font_size]" % [Config.RARITY_COLORS[item.rarity], item.name])
	lines.append("[color=%s]%s %s[/color]" % [GameLog.GRAY, item.rarity, item.slot])
	lines.append("")
	for stat in ["atk", "armor", "hp"]:
		var new_v: int = item.get(stat)
		var old_v: int = current.get(stat) if current else 0
		if new_v == 0 and old_v == 0:
			continue
		var diff := new_v - old_v
		var diff_text := ""
		if diff > 0:
			diff_text = "[color=%s]  +%d[/color]" % [GameLog.GREEN, diff]
		elif diff < 0:
			diff_text = "[color=%s]  %d[/color]" % [GameLog.RED, diff]
		lines.append("%s %d%s" % [stat.to_upper(), new_v, diff_text])
	lines.append("")
	lines.append("Replaces: %s" % (current.describe() if current else "nothing"))
	return "\n".join(lines)
