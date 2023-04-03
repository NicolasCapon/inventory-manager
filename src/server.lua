local modem = peripheral.find("modem") or error("No modem attached", 0)
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
peripheral.find("modem", rednet.open)

RECIPES_FILE = "recipes.txt"
ALLOWED_INVENTORIES = {}
ALLOWED_INVENTORIES["minecraft:chest"] = true
ALLOWED_INVENTORIES["metalbarrels:gold_tile"] = true

recipes = {}
inventory = {}
free = {}

function scanRemoteInventory(remote)
    -- scan remote inventory and populate global inventory
    local chest = peripheral.wrap(remote)
    for cslot=1,chest.size() do
        local item = chest.getItemDetail(cslot)
        local limit = chest.getItemLimit(cslot)
        if item == nil then
            -- no item, add this slot to free slots
            table.insert(free, {chest=remote, slot={index=cslot, limit=limit}})
        else
            local slots = inventory[item.name]
            if slots == nil then
                -- new item, add it and its associated slot
                inventory[item.name] = {{chest=remote, slot={index=cslot, limit=limit, count=item.count}}}
            else
                -- item already listed, add this slot only
                table.insert(inventory[item.name], {chest=remote, slot={index=cslot, limit=limit, count=item.count}})
            end
        end
    end
end 

function scanAll()
    -- Populate inventory
    -- TODO make progress bar
    local remotes = modem.getNamesRemote()
    for i, remote in pairs(remotes) do
        if ALLOWED_INVENTORIES[modem.getTypeRemote(remote)] then
            print("Scanning " .. remote .. "...")
            scanRemoteInventory(remote)
        end
    end
end

function sendResponse(client, response)
    -- client, {ok, reponse, error}
    local protocol = "INVENTORY"
    rednet.send(client, response, protocol)
end

function get(name, count, turtle, turtleSlot)
    local item = inventory[name]
    if item == nil then
        local error = name .. "not found"
        return {ok=false, response={name=name, count=count}, error=error}
    else
        for i, location in ipairs(item) do
            local chest = location.chest
            local inventory_count = location.slot.count
            local left = inventory_count - count
            if left > 0 then
                -- Enough items in this slot
                print("count" .. count)
                modem.callRemote(chest, "pushItems", turtle, location.slot.index, count, turtleSlot)
                -- update inventory
                inventory[name][i]["slot"]["count"] = left
                return {ok=true, response={name=name, count=count}, error=""}
            elseif left == 0 then
                -- just enough item
                print(turtle)
                print(location.slot.index)
                print(item.count)
                print(turtleSlot)
                modem.callRemote(chest, "pushItems", turtle, location.slot.index, item.count, turtleSlot)
                -- add free slot and remove inventory slot
                print(textutils.serialize(free))
                table.insert(free, {chest=chest, slot={index=location.slot.index, limit=location.slot.limit}})
                -- table.remove(inventory[name], i) -- TODO remove slots at the end
                inventory[name][i].status = "TO_REMOVE"
                inventory[name][i]["slot"]["count"] = left
                inventory[name] = clearInventory(inventory[name])
                return {ok=true, response={name=name, count=count}, error=""}
            else
                -- not enough items get the maximum for this slot and continue the loop
                modem.callRemote(chest, "pushItems", turtle, location.slot.index, inventory_count, turtleSlot)
                -- add free slot, remove inventory slot and update count
                table.insert(free, {chest=chest, slot={index=location.slot.index, limit=location.slot.limit}})
                -- table.remove(inventory[name], i) -- TODO remove slots at the end
                inventory[name][i].status = "TO_REMOVE"
                count = count - inventory_count
            end
        end
        -- if not enough items, clear what was still extracted
        inventory[name] = clearInventory(inventory[name])
        if count > 0 then
            local error = "Not enough " .. name .. ", missing " .. count
            return {ok=false, response={name=name, count=count}, error=error}
        end
    end
end

-- function getRecipesList()
--     for key, value in pairs(recipes) do
--         if value ~= nil then
--             n = n + 1
--             keyset[n] = key
--         end
--     end
--     return keyset
-- end

-- function getItemsList()
--     local keyset = {}
--     local n = 0
--     for key, value in pairs(inventory) do
--         if value ~= nil then
--             n = n + 1
--             keyset[n] = key
--         end
--     end
--     return keyset
-- end

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

function fuzzyFindItems(name)
    local items = {}
    for key, value in pairs(inventory) do
        -- if key.find(name) then
        if key == name then
            table.insert(items, key)
        end
    end
    return items
end

function put_in_free_slot(name, count, turtle, turtleSlot)
    for i, fslot in ipairs(free) do
        local chest = fslot.chest
        local limit = fslot.slot.limit
        local left = limit - count
        if left > -1 then
            -- put does not exceed item limit for this free slot
            print(fslot.slot.index)
            modem.callRemote(fslot.chest, "pullItems", turtle, turtleSlot, count, fslot.slot.index)
            -- add item in inventory
            table.insert(inventory[name], {chest=chest, slot={index=fslot.slot.index, limit=limit, count=count}})
            free[i].status = "TO_REMOVE"
            -- update free
            free = clearInventory(free)
            if free == nil then free = {} end
            return {ok=true, response={name=name, count=count}, error=""}
        else
            -- put exceed slot limit, put max and continue loop
            modem.callRemote(chest, "pullItems", turtle, turtleSlot, limit, fslot.slot.index)
            -- update inventory and free
            table.insert(inventory[name], {chest=chest, slot={index=fslot.slot.index, limit=limit, count=limit}})
            -- table.remove(free, i) -- TODO mark this and call ArrayRemove
            free[i].status = "TO_REMOVE"
            count = count - limit
        end
    end
    free = clearInventory(free)
    if free == nil then free = {} end
    return {ok=false, response={name=name, count=count}, error="Not enough free space"}
end

function put(name, count, turtle, turtleSlot)
    local item = inventory[name] 
    if item == nil then
        -- if item not in inventory, fill free slots
        inventory[name] = {}
        return put_in_free_slot(name, count, turtle, turtleSlot)
    else
        -- if inventory contains item
        for i, islot in ipairs(item) do
            local available = islot.slot.limit - islot.slot.count
            if available > 0 then
                local left = available - count
                -- free space available in this slot
                if left > -1 then
                    -- free space for this slot is enough
                    modem.callRemote(islot.chest, "pullItems", turtle, turtleSlot, count, islot.slot.index)
                    inventory[name][i]["slot"]["count"] = islot.slot.count + count
                    return {ok=true, response={name=name, count=count}, error=""}
                else
                    -- not enough space, put max and continue
                    modem.callRemote(islot.chest, "pullItems", turtle, turtleSlot, available, islot.slot.index)
                    inventory[name][i]["slot"]["count"] = islot.slot.limit
                    count = count - available
                end
            end
        end
        if count > 0 then
            -- use free space
            return put_in_free_slot(name, count, turtle, turtleSlot)
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
    term.setTextColour(colors.green)
    print(textutils.serialize(input))
    term.setTextColour(colors.white)
    return input
end

-- https://stackoverflow.com/questions/12394841/safely-remove-items-from-an-array-table-while-iterating
function clearInventory_TO_REMOVE(t)
    -- Remove slots marks as TO_REMOVE
    local j = 1
    local n = #t

    for i=1,n do
        print(i)
        if t[i].status == "TO_REMOVE" then
        print("clean")
            -- Move i's kept value to j's position, if it's not already there.
            if (i ~= j) then
                t[j] = t[i];
                t[i] = nil;
            end
            j = j + 1; -- Increment position of where we'll place the next kept value.
        else
            t[i] = nil;
        end
    end
    return t;
end

function clearGrid(turtleName)
    -- put each item in turtle grid into inventory, return false if put fails
    local status = true
    local responses = {}
    local turtle = peripheral.wrap(turtleName)
    for i=1,16 do
        print(textutils.serialize(peripheral.call(turtleName, "getItemDetail")))
        print(textutils.serialize(turtle.getItemDetail()))
        local item = modem.callRemote(turtle, "getItemDetail")
        if item ~= nil then
            -- slot not empty, put in inventory
            local response = put(item.name, item.count, turtle)
            table.insert(responses, response)
            if not response.ok then
                status = false
            end
        end
    end
    return {ok=status, response=responses, error=""}
end

-- function make(recipe, recursive, turtleID)
--     -- craft item given by its recipe
--     -- set recursive=true to craft sub recipes if necessary
--     local error = ""
--     local turtle = peripheral.wrap(turtleID)
--     for i, item in recipe.items do
--         turtle.select(item.slot)
--         local count = item.count
--         local current = turtle.getItemDetail()
--         -- test if item already in crafting grid
--         if current.name ~= item.name then
--             -- clean slot
--             put(current.name, current.count)
--         else
--             count = count - current.count
--         end
--         if count < -1 then
--             -- put back the difference
--             put(item.name, current.count - count)
--         end
--         if count > 0 then
--             if not get(item.name, count, turtleID).ok then
--                 if not recursive then
--                     error = "Not enough " .. item.name
--                     return {ok=false, response=recipe, error=error}
--                 end
--                 -- Search for recipe
--                 local recipe = recipes[item.name]
--                 if recipe ~= nil then
--                     if not make(recipe, recursive, turtleID).ok then
--                         error = "Cannot craft recipe " .. recipe.name
--                         return {ok=false, response=recipe, error=error}
--                     end
--                 else
--                     error = "Missing item or recipe for " .. item.name
--                     return {ok=false, response=recipe, error=error}
--                 end
--             end
--         end
--     end
--     return {ok=turtle.craft(), response=recipe, error=error}
-- end

function fuzzyFindRecipes(name)
    local recs = {}
    for key, value in pairs(recipes) do
        if key.find(name) then
            table.insert(recs, key)
        end
    end
    return recs
end

function saveRecipe(recipe)
    if recipes[recipe] ~= nil then
        -- recipe already exist print error
        return {ok=false, response=recipe, error="Recipe already exists"}
    end
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

function getMissingItems(recipe)
    local missingItems = {}
    for _, item in ipairs(recipe.items) do
        if item.count > countItem(item.name) then
            table.insert(missingItems, item)
        end
    end
    return missingItems
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

function getSubCrafts(recipe, dependencies, lvl)
    -- TODO handle if we need to craft more than one object ?
    lvl = lvl + 1
    local error = nil
    -- Verify each recipe item in inventory
    local missingItems = getMissingItems(recipe)
    if #missingItems > 0 then
        -- Do the recursive part
        for _, item in ipairs(missingItems) do
            local missingItemRecipe = recipes[item.name]
            if missingItemRecipe == nil then
                -- Item and recipe are missing, throw error
                error = "Missing item " .. item.name .. " or recipe for it."
                return {ok=false, response=item, error=error}
            else
                -- Only item is missing, get sub-recipes (dependencies)
                local response = getSubCrafts(missingItemRecipe, dependencies, lvl)
                if response.ok then
                    dependencies = addDependency(dependencies, missingItemRecipe, item.count, lvl)
                else
                    return {ok=false, response=response.response, error=response.error}
                end
            end
        end
    end
    return {ok=true, response={recipe=recipe, dependencies=dependencies}, error=error}
end

function decodeMessage(message, client)
    if message.endpoint == "get" then
        -- Verify item name
        local items = fuzzyFindItems(message.item)
        if #items > 1 then
            return sendResponse(client, {ok=false, response=items, error="Multiple items found"})
        elseif #items == 1 then
            message.item = items[1]
        else
            return sendResponse(client, {ok=false, response={}, error="Item not in inventory"})
        end
        -- Verify item count
        if message.count ~= nil then
            return sendResponse(client, get(message.item, message.count, message.from, message.slot))
        else
            return sendResponse(client, get(message.item, 1, message.from, message.slot))
        end
    elseif message.endpoint == "info" then
        progressBar("DU")
        return sendResponse(client, {ok=true, response=inventory})
    elseif message.endpoint == "clean" then
        return sendResponse(client, clearGrid(message.from))
    elseif message.endpoint == "put" then
        return sendResponse(client, put(message.item, message.count, message.from, message.slot))
    elseif message.endpoint == "recipes" then
        return sendResponse(client, {ok=true, response=recipes})
    elseif message.endpoint == "make" then
        sendResponse(client, getSubCrafts(message.recipe, {maxlvl=0}, 0))
    elseif message.endpoint == "add" then
        sendResponse(client, saveRecipe(message.recipe))
    end
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
    elseif percent < 80 then
        barColor = colors.orange
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
    
function handleRequests()
    while true do
        client, message = rednet.receive("INVENTORY")
        if client ~= nil then 
            print(textutils.serialize(message))
            decodeMessage(message, client)
        end
    end
end

scanAll()
loadRecipes()
progressBar("DU")
print("Waiting for clients requests...")
handleRequests()

