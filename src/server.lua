local modem = peripheral.find("modem") or error("No modem attached", 0)
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
peripheral.find("modem", rednet.open)

RECIPES_FILE = "recipes.txt"
JOBS_FILE = "jobs.txt"
CRON_FILE = "cron.txt"
LOG_FILE = "server.log"
ALLOWED_INVENTORIES = {}
ALLOWED_INVENTORIES["minecraft:chest"] = true
ALLOWED_INVENTORIES["metalbarrels:gold_tile"] = true

variableLimit = false

inventoryChests = {}
recipes = {}
inventory = {}
free = {}
io_inventories = {}
jobs = {}
cronjobs = {}

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
    local remotes = modem.getNamesRemote()
    for i, remote in pairs(remotes) do
        if (ALLOWED_INVENTORIES[modem.getTypeRemote(remote)] and io_inventories[remote] == nil) then
            table.insert(inventoryChests, remote)
        end
    end
    for i, inv in ipairs(inventoryChests) do
        scanRemoteInventory(inv)
        monitor.setCursorPos(1, 1)
        monitor.write("[" .. tostring(i) .. "/" .. tostring(#inventoryChests) .. "] Loading")
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
    -- TODO optimize by using while loop ?
    -- TODO: pcall on callRemote
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
                local ok, ret = pcall(modem.callRemote, chest, "pushItems", turtle, location.slot.index, count, turtleSlot)
                if not ok then
                    return {ok=false, response={name=name, count=count}, error=ret}
                end
                local num = tonumber(ret)
                -- update inventory
                inventory[name][i]["slot"]["count"] = inventory_count - num
                count = count - num
                if count == 0 then break end
            elseif left == 0 then
                -- just enough item
                local ok, ret = pcall(modem.callRemote, chest, "pushItems", turtle, location.slot.index, count, turtleSlot)
                if not ok then
                    return {ok=false, response={name=name, count=count}, error=ret}
                end
                local num = tonumber(ret)
                -- add free slot and remove inventory slot
                count = count - num
                local slot_count = inventory_count - num
                inventory[name][i]["slot"]["count"] = slot_count
                if slot_count == 0 then
                    table.insert(free, {chest=chest, slot={index=location.slot.index, limit=location.slot.limit}})
                    inventory[name][i].status = "TO_REMOVE"
                end
                if count == 0 then break end
            else
                -- not enough items get the maximum for this slot and continue the loop
                local ok, ret = pcall(modem.callRemote, chest, "pushItems", turtle, location.slot.index, inventory_count, turtleSlot)
                if not ok then
                    return {ok=false, response={name=name, count=count}, error=ret}
                end
                local num = tonumber(ret)
                -- add free slot, remove inventory slot and update count
                table.insert(free, {chest=chest, slot={index=location.slot.index, limit=location.slot.limit}})
                count = count - num
                inventory[name][i].status = "TO_REMOVE"
            end
        end
        -- if not enough items, clear what was still extracted
        inventory[name] = clearInventory(inventory[name])
        if count > 0 then
            local error = "Not enough " .. name .. ", missing " .. count
            return {ok=false, response={name=name, count=count}, error=error}
        else
            return {ok=true, response={name=name, count=count}, error=""}
        end
    end
end

function loadJobs()
    local n = 0
    if not fs.exists(JOBS_FILE) then return {} end
    for line in io.lines(JOBS_FILE) do
        local job = textutils.unserialize(line)
        for _, task in ipairs(job.tasks) do
            io_inventories[task.params.location] = true
        end
        jobs[job.name] = job.tasks
        n = n + 1
    end
    print(n .. " jobs loaded from " .. JOBS_FILE)
end

function loadCronJobs()
    local n = 0
    if not fs.exists(CRON_FILE) then return {} end
    for line in io.lines(CRON_FILE) do
        local job = textutils.unserialize(line)
        io_inventories[job.name] = true
        cronjobs[job.name] = job.task
        n = n + 1
    end
    print(n .. " cron loaded from " .. CRON_FILE)
end

function loadRecipes()
    local n = 0
    if not fs.exists(RECIPES_FILE) then return {} end
    for line in io.lines(RECIPES_FILE) do
        local recipe = textutils.unserialize(line)
        recipes[recipe.name] = recipe 
        n = n + 1
    end
    print( n .. " recipes loaded from ".. RECIPES_FILE)
end

function put_in_free_slot(name, count, maxCount, turtle, turtleSlot)
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
            local ok, ret = pcall(modem.callRemote, fslot.chest, "pullItems", turtle, turtleSlot, count, fslot.slot.index)
            if not ok then
                -- if error occurs, clean free and stop
                free = clearInventory(free) or {}
                return {ok=false, response={name=name, count=count, maxCount=maxCount, turtle=turtle, turtleSlot=turtleSlot}, error=ret}
            end
            local num = tonumber(ret)
            -- add item in inventory
            table.insert(inventory[name], {chest=chest, slot={index=fslot.slot.index, limit=limit, count=num}})
            free[i].status = "TO_REMOVE"
            -- update free
            count = count - num
            if count == 0 then break end
        else
            -- put exceed slot limit, put max and continue loop
            local ok, ret = pcall(modem.callRemote, chest, "pullItems", turtle, turtleSlot, limit, fslot.slot.index)
            if not ok then
                -- if error occurs, clean free and stop
                free = clearInventory(free) or {}
                return {ok=false, response={name=name, count=count, maxCount=maxCount, turtle=turtle, turtleSlot=turtleSlot}, error=ret}
            end
            local num = tonumber(ret)
            -- update inventory
            table.insert(inventory[name], {chest=chest, slot={index=fslot.slot.index, limit=limit, count=num}})
            -- remove free slot
            count = count - num
            free[i].status = "TO_REMOVE"
        end
    end
    free = clearInventory(free) or {}
    if count > 0 then
        return {ok=false, response={name=name, count=count, maxCount=maxCount, turtle=turtle, turtleSlot=turtleSlot}, error="Not enough free space"}
    else
        return {ok=true, response={name=name, count=count, maxCount=maxCount, turtle=turtle, turtleSlot=turtleSlot}}
    end
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
                    local ok, ret = pcall(modem.callRemote, islot.chest, "pullItems", turtle, turtleSlot, count, islot.slot.index)
                    if not ok then
                        -- if error occurs, stop immediately
                        return {ok=false, response={name=name, count=count, maxCount=maxCount, turtle=turtle, turtleSlot=turtleSlot}, error=ret}
                    end
                    local num = tonumber(ret)
                    inventory[name][i]["slot"]["count"] = islot.slot.count + num
                    return {ok=true, response={name=name, count=count}, error=""}
                else
                    -- not enough space, put max and continue
                    local ok, ret = pcall(modem.callRemote, islot.chest, "pullItems", turtle, turtleSlot, available, islot.slot.index)
                    if not ok then
                        -- if error occurs, stop immediately
                        return {ok=false, response={name=name, count=count, maxCount=maxCount, turtle=turtle, turtleSlot=turtleSlot}, error=ret}
                    end
                    local num = tonumber(ret)
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

-- TODO pcall sendResponse()
function decodeMessage(message, client)
    local response
    if message.endpoint == "get" then
        response = get(message.item, message.count, message.from, message.slot)
    elseif message.endpoint == "info" then
        progressBar("DU")
        response = {ok=true, response=inventory}
    elseif message.endpoint == "all" then
        progressBar("DU")
        response = {ok=true, response={inventory=inventory, recipes=recipes, jobs=jobs}}
    elseif message.endpoint == "inventoryChests" then
        response = {ok=true, response=inventoryChests}
    elseif message.endpoint == "put" then
        response = put(message.item.name, message.item.count, message.item.maxCount, message.from, message.slot)
    elseif message.endpoint == "recipes" then
        response = {ok=true, response=recipes}
    elseif message.endpoint == "make" then
        response = getAvailability(message.recipe, message.count)
    elseif message.endpoint == "add" then
        response = saveRecipe(message.recipe)
    elseif message.endpoint == "jobs" then
        response = {ok=true, response=jobs}
    elseif message.endpoint == "cronjobs" then
        response = {ok=true, response=cronjobs}
    elseif message.endpoint == "addCronJob" then
        response = addCronJob(message.job)
    elseif message.endpoint == "addJob" then
        response = addJob(message.job)
    elseif message.endpoint == "execJob" then
        response = execJob(message.job, message.count)
    end
    sendResponse(client, response)
end

function handleRequests()
    while true do
        client, message = rednet.receive("INVENTORY")
        if client ~= nil then 
            decodeMessage(message, client)
        end
    end
end

function addCronJob(job)
    -- TODO verify job
    -- Exemple: job = {inventory="minecraft:chest_1", task="listenInventory"}
    table.insert(cronjobs, job)
    local response
    if not cronjobs[job.name] then
        cronjobs[job.name] = job.task
        local file = fs.open(CRON_FILE, "a")
        file.write(textutils.serialize(job, { compact = true }) .. "\n")
        file.close()
        response = {ok=true, response=job}
    else
        response = {ok=false, response=job, error="Job with same name exists"}
    end
    return response
end

function addJob(job)
    -- TODO verify job (if for job.tasks, if not task in accepted task then return)
    -- Example: {name="oak_planks", tasks={{exec=sendItemToInventory, params=...}}
    local response
    if not jobs[job.name] then
        jobs[job.name] = job.tasks
        local file = fs.open(JOBS_FILE, "a")
        file.write(textutils.serialize(job, { compact = true }) .. "\n")
        file.close()
        response = {ok=true, response=job}
    else
        response = {ok=false, response=job, error="Job with this name already exists"}
    end
    return response
end

function execAllCronJobs()
    while true do
        local crons = {}
        for key, value in pairs(cronjobs) do
            if value == "listenInventory" then
                local fn = function() listenInventory(key) end
                table.insert(crons, fn)
            end
        end
        print("Exec " .. #crons .. " job(s)")
        parallel.waitForAll(table.unpack(crons))
        os.sleep(5)
    end
end

-- Return a copy of a simple table
function copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[copy(k)] = copy(v) end
    return res
end

-- Execute all tasks of given job, if n then multiply count for each tasks by n
function execJob(job, n)
    if not jobs[job] then return {ok=false, error="No job for name: ".. job} end
    job = jobs[job]
    n = n or 1
    local status = true
    local error = ""
    for _, task in ipairs(job) do
        local p = copy(task["params"])
        p["count"] = p["count"] or 1
        p["count"] = p["count"] * n
        if task.exec == "sendItemToInventory" then
            local request = sendItemToInventory(p)
            if not request.ok then 
                status = false
                error = error .. "[" .. request.error .. "] "
            end
        end
    end
    return {ok=status, response={job=job, count=count}, error=error}
end

-- Job function
function sendItemToInventory(...)
    local args = ...
    if not args["item"] then return end
    if not args["location"] then return end
    local count = args.count or 1
    return get(args["item"], count, args["location"], args["slot"])
end

-- Cron Job function
function listenInventory(inv)
    -- Listen only for first slots
    -- TODO: add log when pcall catch an error
    n = 1
    local ok, item = pcall(modem.callRemote, inv, "getItemDetail", n)
    while (ok and item) do
        local request = put(item.name, item.count, item.maxCount, inv, n)
        if not request.ok then
            return request
        end
        n = n + 1
        ok, item = pcall(modem.callRemote, inv, "getItemDetail", n)
    end
    return {ok=true, response=inv}
end

loadJobs()
loadCronJobs()
scanAll()
loadRecipes()
progressBar("DU")
print("Waiting for clients requests...")
parallel.waitForAll(handleRequests, execAllCronJobs)
