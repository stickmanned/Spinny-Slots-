class_name NumberFormatter
extends RefCounted

## Presentation-only compact number formatting shared by every money UI.
## Examples: 950 -> 950, 1_250 -> 1.25K, 2_500_000 -> 2.5M.

const UNIT_SUFFIXES: Array[String] = [
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
]


static func compact(value: int) -> String:
	var negative := value < 0
	var scaled := absf(float(value))
	var unit_index := 0
	while scaled >= 1000.0 and unit_index < UNIT_SUFFIXES.size() - 1:
		scaled /= 1000.0
		unit_index += 1
	if unit_index == 0:
		return str(value)

	var decimals := 2
	if scaled >= 100.0:
		decimals = 0
	elif scaled >= 10.0:
		decimals = 1
	var formatted := "%.*f" % [decimals, scaled]
	if decimals > 0:
		formatted = formatted.trim_suffix("0").trim_suffix("0").trim_suffix(".")
	return ("-" if negative else "") + formatted + UNIT_SUFFIXES[unit_index]


static func currency(value: int) -> String:
	return "$%s" % compact(value)


static func reward(value: int, noun: String = "COINS") -> String:
	return "+%s %s" % [compact(maxi(value, 0)), noun]
