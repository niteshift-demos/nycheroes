class_name HeroUpgrades
extends RefCounted
## Saved local purchases. Peers receive the resulting movement and Combat hits,
## never read this player's Settings to simulate a remote hero.

const NAMES := {
	"health": "Max health", "punch": "Punch power", "speed": "Super speed",
	"flight": "Flight speed", "slam": "Slam radius", "armor": "Car armor",
}
const PRICES: Array[int] = [2000, 8000, 25000]


static func tier(id: String) -> int:
	return clampi(int(Settings.get_value("upgrade_" + id, 0)), 0, 3) if NAMES.has(id) else 0


static func multiplier(id: String) -> float:
	return 1.0 + 0.25 * tier(id)


static func price(id: String) -> int:
	return PRICES[tier(id)] if NAMES.has(id) and tier(id) < 3 else -1


static func purchase(id: String, wallet: Wallet) -> bool:
	var cost := price(id)
	if cost < 0 or not wallet.spend(cost):
		return false
	Settings.set_value("upgrade_" + id, tier(id) + 1)
	return true


static func reset() -> void:
	for id: String in NAMES:
		Settings.set_value("upgrade_" + id, 0)
