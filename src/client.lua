local basalt = require("basalt")

local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open("right")

listIsFiltered = false
inventory = {} -- dict
recipes = {} -- dict
items = {}

function sendMessage(message, modem)
    local SERVER = 6 --TODO put real computer ID here
    local PROTOCOL = "INVENTORY"
    local TIMEOUT = 5

    message["from"] = modem.getNameLocal()
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    if not id then
        response = {ok=false, response={}, error="Server not responding"}
        log(response.error, true)
    elseif not response.ok then
        log(response.error, true)
    end
    return response
end

function getItemCount(item)
    local total = 0
    for _, s in ipairs(item) do
        total = total + s.slot.count
    end
    return total
end

function log(message, keep)
    if not keep then basalt.debugList:clear() end
    basalt.debug(textutils.serialize(message))
end

function sync()
    local request = sendMessage({endpoint="all"}, modem)
    if request.ok then
        inventory = request.response.inventory
        recipes = request.response.recipes
        jobs = request.response.jobs
    end
    return request.ok
end

-- Update items in list based on a string filter
function updateItemsList(filter)
    items = {}
    itemsList:clear()
    if filter then
        for key, value in pairs(inventory) do
            if string.find(key, filter) then
                table.insert(items, key)
                itemsList:addItem(getItemCount(value) .. "\t" .. key)
            end
        end
        -- Display available recipes for unavailable items
        for key, value in pairs(recipes) do
            if not inventory[key] then
                -- Item not in inventory, display recipe instead
                if string.find(key, filter) then
                    table.insert(items, key)
                    itemsList:addItem("%\t" .. key, colors.purple)
                end
            end
        end
        -- Display jobs
        for key, value in pairs(jobs) do
            if string.find(key, filter) then
                table.insert(items, key)
                itemsList:addItem("@\t" .. key, colors.lime)
            end
        end
    else
        for key, value in pairs(inventory) do
            table.insert(items, key)
            itemsList:addItem(getItemCount(value) .. "\t" .. key)
        end
        -- Display available recipes for unavailable items
        for key, value in pairs(recipes) do
            if not inventory[key] then
                -- Item not in inventory, display recipe instead
                table.insert(items, key)
                itemsList:addItem("%\t" .. key)
            end
        end
        -- Display jobs
        for key, value in pairs(jobs) do
            table.insert(items, key)
            itemsList:addItem("@\t" .. key, colors.lime)
        end
    end
end

function filterList(self, event, key)
    local selection = self:getValue()
    if string.len(selection) > 2 then
        listIsFiltered = true
        updateItemsList(selection)
    elseif listIsFiltered then
        updateItemsList()
        listIsFiltered = false
    end
    itemsList:selectItem(1)
    itemsList:setOffset(0)
end

function make(name, count)
    if not checkForEmptySlots() then
        log("Dump first")
        return false
    end
    local recursive = true
    local recipe = recipes[name]
    if not recipe then return false end
    local dependencies = {}
    local request = sendMessage({endpoint="make", recipe=recipe, count=count}, modem) 
    if request.ok then
        dependencies = request.response.dependencies
    else
        log("Click to see what's missing\n" .. textutils.serialize(request.error))
        return false
    end
    local deplvl = dependencies["maxlvl"]
    while deplvl > 0 do
        for dependency, value in pairs(dependencies) do
            -- Avoid maxlvl entry
            if dependency ~= "maxlvl" then
                if value.lvl == deplvl then
                    if not craft(recipes[dependency], value.count).ok then 
                        return false 
                    end
                end
            end
        end
        deplvl = deplvl - 1
    end
    if not craft(recipe, count).ok then 
        return false 
    end
    return true
end

function craft(recipe, count)
    -- TODO check if count is not too high first ?
    -- Do items can have multiple in same slot ? if not max = 64 ?

    -- We have all dep, just craft
    local status = true
    local error = ""
    -- Make room first
    local request = dump()
    if not request.ok then
        status = false
        return request
    end
    -- Get all items
    for _, item in ipairs(recipe.items) do
        turtle.select(item.slot)
        local total = item.count * count
        local message = {endpoint="get", item=item.name, count=total, slot=turtle.getSelectedSlot()}
        request = sendMessage(message, modem)
        if not request.ok then
            error = request.error
            log(error)
            status = false
            return request
        end
    end
    -- Some items are not consumed after craft, move crafting result slot to
    -- an unused slot
    turtle.select(4)
    if not turtle.craft(count) then
        error = "error while crafting " .. recipe.name
        log(error)
        status = false
        return {ok=status, message=recipe, error=error}
    end
    return {ok=status, message=recipe, error=error}
end

function learnRecipe(self, event, button, x, y)
    -- Check for slots that should be empty
    local empty = {4, 8, 12, 13, 14, 15, 16}
    for _,i in ipairs(empty) do
        if turtle.getItemDetail(i) ~= nil then
            log("Only put items in the top left 3x3 grid")
            return false
        end
    end
    local recipe = {items={}, type="crafting_table"}
    local slots = {1, 2, 3, 5, 6, 7, 9, 10, 11}
    local counter = 0
    for _,i in ipairs(slots) do
        local item = turtle.getItemDetail(i)
        if item ~= nil then
            counter = counter + 1
            table.insert(recipe["items"], {slot=i, name=item.name, count=item.count})
        end
    end
    if counter == 0 then
        log("Invalid recipe")
    end
    -- craft in last slot
    turtle.select(16)
    if turtle.craft() then
        recipe["name"]  = turtle.getItemDetail(16).name
        recipe["count"] = turtle.getItemDetail(16).count
        local request = sendMessage({endpoint="add", recipe=recipe}, modem)
        if request.ok then
            log("New recipe [" .. recipe["name"] .. "] learned.")
            sync()
        end
    else
        log("Invalid recipe")
    end
end

function dump(self, event, button, x, y)
    for i=1,16 do
        local item = turtle.getItemDetail(i)
        if item ~= nil then
            local message = {endpoint="put", item=item, slot=i}
            local request = sendMessage(message, modem)
            if not request.ok then
                log(request.error)
                local error = "Dump failed: " .. request.error
                return {ok=false, message=request.message, error=error}
            end
        end
    end
    if self then
        -- Avoid calling this when using this function without handler
        sync()
        updateItemsList()
        input:setValue("")
        countInput:setValue(1)
        -- TODO make this works
        main:setFocusedObject(input)
    end
    return {ok=true, message="dump", error=""}
end

function checkForEmptySlots()
    for i=1,16 do
        if turtle.getItemDetail(i) ~= nil then
            log("Remove items in turtle inventory first (use command dump)")
            return false
        end
    end
    return true
end

function get(name, count)
    turtle.select(1) -- always get on slot 1 for consistency
    if not checkForEmptySlots() then
        log("Dump first")
        return false
    end
    local maxCount = getItemCount(inventory[name])
    if count > maxCount then
        -- Try to craft first if there is a recipe for this item
        local recipeCount = count - maxCount
        if recipeCount > 64 then
            -- Cap the max to 64
            recipeCount = 64
        end
        recipe = recipes[name]
        if recipe then
            if not make(name, recipeCount) then
                -- If we cannot craft then only give what's in inventory
                count = maxCount
            else
                dump()
            end
        else
            -- No recipe for this item, only give what's in inventory
            count = maxCount
        end
    end
    local slot
    -- If count is superior to 64, dont specify slot for pushItem() to be able
    -- to push in other free slots
    if count < 65 then
        slot = turtle.getSelectedSlot()
    end
    local message = {item=name, endpoint="get", count=count, slot=slot}
    return sendMessage(message, modem).ok
end

function isRecipe(name)
    return string.sub(name, 1, 1) == "%"
end

function isJob(name)
    return string.sub(name, 1, 1) == "@"
end

-- Show a frame dynamically created to get missing liveParams for a job
function invokeLiveParamsPopup(job, liveParams)
    -- TODO: Isolate in a separate file ?
    -- Collect all basalt object for this popup to be destroyed later on
    local basaltObjects = {}
    -- Create a UI bloc and return a function to collect item name
    local function createItemBloc(y, frame, text)
        local list
        local function filter(self, event, key)
            local filter = self:getValue()
            if filter:len() > 2 then
                list:clear()
                for key, value in pairs(inventory) do
                    if string.find(key, filter) then
                        list:addItem(key)
                    end
                end
            end
        end
        table.insert(basaltObjects, frame:addLabel():setText(text)
                                                    :setPosition(1, y))
        y = y + 1
        table.insert(basaltObjects, frame:addInput():setPosition(1, y)
                                                    :setSize("parent.w", 1)
                                                    :setBackground(colors.white)
                                                    :onChange(filter))
        y = y + 1
        local valueObj = frame:addList():setPosition(1, y)
                                        :setSize("parent.w", 3)
                                        :setBackground(colors.yellow)
        table.insert(basaltObjects, valueObj)
        for key, value in pairs(inventory) do
            list:addItem(key)
        end
        y = y + 1
        local function getValue()
            return valueObj:getValue().text
        end
        return getValue
    end

    -- Create a UI bloc and return a function to collect item count
    local function createCountBloc(y, frame, text)
        table.insert(basaltObjects, frame:addLabel():setText(text)
                                                    :setPosition(1, y))
        y = y + 1
        local valueObj = frame:addInput():setInputType("number")
                                           :setPosition(1, y)
                                           :setSize("parent.w", 1)
                                           :setBackground(colors.white))
        table.insert(basaltObjects, valueObj)
        y = y + 1
        local function getValue()
            return valueObj:getValue()
        end
        return getValue
    end

    -- Create a UI bloc and return a function to collect destination chest
    local function createLocationBloc(y, frame, text)
        -- TODO call server for unused chests
        table.insert(basaltObjects, frame:addLabel():setText(text)
                                                    :setPosition(1, y))
        y = y + 1
        local valueObj = frame:addDropdown():setPosition(1, y)
                                            :setSize("parent.w - 1", 1)
                                            :setBackground(colors.white)
        table.insert(basaltObjects, valueObj)
        -- Request chests names and add them as items to the dropDown
        local satelliteChests = {}
        local message = {endpoint="satelliteChests"}
        local request = sendMessage(message, modem)
        if request.ok then
            satelliteChests = request.response
        end
        for _, chest in ipairs(satelliteChests) do
            valueObj:addItem(chest)
        end
        y = y + 1
        local function getValue()
            return valueObj:getValue()
        end
        return getValue()
    end

    -- Create popup frame
    local f = main:addFrame("liveParams"):setSize("parent.w", "parent.h")
                                         :setScrollable()
    -- params is a list of table where each item of the list is a table of
    -- functions for collecting params of each task
    local params = {} 
    local getValueFns = {}
    local y = 1 -- store y value for dynamically construct UI
    for i, task in ipairs(liveParams) do
        -- dynamically construct the UI by looping through tasks
        table.insert(basaltObjects, f:addLabel():setText("Task " .. i)
                                                :setPosition(1, y)
                                                :setForeground(colors.orange)
                                                :setSize("parent.w", 1)
                                                :setBackground(colors.blue))
        y = y + 1
        for param, value in pairs(task) do
            if param == "item" then
                getValueFns[param] = createItemBloc(y, f, "Item name")
            elseif param == "count" then
                getValueFns[param] = createItemBloc(y, f, "Item count")
            elseif param == "location" then
                getValueFns[param] = createLocationBloc(y, f, "Destination chest")
            end
        end
        table.insert(params, getValueFns)
    end

    -- Function to destroy this popup
    local function selfDestroy()
        for _, obj in ipairs(basaltObjects) do
            main:remove(obj)
        end
    end

    -- Button functions
    local function collectValues() 
        local endParams = {}
        -- Collect values of each UI Objects of interest
        for _, task in ipairs(params) do
            for p, fn in pairs(getValueFns) do
                -- log(p .. ", " .. fn()) TODO remove after testing
                endParams[p] = fn()
            end
        end
        -- Submit the job with collected live params
        local message = {endpoint="execJob", job=selectedItem, count=count, params=endParams}
        local request = sendMessage(message, modem)
        if request.ok then
            selfDestroy() -- We dont need the popup anymore, destroy it
        else
            log(request.error)
        end
    end

    local function cancel()
        params = nil
        selfDestroy()
    end

    -- Finally add buttons
    local buttonOK = f:addButton("okLive")
                      :setText("OK")
                      :onClick(collectValues)
                      :setPosition("parent.w - 9", "parent.h")
                      :setSize(10, 1)
                      :setBackground(colors.green)
    table.insert(basaltObjects, buttonOK)
    local buttonKO = f:addButton("cancelLive")
                      :setText("Cancel")
                      :setPosition(1, "parent.h")
                      :setSize(10, 1)
                      :setBackground(colors.red)
                      :onClick(cancel)
    table.insert(basaltObjects, buttonKO)
    return params
end

-- Verify if this job contains live parameters == "*"
-- If it contains, then pop up the right frame to handle theses params
function getLiveParams(job)
    local atLeastOne = false
    local liveParams = {}
    for _, task in ipairs(job) do
        local params = {}
        for key, value in pairs(task.params) do
            if value == "*" then
                params[key] = value
                atLeastOne = true
            end
        end
        table.insert(liveParams, params)
    end
    if atLeastOne then
        invokeLiveParamsPopup(job, liveParams)
    end
    return atLeastOne
end

function getSelectedItem(self, event, button, x, y)
    local index = itemsList:getItemIndex()
    local selectedItem = items[index]
    local count = tonumber(countInput:getValue())
    local selectedItemText = itemsList:getItem(index).text
    if isRecipe(selectedItemText) then
        make(selectedItem, count)
    elseif isJob(selectedItemText) then
        if getLiveParams(jobs[selectedItem]) then
            return true -- Dont update and dont set focus to main frame
        else
            local message = {endpoint="execJob", job=selectedItem, count=count}
            if not sendMessage(message, modem).ok then return false end
        end
    else
        if not get(selectedItem, count) then return false end
    end
    -- Reset position and values
    -- TODO factorize
    input:setValue("")
    countInput:setValue(1)
    main:setFocusedObject(input)
    sync()
    updateItemsList()
    countInput:setValue(1)
    itemsList:selectItem(1)
    itemsList:setOffset(0)
end

function navigation(self, event, key)
    local focus = main:getFocusedObject()
    local listIndex = itemsList:getItemIndex()
    local listMax = itemsList:getItemCount()
    if key == keys.tab then
        if focus == countInput then
            main:setFocusedObject(input)
        else
            main:setFocusedObject(countInput)
            countInput:setValue("")
        end
        return true
    elseif key == keys.enter then
        getSelectedItem()
        return true
    elseif key == keys.f3 then
        dump(true)
        return true
    elseif key == keys.f5 then
        refresh()
        return true
    elseif (key == keys.up and listIndex > 1) then
        listIndex = listIndex - 1
        itemsList:selectItem(listIndex)
        local currentOffset = itemsList:getOffset()
        if currentOffset > 0 then
            itemsList:setOffset(currentOffset - 1)
        end
        return true
    elseif (key == keys.down and listIndex < listMax) then
        listIndex = listIndex + 1
        itemsList:selectItem(listIndex)
        if (listIndex > 4 and listIndex < listMax) then
            itemsList:setOffset(itemsList:getOffset() + 1)
        end
        return true
    end
end

function refresh(self, event, button, x, y)
    input:setValue("")
    countInput:setValue(1)
    main:setFocusedObject(input)
    sync()
    updateItemsList()
    countInput:setValue(1)
    itemsList:selectItem(1)
    itemsList:setOffset(0)
end

-- TODO try to apply local to these variables
main = basalt.createFrame():addLayout("client.xml")
input = main:getObject("input"):onKey(navigation):onChange(filterList)
countInput = main:getObject("countInput"):setValue(1):onKey(navigation)
itemsList = main:getObject("itemsList"):onKey(navigation)

main:getObject("getButton"):onClick(getSelectedItem)
main:getObject("dumpButton"):onClick(dump)
main:getObject("learnButton"):onClick(learnRecipe)
main:getObject("refreshButton"):onClick(refresh)
main:setFocusedObject(input)

sync()
updateItemsList()

basalt.autoUpdate()
