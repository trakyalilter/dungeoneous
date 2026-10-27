class_name RunMap
extends RefCounted
## One floor's branching map. rows[r] is an array of nodes:
##   {"type": "fight"|"elite"|"event"|"shop"|"rest"|"treasure"|"boss", "x": 0..1, "links": [indices in row r+1], "done": bool}
## The player starts below row 0 and climbs one row at a time along the links.

var rows: Array = []
var pos_row := -1  # -1 = not entered yet
var pos_idx := -1


static func generate() -> RunMap:
	var m := RunMap.new()
	for r in Config.MAP_ROWS:
		var width := randi_range(2, 4)
		var row: Array = []
		for c in width:
			row.append({"type": _roll_type(r), "x": (c + 0.5) / width, "links": [], "done": false})
		m.rows.append(row)
	m.rows.append([{"type": "boss", "x": 0.5, "links": [], "done": false}])

	# link each node to the closest node(s) above it, then make sure every node above is reachable
	for r in Config.MAP_ROWS:
		var row: Array = m.rows[r]
		var next: Array = m.rows[r + 1]
		for node in row:
			var nearest := _nearest(next, node.x)
			node.links.append(nearest)
			if next.size() > 1 and randf() < 0.45:
				var side := nearest + (1 if randf() < 0.5 else -1)
				if side >= 0 and side < next.size() and absf(next[side].x - node.x) < 0.45:
					node.links.append(side)
		for j in next.size():
			var has_parent := false
			for node in row:
				if j in node.links:
					has_parent = true
			if not has_parent:
				row[_nearest(row, next[j].x)].links.append(j)
		for node in row:
			node.links.sort()
	return m


static func _roll_type(row: int) -> String:
	if row == 0:
		return "fight"
	if row == Config.MAP_ROWS - 1:
		return "rest"
	var total := 0
	for k in Config.NODE_WEIGHTS:
		total += Config.NODE_WEIGHTS[k]
	while true:
		var pick := randi_range(1, total)
		for k in Config.NODE_WEIGHTS:
			pick -= Config.NODE_WEIGHTS[k]
			if pick <= 0:
				# no elites in the first rows, no rest right before the guaranteed rest row
				if (k == "elite" and row < 3) or (k == "rest" and row == Config.MAP_ROWS - 2):
					break
				return k
	return "fight"


static func _nearest(row: Array, x: float) -> int:
	var best := 0
	for j in row.size():
		if absf(row[j].x - x) < absf(row[best].x - x):
			best = j
	return best


## Nodes the player can move to now, as [row, idx] pairs.
func reachable() -> Array:
	var out := []
	if pos_row == -1:
		for j in rows[0].size():
			out.append([0, j])
	elif pos_row < rows.size() - 1:
		for j in rows[pos_row][pos_idx].links:
			out.append([pos_row + 1, j])
	return out


func node(r: int, i: int) -> Dictionary:
	return rows[r][i]


func move_to(r: int, i: int) -> Dictionary:
	pos_row = r
	pos_idx = i
	rows[r][i].done = true
	return rows[r][i]


func to_dict() -> Dictionary:
	return {"rows": rows, "pos_row": pos_row, "pos_idx": pos_idx}


static func from_dict(d: Dictionary) -> RunMap:
	var m := RunMap.new()
	for row in d["rows"]:
		var new_row: Array = []
		for n in row:
			var links: Array = []
			for l in n["links"]:
				links.append(int(l))
			new_row.append({"type": n["type"], "x": float(n["x"]), "links": links, "done": bool(n["done"])})
		m.rows.append(new_row)
	m.pos_row = int(d["pos_row"])
	m.pos_idx = int(d["pos_idx"])
	return m
