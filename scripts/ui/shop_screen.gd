class_name ShopScreen
extends Control
## Shop node: potions and upgrades, two pieces of gear, two consumables and a relic.

signal changed  # something was bought (main saves + checks achievements)
signal leave

var sfx: Sfx
var _state: GameState
var _stock := {}
var _info: RichTextLabel
var _list: VBoxContainer


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := UiKit.panel(UiKit.PANEL, 18)
	box.custom_minimum_size = Vector2(660, 0)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	v.add_child(UiKit.heading("Wandering Merchant", 30))
	v.add_child(UiKit.label("\"Fine wares for the brave... and the solvent.\"", 14, GameLog.GRAY))
	_info = UiKit.rich(15)
	v.add_child(_info)
	v.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	v.add_child(_list)
	v.add_child(HSeparator.new())
	v.add_child(UiKit.button("Leave the shop", func() -> void: leave.emit()))


func open(state: GameState, stock: Dictionary) -> void:
	_state = state
	_stock = stock
	_refresh()


func _row(icon: String, text: String, tip: String, price: int, callback: Callable, color: String = "") -> void:
	var b := UiKit.button("         %s - %dg" % [text, price], callback)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 42)
	b.tooltip_text = tip
	b.disabled = _state.player.gold < price
	if color != "":
		b.add_theme_color_override("font_color", Color(color))
	var i := GameIcon.make(icon, 30)
	i.position = Vector2(8, 6)
	b.add_child(i)
	_list.add_child(b)


func _section(title: String) -> void:
	_list.add_child(UiKit.label(title, 16, GameLog.CYAN))


func _refresh() -> void:
	var p := _state.player
	_info.text = "[color=%s]Gold: %d[/color]    HP %d/%d    ATK %d    Armor %d    Potions %d    Items %d/%d" % [
			GameLog.YELLOW, p.gold, p.hp, p.max_hp, p.atk, p.armor, p.potions, p.items.size(), Config.MAX_ITEMS]
	for c in _list.get_children():
		c.queue_free()

	_section("Supplies")
	var icons := {"potion": "potion", "atk": "whetstone", "hp": "armor"}
	for key in Config.SHOP:
		_row(icons[key], Config.SHOP[key]["name"], "", p.shop_price(key), _buy_upgrade.bind(key))

	_section("Equipment")
	for i in _stock.gear.size():
		var item: Item = _stock.gear[i]
		var current := p.equipped(item.slot)
		var better := current == null or item.score() > current.score()
		_row("atk" if item.slot == "weapon" else "armor", "%s  %s" % [item.describe(), "(upgrade)" if better else "(worse than yours)"],
				"Replaces: %s" % (current.describe() if current else "nothing"), Progression.item_price(item),
				_buy_gear.bind(i), Config.RARITY_COLORS[item.rarity])

	_section("Items")
	for i in _stock.consumables.size():
		var id: String = _stock.consumables[i]
		var info: Dictionary = Config.CONSUMABLES[id]
		_row(id, "%s: %s" % [info["name"], info["desc"]], "", int(info["price"]), _buy_consumable.bind(i))
		if p.items.size() >= Config.MAX_ITEMS:
			_list.get_child(_list.get_child_count() - 1).disabled = true

	if _stock.relic != "":
		_section("Relic")
		var info := Progression.relic_info(_stock.relic)
		_row(_stock.relic, "%s: %s" % [info["name"], info["desc"]], "", Progression.relic_price(_state),
				_buy_relic, GameLog.MAGENTA)


func _pay(price: int) -> bool:
	if _state.player.gold < price:
		return false
	_state.player.gold -= price
	return true


func _done(sound: String) -> void:
	sfx.play(sound)
	changed.emit()
	_refresh()


func _buy_upgrade(key: String) -> void:
	if Progression.buy(_state.player, key):
		_done("coin")


func _buy_gear(i: int) -> void:
	var item: Item = _stock.gear[i]
	if _pay(Progression.item_price(item)):
		_state.player.equip(item)
		_stock.gear.remove_at(i)
		_done("defend")


func _buy_consumable(i: int) -> void:
	var id: String = _stock.consumables[i]
	if _state.player.items.size() < Config.MAX_ITEMS and _pay(int(Config.CONSUMABLES[id]["price"])):
		_state.player.add_item(id)
		_stock.consumables.remove_at(i)
		_done("coin")


func _buy_relic() -> void:
	if _pay(Progression.relic_price(_state)):
		_state.player.add_relic(_stock.relic)
		_stock.relic = ""
		_done("levelup")
