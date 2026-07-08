class_name Structure
extends RefCounted

## Layer 3 - mid/high level objects. Block movement through the hex, but can be
## "inhabited": a unit can garrison a building, take cover in/behind a tree or
## boulder, or crew a vehicle, up to `capacity`.

enum Kind { NONE, MATURE_TREE, BUILDING, CAMP, VEHICLE_LARGE, BOULDER, BRIDGE }
enum TreeSpecies { SPRUCE, OAK, WILLOW, PINE, BIRCH }
enum BuildingKind { HOUSE, CHURCH, BARN, BASE_PART, VILLAGE_HALL, WELL }
enum VehicleKind { CAR, TRUCK, HALFTRACK, ARMORED_CAR }

var kind: int = Kind.NONE
var subtype: int = -1      # meaning depends on kind: TreeSpecies / BuildingKind / VehicleKind
var blocks_movement: bool = true
var capacity: int = 0
var occupants: Array = []  # LivingEntity refs currently inside/using this structure

func _init(_kind: int, _subtype: int = -1, _capacity: int = 0) -> void:
	kind = _kind
	subtype = _subtype
	capacity = _capacity

func can_accept_occupant() -> bool:
	return occupants.size() < capacity

func add_occupant(entity) -> bool:
	if not can_accept_occupant():
		return false
	occupants.append(entity)
	entity.occupying = self
	return true

func remove_occupant(entity) -> void:
	occupants.erase(entity)
	if entity.occupying == self:
		entity.occupying = null

const COLORS = {
	Kind.MATURE_TREE: Color(0.10, 0.35, 0.12),
	Kind.BUILDING: Color(0.65, 0.30, 0.20),
	Kind.CAMP: Color(0.45, 0.40, 0.25),
	Kind.VEHICLE_LARGE: Color(0.30, 0.30, 0.32),
	Kind.BOULDER: Color(0.50, 0.50, 0.50),
	Kind.BRIDGE: Color(0.60, 0.60, 0.60),
}
