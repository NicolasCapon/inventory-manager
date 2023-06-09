local lib = {}

lib.PROTOCOLS = {}
lib.PROTOCOLS.MAIN = "INVENTORY"
lib.PROTOCOLS.NOTIF = {}
lib.PROTOCOLS.NOTIF.MAIN = "NOTIFICATION"
lib.PROTOCOLS.NOTIF.UI = "UPDATE_UI"
lib.PROTOCOLS.NOTIF.START = "SERVER_START"

lib.RECIPES_FILE = "recipes.txt"
lib.LOG_FILE = "log.txt"
lib.JOBS_FILE = "jobs.txt"
lib.ACCEPTED_TASKS = {"listenInventory", "keepMinItemInSlot"}

lib.ALLOWED_INVENTORIES = {}
lib.ALLOWED_INVENTORIES["metalbarrels:gold_tile"] = true

lib.SERVER_ID = 6
lib.TIMEOUT = 1

lib.GET_SLOT = 1
lib.CRAFTING_SLOT = 4

return lib
