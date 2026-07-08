class_name HexUtils
extends RefCounted

## Flat-top hex grid utilities using axial coordinates (q, r).
## Each hex's neighbor directions are orientation-independent in axial space.

const DIRECTIONS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

## For flat-top hexes, neighbor direction `d` sits on the hex edge between
## corners[EDGE_FOR_DIRECTION[d]] and corners[EDGE_FOR_DIRECTION[d] + 1].
## Used to draw a wall segment on the correct side of a hex.
const EDGE_FOR_DIRECTION = [0, 5, 4, 3, 2, 1]

static func neighbors(coord: Vector2i) -> Array:
	var result = []
	for d in DIRECTIONS:
		result.append(coord + d)
	return result

static func distance(a: Vector2i, b: Vector2i) -> int:
	var ac = _axial_to_cube(a)
	var bc = _axial_to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2)

static func _axial_to_cube(coord: Vector2i) -> Vector3i:
	var x = coord.x
	var z = coord.y
	var y = -x - z
	return Vector3i(x, y, z)

## Pixel position of a hex center, for flat-top orientation.
static func axial_to_pixel(coord: Vector2i, size: float) -> Vector2:
	var x = size * (3.0 / 2.0 * coord.x)
	var y = size * (sqrt(3.0) * (coord.y + coord.x / 2.0))
	return Vector2(x, y)

## The 6 corner points of a flat-top hex centered at `center`.
static func hex_corners(center: Vector2, size: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		var angle_rad = deg_to_rad(60 * i)
		points.append(center + Vector2(size * cos(angle_rad), size * sin(angle_rad)))
	return points

## Inverse of axial_to_pixel for flat-top hexes: given a point in the same
## space (e.g. a mouse click converted to this node's local coordinates),
## returns the axial coordinate of the hex that contains it.
static func pixel_to_axial(point: Vector2, size: float) -> Vector2i:
	var q = (2.0 / 3.0 * point.x) / size
	var r = (-1.0 / 3.0 * point.x + sqrt(3.0) / 3.0 * point.y) / size
	return _cube_round(q, r)

static func _cube_round(q: float, r: float) -> Vector2i:
	var x = q
	var z = r
	var y = -x - z
	var rx = round(x)
	var ry = round(y)
	var rz = round(z)
	var x_diff = abs(rx - x)
	var y_diff = abs(ry - y)
	var z_diff = abs(rz - z)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))

## Converts a rectangular col/row grid index into axial coordinates
## so a rectangular region of columns/rows produces a roughly rectangular
## hex map (offset "odd-q" style for flat-top hexes).
static func offset_to_axial(col: int, row: int) -> Vector2i:
	var q = col
	var r = row - int(floor(col / 2.0))
	return Vector2i(q, r)
