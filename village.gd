class_name LivingEntity
extends RefCounted

## Layer 4 - things that move around and can inhabit a Structure (layer 3):
## humans, animals, motorcycles. Large vehicles are layer 3 (they block and can
## be crewed); these are the mobile, "small" occupants.

enum Kind { HUMAN, ANIMAL, MOTORCYCLE }
enum AnimalSpecies { DOG, HORSE, COW, DEER }

var kind: int
var subtype: int = -1
var occupying: Structure = null   # non-null if currently inside/using a Structure

func _init(_kind: int, _subtype: int = -1) -> void:
	kind = _kind
	subtype = _subtype

const COLORS = {
	Kind.HUMAN: Color(0.95, 0.85, 0.60),
	Kind.ANIMAL: Color(0.75, 0.55, 0.35),
	Kind.MOTORCYCLE: Color(0.15, 0.15, 0.15),
}
