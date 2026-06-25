class_name VisitSchedule
extends RefCounted
## Pure schedule logic for the Captain's visits: which weekday a 1-based day
## number falls on, whether it is a visit day (Tue/Fri/Sun), and whether the
## Captain should be present at a given (day, hour). No nodes, no state — unit
## tested. Reference via `const VisitSchedule := preload(...)`.

const WEEKDAY_NAMES := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const VISIT_WEEKDAYS := [1, 4, 6]      # Tue, Fri, Sun (Monday == 0)
const ARRIVE_HOUR := 6.0
const DEPART_HOUR := 19.0


## 0..6 for a 1-based day number; day 1 is Monday (0).
static func weekday(day: int) -> int:
	return (day - 1) % 7


static func weekday_name(day: int) -> String:
	return WEEKDAY_NAMES[weekday(day)]


static func is_visit_day(day: int) -> bool:
	return weekday(day) in VISIT_WEEKDAYS


## True when the Captain should be on the island for cycle day `day` at clock
## `hour` in [0,24): a visit day, between arrival (06:00) and departure (19:00).
static func present_at(day: int, hour: float) -> bool:
	return is_visit_day(day) and hour >= ARRIVE_HOUR and hour < DEPART_HOUR
