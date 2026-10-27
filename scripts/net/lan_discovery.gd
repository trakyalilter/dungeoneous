class_name LanDiscovery
extends Node
## Finds games on the local network without typing IPs.
## A host shouts a small UDP broadcast every second; players on the join screen listen and list what they hear.

signal hosts_changed(hosts: Array)  # [{"ip", "name", "players", "max"}]

const PORT := 8911
const TAG := "dungeoneous"
const FORGET_AFTER := 4.0  # seconds without a broadcast before a game drops off the list

var _udp: PacketPeerUDP
var _broadcasting := false
var _info := Callable()  # host: returns the Dictionary to broadcast
var _hosts := {}         # ip -> {info..., "seen": time}
var _clock := 0.0
var _next_shout := 0.0


## Host: announce this game every second. info() is called each time for fresh player counts.
func start_broadcast(info: Callable) -> void:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", PORT)
	_info = info
	_broadcasting = true


## Join screen: listen for hosts.
func start_listening() -> bool:
	stop()
	_udp = PacketPeerUDP.new()
	if _udp.bind(PORT) != OK:  # another copy of the game on this PC may already be listening
		_udp = null
		return false
	return true


func stop() -> void:
	if _udp:
		_udp.close()
	_udp = null
	_broadcasting = false
	_hosts.clear()


func _process(delta: float) -> void:
	_clock += delta
	if _udp == null:
		return
	if _broadcasting:
		if _clock >= _next_shout:
			_next_shout = _clock + 1.0
			var data: Dictionary = _info.call()
			data["tag"] = TAG
			_udp.put_packet(JSON.stringify(data).to_utf8_buffer())
		return
	var changed := false
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var d: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if d is Dictionary and d.get("tag", "") == TAG:
			changed = changed or not _hosts.has(ip) or _hosts[ip].get("players") != d.get("players")
			d["ip"] = ip
			d["seen"] = _clock
			_hosts[ip] = d
	for ip in _hosts.keys():
		if _clock - float(_hosts[ip]["seen"]) > FORGET_AFTER:
			_hosts.erase(ip)
			changed = true
	if changed:
		hosts_changed.emit(_hosts.values())
