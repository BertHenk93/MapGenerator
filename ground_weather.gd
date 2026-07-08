class_name Village
extends RefCounted

## A multi-hex settlement. Individual villagers aren't simulated as separate
## entities (that would be hundreds of objects for no gameplay benefit yet) -
## population is tracked as an aggregate count here, split by demographic.

var center: Vector2i
var hexes: Array = []   # Vector2i coords belonging to this village's footprint

var men: int = 0
var women: int = 0
var children: int = 0

func _init(_center: Vector2i) -> void:
	center = _center

func total_population() -> int:
	return men + women + children
