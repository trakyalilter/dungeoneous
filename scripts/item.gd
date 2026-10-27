class_name Item
extends RefCounted
## A weapon or armor piece.

var name: String
var slot: String  # "weapon" or "armor"
var atk: int
var armor: int
var hp: int
var rarity: String


func _init(p_name: String = "", p_slot: String = "weapon", p_atk: int = 0, p_armor: int = 0,
		p_hp: int = 0, p_rarity: String = "Common") -> void:
	name = p_name
	slot = p_slot
	atk = p_atk
	armor = p_armor
	hp = p_hp
	rarity = p_rarity


## Rough value used to compare two items.
func score() -> float:
	return atk * 2 + armor * 3 + hp * 0.5


func describe() -> String:
	var parts := PackedStringArray()
	if atk:
		parts.append("+%d ATK" % atk)
	if armor:
		parts.append("+%d ARMOR" % armor)
	if hp:
		parts.append("+%d HP" % hp)
	return "%s (%s)" % [name, ", ".join(parts)]


func to_dict() -> Dictionary:
	return {"name": name, "slot": slot, "atk": atk, "armor": armor, "hp": hp, "rarity": rarity}


static func from_dict(d: Dictionary) -> Item:
	return Item.new(d["name"], d["slot"], int(d["atk"]), int(d["armor"]), int(d["hp"]), d["rarity"])
