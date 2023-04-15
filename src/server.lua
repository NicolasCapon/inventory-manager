local modem = peripheral.find("modem") or error("No modem attached", 0)
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
peripheral.find("modem", rednet.open)

RECIPES_FILE = "recipes.txt"
LOG_FILE = "server.log"
ALLOWED_INVENTORIES = {}
ALLOWED_INVENTORIES["minecraft:chest"] = true
ALLOWED_INVENTORIES["metalbarrels:gold_tile"] = true
variableLimit = false

recipes = {}
inventory = {}
free = {}

function log(message)
    local file = fs.open(LOG_FILE, "a")
    file.write(textutils.serialize(message, { compact = true }) .. "\n")
    file.close()
end

function scanRemoteInventory(remote, variableLimit)
    -- scan remote inventory and populate global inventory
    local chest = peripheral.wrap(remote)
    for cslot=1,chest.size() do
        local item = chest.getItemDetail(cslot)
        if item == nil then
            -- no item, add this slot to free slots
            local limit = 64
            if variableLimit then
                limit = chest.getItemLimit(cslot)
            end
            table.insert(free, {chest=remote, slot={index=cslot, limit=limit}})
        else
            local slots = inventory[item.name]
            if slots == nil then
                -- new item, add it and its associated slot
                inventory[item.name] = {{chest=remote, slot={index=cslot, limit=item.maxCount, count=item.count}}}
            else
                -- item already listed, add this slot only
                table.insert(inventory[item.name], {chest=remote, slot={index=cslot, limit=item.maxCount, count=item.count}})
            end
        end
    end
end 

function scanAll()
    monitor.clear()
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.red)
    -- Populate inventory
    -- TODO make progress bar
    local remotes = modem.getNamesRemote()
    local toScan = {}
    for i, remote in pairs(remotes) do
        if ALLOWED_INVENTORIES[modem.getTypeRemote(remote)] then
            table.insert(toScan, remote)
        end
    end
    for i, inv in ipairs(toScan) do
        scanRemoteInventory(inv)
        monitor.setCursorPos(1, 1)
        monitor.write("[" .. tostring(i) .. "/" .. tostring(#toScan) .. "] Loading")
        monitor.setCursorPos(1, 2)
        monitor.write("inventory...")
        print("Scanning " .. inv .. "...")
    end
    monitor.setBackgroundColor(colors.black)
end

function sendResponse(client, response)
    -- client, {ok, reponse, error}
    local protocol = "INVENTORY"
    rednet.send(client, response, protocol)
end

function get(name, count, turtle, turtleSlot)
    -- TODO optimize by breaking the loop and call clearInventory only at the end
    local item = inventory[name]
    if item == nil then
        local error = name .. " not found"
        return {ok=false, response={name=name, count=count}, error=error}
    else
        for i, location in ipairs(item) do
            local chest = location.chest
            local inventory_count = location.slot.count
            local left = inventory_count - count
            if left > 0 then
                -- Enough items in this slot
                local num = modem.callRemote(chest, "pushItems", turtle, location.slot.index, count, turtleSlot)
                -- update inventory
                inventory[name][i]["slot"]["count"] = inventory_count - tonumber(num)
                return {ok=true, response={name=name, count=count}, error=""}
            elseif left == 0 then
                -- just enough item
                local num = modem.callRemote(chest, "pushItems", turtle, location.slot.index, count, turtleSlot)
                -- add free slot and remove inventory slot
                table.insert(free, {chest=chest, slot={index=location.slot.index, limit=location.slot.limit}})
                inventory[name][i].status = "TO_REMOVE"
                inventory[name][i]["slot"]["count"] = left
                inventory[name] = clearInventory(inventory[name])
                return {ok=true, response={name=name, count=count}, error=""}
            else
                -- not enough items get the maximum for this slot and continue the loop
                local num = modem.callRemote(chest, "pushItems", turtle, location.slot.index, inventory_count, turtleSlot)
                -- add free slot, remove inventory slot and update count
                table.insert(free, {chest=chest, slot={index=location.slot.index, limit=location.slot.limit}})
                count = count - tonumber(num)
                inventory[name][i].status = "TO_REMOVE"
                inventory[name] = clearInventory(inventory[name])
            end
        end
        -- if not enough items, clear what was still extracted
        if count > 0 then
            local error = "Not enough " .. name .. ", missing " .. count
            return {ok=false, response={name=name, count=count}, error=error}
        end
    end
end

function loadRecipes()
    local keyset = {}
    local n = 0
    if not fs.exists(RECIPES_FILE) then return {} end
    local lines = {}
    for line in io.lines(RECIPES_FILE) do
        local recipe = textutils.unserialize(line)
        recipes[recipe.name] = recipe 
        n = n + 1
    end
    print( n .. " recipes loaded from ".. RECIPES_FILE)
end

function put_in_free_slot(name, count, maxCount, turtle, turtleSlot)
    -- TODO optimize by breaking the loop and call clearInventory only at the end
    maxCount = maxCount or 64
    for i, fslot in ipairs(free) do
        local chest = fslot.chest
        local limit = fslot.slot.limit
        if limit > maxCount then
            -- If this type of item cannot support the max of this slot, use
            -- item limit instead
            limit = maxCount
        end
        local left = limit - count
        if left > -1 then
            -- put does not exceed item limit for this free slot
            local num = modem.callRemote(fslot.chest, "pullItems", turtle, turtleSlot, count, fslot.slot.index)
            -- add item in inventory
            table.insert(inventory[name], {chest=chest, slot={index=fslot.slot.index, limit=limit, count=tonumber(num)}})
            free[i].status = "TO_REMOVE"
            -- update free
            free = clearInventory(free)
            if free == nil then free = {} end
            return {ok=true, response={name=name, count=count}, error=""}
        else
            -- put exceed slot limit, put max and continue loop
            local num = modem.callRemote(chest, "pullItems", turtle, turtleSlot, limit, fslot.slot.index)
            -- update inventory
            table.insert(inventory[name], {chest=chest, slot={index=fslot.slot.index, limit=limit, count=tonumber(num)}})
            -- remove free slot
            print("free", num)
            count = count - num
            free[i].status = "TO_REMOVE"
            free = clearInventory(free)
        end
    end
    print("No free space")
    if free == nil then free = {} end
    return {ok=false, response={name=name, count=count}, error="Not enough free space"}
end

function put(name, count, maxCount, turtle, turtleSlot)
    local item = inventory[name] 
    if item == nil then
        -- if item not in inventory, fill free slots
        inventory[name] = {}
        return put_in_free_slot(name, count, maxCount, turtle, turtleSlot)
    else
        -- try to fill already used slots
        for i, islot in ipairs(item) do
            local available = islot.slot.limit - islot.slot.count
            if available > 0 then
                local left = available - count
                -- free space available in this slot
                if left > -1 then
                    -- free space for this slot is enough
                    local num = modem.callRemote(islot.chest, "pullItems", turtle, turtleSlot, count, islot.slot.index)
                    inventory[name][i]["slot"]["count"] = islot.slot.count + tonumber(num)
                    return {ok=true, response={name=name, count=count}, error=""}
                else
                    -- not enough space, put max and continue
                    local num = modem.callRemote(islot.chest, "pullItems", turtle, turtleSlot, available, islot.slot.index)
                    num = tonumber(num)
                    print("put 2", num)
                    inventory[name][i]["slot"]["count"] = islot.slot.count + num
                    count = count - num
                end
            end
        end
        if count > 0 then
            -- use free space
            return put_in_free_slot(name, count, maxCount, turtle, turtleSlot)
        end
    end
end

function clearInventory(input)
    local n=#input
    for i=1,n do
        if input[i].status == "TO_REMOVE" then
            input[i]=nil
        end
    end

    local j=0
    for i=1,n do
        if input[i]~=nil then
            j=j+1
            input[j]=input[i]
        end
    end
    for i=j+1,n do
        input[i]=nil
    end
    if not next(input) then input = nil end
    return input
end

function removeExcessiveItems(recipe)
    local min = 64
    for _, item in ipairs(recipe.items) do
        if item.count < min then
            min = item.count
        end
        item.count = 1
    end
    recipe.count = recipe.count / min
    return recipe
end

function saveRecipe(recipe)
    if recipes[recipe.name] ~= nil then
        -- recipe already exist print error
        return {ok=false, response=recipe, error="Recipe already exists"}
    end
    -- Assume each recipe cannot contains more than one item per slot
    recipe = removeExcessiveItems(recipe)
    local file = fs.open(RECIPES_FILE, "a")
    file.write(textutils.serialize(recipe, { compact = true }) .. "\n")
    file.close()
    recipes[recipe.name] = recipe
    return {ok=true, response=recipe, error=""}
end

function createRecipe(name, turtleID)
    -- create recipe from turtle inventory and serialize it to file
    local turtle = peripheral.wrap(turtleID)
    local recipe = {name=name, items={}}
    for i=1,16 do
        local item = turtle.getItemDetail(i)
        if item ~= nil then
            table.insert(recipe["items"], {slot=i, name=item.name, count=item.count})
        end
    end
    saveRecipe(recipe)
end

function countItem(item)
    -- count total of an item in inventory
    local total = 0
    if inventory[item] == nil then return 0 end
    for _, location in ipairs(inventory[item]) do
        total = total + location.slot.count
    end
    return total
end

function addDependency(dependencies, recipe, count, lvl)
    -- add recipe lvl of dependencies and item count
    if dependencies["maxlvl"] < lvl then
        -- lvl up max lvl of dependencies if necessary
        dependencies["maxlvl"] = lvl
    end
    if dependencies[recipe.name] == nil then
        dependencies[recipe.name] = {lvl=lvl, count=count} 
    else
        if dependencies[recipe.name].lvl < lvl then
            -- lvl up dependency
            dependencies[recipe.name].lvl = lvl
        end
        dependencies[recipe.name].count = dependencies[recipe.name].count + count
    end
    return dependencies
end

-- Check a recipe for missing materials and keep track of inventory lvl
function checkMaterials(recipe, count, inventoryCount)
    local toCraft = {} -- items unavailable in inventory
    for _, item in ipairs(recipe.items) do
        -- if inventoryCount not set, initialize it to inventory lvl
        if inventoryCount[item.name] == nil then
            inventoryCount[item.name] = countItem(item.name)
        end
        local diff = (item.count * count) - inventoryCount[item.name]
        if diff > 0 then
            -- materials are missing
            inventoryCount[item.name] = 0
            if toCraft[item.name] == nil then
                toCraft[item.name] = diff
            else
                -- usefull if recipe contains multiple of the same item
                toCraft[item.name] = toCraft[item.name] + diff
            end
        else
            -- update what is left in inventory
            inventoryCount[item.name] = math.abs(diff)
        end
    end
    return inventoryCount, toCraft
end

-- Get if recipe can be crafted with current state of the inventory
-- Take into account inner recipes if items are missing and have a recipe
function getAvailability(recipe, count, dependencies, lvl, inventoryCount, missing, ok)
    -- get recipe dependencies for crafting in the right order
    dependencies = dependencies or {maxlvl=0} 
    -- lvl is the lvl of recursion for this recipe
    lvl = lvl or 0
    -- keep track of inventory count for items
    inventoryCount = inventoryCount or {}
    -- keep track of missing items
    missing = missing or {}
    if ok == nil then ok = true end

    -- check items for this recipe
    local inventoryCount, toCraft = checkMaterials(recipe, count, inventoryCount)
    lvl = lvl + 1
    for key, value in pairs(toCraft) do
        local recipeToCraft = recipes[key]
        if recipeToCraft ~= nil then
            -- if recipe produce more than one item, adjust number to craft
            value = math.ceil(value / recipeToCraft.count) -- round up
            -- Recurse this function
            local request = getAvailability(recipeToCraft, value, dependencies, lvl, inventoryCount, missing, ok)
            -- if a step fail, whole status must be false
            if not request.ok then
                ok = false
            end
            -- update recursive values
            inventoryCount = request.response.inventoryCount
            missing = request.response.missing
            dependencies = addDependency(request.response.dependencies, recipeToCraft, value, lvl)
        else
            -- Item is raw material without enough quantity or 
            -- we dont have a recipe for it. Throw error
            ok = false
            if not missing[key] then
                missing[key] = value
            else
            missing[key] = missing[key] + value
            end
            -- return {ok=false, response={recipe=recipe, count=count}, error=error}
        end
    end
    return {ok=ok, response={recipe=recipe, count=count, dependencies=dependencies, missing=missing, inventoryCount=inventoryCount}, error=missing}
end

function getInventorySlotsNumber()
    total = 0
    for key, value in pairs(inventory) do
        total = total + #value
    end
    return total
end

function progressBar(text)
    monitor.clear()
    local current = getInventorySlotsNumber()
    local max = current + #free
    local x, y = monitor.getSize()
    local ratio = (current * x) / max
    local percent = tonumber(current/max*100)
    monitor.setTextColor(colors.black)
    local barColor = nil
    if percent < 50 then
        barColor = colors.green
    elseif percent < 70 then
        barColor = colors.yellow
    elseif percent < 90 then
        barColor = colors.yellow
    else
        barColor = colors.red
    end
    monitor.setBackgroundColor(colors.red)
    local cpt = 1
    while cpt <= ratio do
        monitor.setCursorPos(cpt, 2)
        monitor.write(" ")
        cpt = cpt + 1
    end
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.write(text .. ": ".. math.floor((current/max*100)+0.5) .."%")
end
    
-- TODO ? show doable recipes to the GET screen
function getDoableRecipes(inventory, recipes)
    doableRecipes = {} -- dict key = value where value is a list of recipes
    for key, value in pairs(recipes) do
        if (inventory[key] == nil or #inventory[key] == 0) then
            local request = getAvailability(key)
            if request.ok then
                if not doableRecipes[key] then
                doableRecipes[key] = {request.response}
                else
                    table.insert(doableRecipes[key], request.response)
                end
            end
        end
    end
    return doableRecipes
end

-- TODO xpcall sendResponse()
function decodeMessage(message, client)
    local response
    if message.endpoint == "get" then
        response = get(message.item, message.count, message.from, message.slot)
    elseif message.endpoint == "info" then
        progressBar("DU")
        response = {ok=true, response=inventory}
    elseif message.endpoint == "put" then
        response = put(message.item.name, message.item.count, message.item.maxCount, message.from, message.slot)
    elseif message.endpoint == "recipes" then
        response = {ok=true, response=recipes}
    elseif message.endpoint == "make" then
        response = getAvailability(message.recipe, message.count)
    elseif message.endpoint == "add" then
        response = saveRecipe(message.recipe)
    end
    -- log("response:")
    -- log(response)
    sendResponse(client, response)
end

function handleRequests()
    while true do
        client, message = rednet.receive("INVENTORY")
        if client ~= nil then 
            -- log("request:")
            -- log(message)
            decodeMessage(message, client)
        end
    end
end

scanAll()
loadRecipes()
progressBar("DU")
print("Waiting for clients requests...")
handleRequests()
