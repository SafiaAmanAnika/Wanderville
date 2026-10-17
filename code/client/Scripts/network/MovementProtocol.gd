extends RefCounted
class_name MovementProtocol
## The movement wire format, shared byte-for-byte by the server and every client.
##
## Two rules shape this format.
##
## **A client sends intent, never a position.** The input packet carries a
## direction and a sequence number; it has no field for coordinates at all, so
## "tell the server where I want to be" is not a message that can be expressed.
## That is why position spoofing is structurally impossible here rather than
## filtered by a range check.
##
## **The client never sets the clock.** There is no delta, no timestamp and no
## duration in the packet, so how far a player moves is decided entirely by the
## server's own fixed physics timestep. A client cannot claim to have held a key
## for a second and travel 300 units.
##
## Facing is sent explicitly rather than derived from the direction. It cannot be
## derived while idle: a stationary player still faces the direction they last
## walked, and a zero direction would otherwise snap every idle avatar to "front".
##
## Layouts are fixed width and little-endian, written through StreamPeerBuffer so
## both ends encode from one definition. Sizes are asserted at startup rather than
## assumed.

const PROTOCOL_VERSION := 1

# ── input: client -> server (unreliable_ordered, channel 1) ────────────────

## version(1) + type(1) + seq(4) + dir_x(1) + dir_y(1) + facing(1) + flags(1)
const INPUT_SIZE := 10
const INPUT_TYPE := 1

const FLAG_MOVING := 1
## Bit 2 is reserved and must arrive zero, so a future field cannot be smuggled in
## through a client that happens to set a spare bit.
const FLAG_RESERVED_MASK := 0xFC

## A direction component is quantised to a signed byte. 127 is used rather than
## 255 because that is the largest magnitude representable symmetrically.
const DIR_SCALE := 127.0
## Tolerance for "is this direction actually unit length". Quantisation error on a
## unit vector is well under this; a diagonal with both axes at 127 lands at 1.407
## and is rejected.
const DIR_TOLERANCE := 1.06

## Sequence numbers wrap, so "newer" is decided on a wrapped comparison.
const SEQ_MODULUS := 1 << 32

static func encode_input(seq: int, direction: Vector2, facing: int, moving: bool) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	var flags := FLAG_MOVING if moving else 0
	var normalised := direction
	if normalised.length() > 1.0:
		normalised = normalised.normalized()
	buffer.put_u8(PROTOCOL_VERSION)
	buffer.put_u8(INPUT_TYPE)
	buffer.put_u32(seq % SEQ_MODULUS)
	buffer.put_8(int(round(clampf(normalised.x, -1.0, 1.0) * DIR_SCALE)))
	buffer.put_8(int(round(clampf(normalised.y, -1.0, 1.0) * DIR_SCALE)))
	buffer.put_u8(clampi(facing, 0, 7))
	buffer.put_u8(flags)
	var out := buffer.data_array
	assert(out.size() == INPUT_SIZE, "input packet must be %d bytes, got %d" % [INPUT_SIZE, out.size()])
	return out


## Decode and validate. Returns {} when the packet is not acceptable, so a caller
## cannot accidentally use a half-validated value: it must check for emptiness.
static func decode_input(packet: PackedByteArray) -> Dictionary:
	if packet.size() != INPUT_SIZE:
		return {}
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	if buffer.get_u8() != PROTOCOL_VERSION:
		return {}
	if buffer.get_u8() != INPUT_TYPE:
		return {}
	var seq := buffer.get_u32()
	var raw_x := buffer.get_8()
	var raw_y := buffer.get_8()
	var facing := buffer.get_u8()
	var flags := buffer.get_u8()

	# A reserved bit set means the sender is running a different build, or is
	# probing. Refuse rather than guess what it meant.
	if flags & FLAG_RESERVED_MASK != 0:
		return {}
	if facing > 7:
		return {}

	var direction := Vector2(float(raw_x) / DIR_SCALE, float(raw_y) / DIR_SCALE)
	# Not finite, or longer than a unit vector: a client sending "move 400 units
	# north" as a direction, or NaN from a broken build.
	if not is_finite(direction.x) or not is_finite(direction.y):
		return {}
	if direction.length() > DIR_TOLERANCE:
		return {}
	# The moving flag must agree with the direction, so neither can be used to
	# smuggle state the other does not describe.
	if bool(flags & FLAG_MOVING) != (direction.length() > 0.05):
		return {}

	return {
		"seq": seq,
		"direction": direction,
		"facing": facing,
		"moving": bool(flags & FLAG_MOVING),
	}


# ── snapshot: server -> client (unreliable_ordered, channel 1) ─────────────

const SNAPSHOT_HEADER_SIZE := 8
const SNAPSHOT_ENTITY_SIZE := 20
const SNAPSHOT_TYPE := 2


static func encode_snapshot(tick: int, entities: Array) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(PROTOCOL_VERSION)
	buffer.put_u8(SNAPSHOT_TYPE)
	buffer.put_u32(tick % SEQ_MODULUS)
	buffer.put_u16(mini(entities.size(), 0xFFFF))
	for entity in entities:
		buffer.put_u32(int(entity["player_id"]) % SEQ_MODULUS)
		buffer.put_u32(int(entity["last_seq"]) % SEQ_MODULUS)
		buffer.put_float(float(entity["x"]))
		buffer.put_float(float(entity["y"]))
		buffer.put_8(int(entity.get("facing", 0)))
		buffer.put_u8(int(entity.get("flags", 0)))
		buffer.put_u16(0)  # reserved; keeps each entity record 4-byte aligned
	return buffer.data_array


static func decode_snapshot(packet: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	if packet.size() < SNAPSHOT_HEADER_SIZE:
		return {}
	if buffer.get_u8() != PROTOCOL_VERSION or buffer.get_u8() != SNAPSHOT_TYPE:
		return {}
	var tick := buffer.get_u32()
	var count := buffer.get_u16()
	# The unreliable channel can hand over a short read. A snapshot whose length
	# does not match its own entity count is discarded rather than decoded, so a
	# half entity is never mistaken for a real position.
	if packet.size() != SNAPSHOT_HEADER_SIZE + count * SNAPSHOT_ENTITY_SIZE:
		return {}
	var entities: Array = []
	for _i in count:
		var player_id := buffer.get_u32()
		var last_seq := buffer.get_u32()
		var x := buffer.get_float()
		var y := buffer.get_float()
		var facing := buffer.get_8()
		var flags := buffer.get_u8()
		buffer.get_u16()
		if not is_finite(x) or not is_finite(y):
			return {}
		if facing > 7:
			return {}
		entities.append({
			"player_id": player_id,
			"last_seq": last_seq,
			"x": x,
			"y": y,
			"facing": facing,
			"moving": bool(flags & FLAG_MOVING),
		})
	return {"tick": tick, "entities": entities}


# ── sequencing helpers ─────────────────────────────────────────────────────


## True when ``seq`` is newer than ``last`` on a wrapping counter.
##
## Unreliable-ordered delivery means a packet cannot arrive late within the
## channel, so anything not strictly newer is a replay or a stale duplicate and is
## dropped instead of being applied.
static func is_newer(seq: int, last: int) -> bool:
	return (seq - last) % SEQ_MODULUS > 0 and (seq - last) % SEQ_MODULUS < (SEQ_MODULUS / 2)


## Eight-way facing index from a direction, matching the row order the character
## sheets use: right, front_right, front, front_left, left, back_left, back,
## back_right.
static func facing_from_direction(direction: Vector2) -> int:
	if direction.length() < 0.05:
		return -1
	var index := int(round(rad_to_deg(direction.angle()) / 45.0)) % 8
	return index + 8 if index < 0 else index