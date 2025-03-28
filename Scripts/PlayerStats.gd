extends Node

@onready var global_state = get_node("/root/GlobalState")  # Sync player stats with GlobalState
@onready var inventory_panel = get_tree().get_first_node_in_group("inventory_panel")  # ✅ Uses group instead of fixed path
@onready var armor_panel = get_node("/root/TheCrossroads/MainUI/ArmorPanel")  # Reference to ArmorPanel
@onready var inventory = GlobalState.inventory  # ✅ Sync inventory reference
@onready var player = get_tree().get_first_node_in_group("player")
@onready var stats_panel = get_node("/root/TheCrossroads/MainUI/StatsPanel")  # Update path to StatsPanel

signal equipment_changed(slot_type, item_name)  # ✅ UI updates when equipment changes
@export var equipped_items := {
	"weapon": null,
	"helm": null,
	"chest": null,
	"legs": null,
	"shield": null,
	"pickaxe": null
}

# Player stats variables
var player_xp = 0          # Experience points
var health = 100           # Player health
var total_level = 1        # Total level (formerly player_level)

# Skill progression variables (Mining, Herbalism, Combat)
var mining_xp = 0
var herbalism_xp = 0
var combat_xp = 0

# Maximum levels for each skill
var max_skill_level = 20

# Skill levels (initial values; these will update based on XP)
var mining_level = 1
var herbalism_level = 1
var combat_level = 1

# Autosave Timer
var autosave_timer : Timer

# Equipment slots
var equipped_weapon = null  # Stores the equipped weapon (if any)
var equipped_armor = null   # Stores the equipped armor (if any)


# Called when the game starts
func _ready():
	print("🔄 [PlayerStats] Syncing with GlobalState on game start...")

	inventory = GlobalState.inventory
	equipped_items = GlobalState.equipped_items
	update_ui()
	
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	# Fallback defaults if inventory or equipped items not found
	if typeof(inventory) != TYPE_ARRAY:
		print("⚠️ [PlayerStats] Converting old inventory format...")
		inventory = []
		GlobalState.inventory = inventory

	if typeof(equipped_items) != TYPE_DICTIONARY:
		print("⚠️ [PlayerStats] Using default equipped items...")
		equipped_items = {
			"weapon": null,
			"helm": null,
			"chest": null,
			"legs": null,
			"shield": null,
			"pickaxe": null
		}
		GlobalState.equipped_items = equipped_items

	# Load stats
	load_player_stats()
	update_skill_levels()

	# Setup autosave
	autosave_timer = Timer.new()
	add_child(autosave_timer)
	autosave_timer.wait_time = 60
	autosave_timer.one_shot = false
	autosave_timer.connect("timeout", Callable(self, "_on_autosave_timeout"))
	autosave_timer.start()

	print("✅ [PlayerStats] Ready with inventory size:", inventory.size())

# Function to load player stats (from GlobalState or file)
func load_player_stats():
	player_xp = GlobalState.player_xp
	total_level = GlobalState.total_level
	health = GlobalState.health
	mining_xp = GlobalState.mining_xp
	herbalism_xp = GlobalState.herbalism_xp
	combat_xp = GlobalState.combat_xp

# Function to gain XP for a specific skill (called from other scripts)
func gain_xp(skill: String, amount: int):
	# Before adding the XP, make sure to load the current skill levels first
	SkillStats.add_xp(skill, amount)  # Directly call SkillStats to update XP

	# After XP gain, update skill levels and sync data
	update_skill_levels()
	sync_player_stats()

	# Trigger UI Update (this is where StatsPanel needs to be updated)
	if stats_panel:
		stats_panel.emit_signal("xp_updated")  # Emit the xp_updated signal for UI update

	# Save updated data
	GlobalState.save_all_data()  # Immediately save the updated XP and level

# Function to update skill levels based on current XP values
func update_skill_levels():
	# Get current skill levels from SkillStats
	total_level = get_total_level()  # Get total level based on current skill levels

# Function to calculate the total level (sum of all skill levels, capped at 70)
func get_total_level() -> int:
	# Total level is the sum of the skill levels from SkillStats
	var total_skill_level = SkillStats.get_skill_level("mining") + SkillStats.get_skill_level("herbalism") + SkillStats.get_skill_level("combat")
	return min(total_skill_level, 70)  # Cap total level at 70

# Sync player stats with GlobalState (for persistence)
func sync_player_stats():
	# Sync data to GlobalState
	GlobalState.player_xp = player_xp
	GlobalState.total_level = total_level
	GlobalState.health = health
	# Skill XP is now stored in SkillStats, no need to duplicate
	GlobalState.mining_xp = SkillStats.mining_xp
	GlobalState.herbalism_xp = SkillStats.herbalism_xp
	GlobalState.combat_xp = SkillStats.combat_xp
	
	# Sync inventory and equipped items
	GlobalState.inventory = inventory
	GlobalState.equipped_items = equipped_items 

	# Save data after updating GlobalState
	GlobalState.save_all_data()  # Save the state to disk

func sync_with_global_state():
	global_state.equipped_items = equipped_items
	global_state.inventory = inventory
	global_state.save_all_data()

	print("✅ Synced PlayerStats with GlobalState")

# Declare the signal in PlayerStats.gd
signal inventory_updated
func add_item_to_inventory(item: ItemResource, amount: int):
	if item == null:
		print("❌ Tried to add null item to inventory.")
		return

	var item_path = item.resource_path
	if item_path == "":
		print("❌ Item has no valid resource_path. Make sure it's saved as a .tres file.")
		return

	# Check if the item already exists in the inventory
	for entry in inventory:
		if entry.path == item_path:
			entry.quantity += amount  # Add the drop amount to the existing quantity
			print("🔁 Increased quantity of:", item.item_name, "to", entry.quantity)
			emit_signal("inventory_updated")
			GlobalState.inventory = inventory
			GlobalState.save_all_data()
			return

	# If it's a new item, add it with the specified amount
	inventory.append({ "path": item_path, "quantity": amount })
	print("🆕 Added new item to inventory:", item.item_name)

	emit_signal("inventory_updated")
	GlobalState.inventory = inventory
	GlobalState.save_all_data()

# ✅ Get item type from GlobalState
func get_item_type(item_name: String) -> String:
	if GlobalState.item_types.has(item_name):
		return GlobalState.item_types[item_name]
	return "unknown"  # Default if item type is missing

func sync_inventory_with_player():
	GlobalState.inventory = inventory
	GlobalState.equipped_items = equipped_items
	GlobalState.save_all_data()

	if inventory_panel:
		inventory_panel.update_inventory_ui()  # ✅ correct call now

	if armor_panel:
		armor_panel.load_equipped_items()
	else:
		print("❌ ERROR: ArmorPanel not found!")

	print("🔄 Inventory and Equipped Items synced and UI updated.")


func get_equipped_item(item_type: String) -> String:
	var slot = get_slot_by_type(item_type)
	if equipped_items.has(slot) and equipped_items[slot] != null and equipped_items[slot] != "":
		return equipped_items[slot]
	return ""


# Function for autosave (called every interval)
func _on_autosave_timeout():
	GlobalState.save_all_data()  # Save data

# Optionally, trigger manual save when a key is pressed (e.g., F5 or Ctrl+S)
func _process(delta):
	if Input.is_action_pressed("save_game"):  # Make sure to add this action in Input Map
		GlobalState.save_all_data()  # Save data manually
		print("Game saved manually.")

func equip_item(slot_type: String, item_path: String):
	print("✅ [PlayerStats] Attempting to equip:", item_path, "to", slot_type)

	# ✅ Check if item is already equipped in that slot
	if equipped_items.get(slot_type) != null and equipped_items[slot_type] != "":
		print("❌ [PlayerStats] ERROR: Slot", slot_type, "already occupied by", equipped_items[slot_type])
		return

	# ✅ Find the item in the array-based inventory
	for i in inventory.size():
		if inventory[i].path == item_path:
			# ✅ Reduce quantity or remove if it's the last one
			inventory[i].quantity -= 1
			if inventory[i].quantity <= 0:
				inventory.remove_at(i)
			break
		else:
			print("❌ [PlayerStats] ERROR: Item", item_path, "not found in inventory!")
			return

	# ✅ Equip the item
	equipped_items[slot_type] = item_path
	sync_with_global_state()

	print("✅ [PlayerStats] Successfully equipped:", item_path, "to", slot_type)

	update_ui()
	update_pickaxe_visibility()

func unequip_item(slot_type: String):
	print("🛠 [PlayerStats] Called unequip_item() for:", slot_type)

	if not equipped_items.has(slot_type):
		print("❌ [PlayerStats] ERROR: Slot does not exist in equipped_items:", slot_type)
		return

	var item_path = equipped_items[slot_type]
	if item_path == null or item_path == "":
		print("⚠️ [PlayerStats] WARNING: No item to unequip in slot", slot_type)
		return

	print("❎ [PlayerStats] Unequipping:", item_path, "from", slot_type)

	# ✅ Add item back to inventory (or increase quantity if it exists)
	var found = false
	for entry in inventory:
		if entry.path == item_path:
			entry.quantity += 1
			found = true
			break

	if not found:
		inventory.append({ "path": item_path, "quantity": 1 })

	# ✅ Clear equipped slot
	equipped_items[slot_type] = ""

	# ✅ Save all data to GlobalState
	GlobalState.equipped_items = equipped_items
	GlobalState.inventory = inventory
	GlobalState.save_all_data()

	print("✅ [PlayerStats] Successfully unequipped", item_path)
	update_ui()
	player.update_pickaxe_visibility()


# Function to return the correct slot type for an item
func get_slot_by_type(item_type: String) -> String:
	match item_type:
		"weapon", "pickaxe":  # Pickaxes are also considered weapons
			return "weapon"
		"helm":
			return "helm"
		"chest":
			return "chest"
		"legs":
			return "legs"
		"shield":
			return "shield"
	return ""

# Function to refresh the inventory UI
func update_ui():
	print("🔄 [PlayerStats] Updating UI after equip/unequip...")

	# ✅ Update Armor Panel
	var armor_panel = get_tree().get_first_node_in_group("armor_ui")
	if armor_panel:
		print("✅ [PlayerStats] Found Armor Panel. Reloading UI...")
		armor_panel.load_equipped_items()
	else:
		print("❌ [PlayerStats] ERROR: Armor Panel not found!")

	# ✅ Update Inventory Panel
	var inventory_panel = get_tree().get_first_node_in_group("inventory_ui")
	if inventory_panel:
		print("✅ [PlayerStats] Found Inventory Panel. Updating UI...")
		inventory_panel.call_deferred("update_inventory_ui")  # ✅ Correct Call
	else:
		print("❌ [PlayerStats] ERROR: Inventory Panel not found!")


func update_pickaxe_visibility():
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.update_pickaxe_visibility()
	else:
		print("❌ [PlayerStats] ERROR: Player not found when updating pickaxe visibility!")
