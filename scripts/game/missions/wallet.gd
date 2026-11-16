class_name Wallet
extends Node
## Local cash, saved through Settings' desktop file and immediate web mirror.
## Use the Game/Wallet node (or the "wallet" group); no multiplayer authority.

signal changed(balance: int)

const MAX_BALANCE := 999999999
var balance: int = 0


func _ready() -> void:
	add_to_group("wallet")
	balance = clampi(int(Settings.get_value("cash", 0)), 0, MAX_BALANCE)
	if LaunchOptions.has("cash"):
		balance = clampi(LaunchOptions.get_string("cash").to_int(), 0, MAX_BALANCE)
		_save()


## Credits positive earnings. Reason is for callers' notices, never a save key.
func add(amount: int, _reason: String) -> void:
	if amount <= 0:
		return
	balance = mini(MAX_BALANCE, balance + mini(amount, MAX_BALANCE))
	_save()


## Rejects negative prices and overdrafts; zero-cost actions are allowed.
func spend(amount: int) -> bool:
	if amount < 0 or amount > balance:
		return false
	balance -= amount
	_save()
	return true


func _save() -> void:
	Settings.set_value("cash", balance)
	changed.emit(balance)


static func format_cash(amount: int) -> String:
	var digits := str(amount)
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return "$" + result
