local utils = require("utils")
local basalt = require("basalt")

local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open("right")

listIsFiltered = false
inventory = {} -- dict
recipes = {} -- dict
items = {}

function log(message, keep)
    if not keep then basalt.debugList:clear() end
    basalt.debug(textutils.serialize(message))
end

function updateInventory()
    local request = sendMessage({endpoint="info"}, modem)
    if request.ok then
        inventory = request.response
    end
    local requestRecipes = sendMessage({endpoint="recipes"}, modem)
    if requestRecipes.ok then
        recipes = requestRecipes.response
    end
    return request.ok and requestRecipes.ok
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
    if not recipe then return false end -- TODO pretty this
    local dependencies = {}
    local request = sendMessage({endpoint="make", recipe=recipe, count=count}, modem) 
    if request.ok then
        dependencies = request.response.dependencies
    else
        -- TODO show error message
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
            updateInventory()
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
        updateInventory()
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

function getSelectedItem(self, event, button, x, y)
    local index = itemsList:getItemIndex()
    local selectedItem = items[index]
    local count = tonumber(countInput:getValue())
    if isRecipe(itemsList:getItem(index).text) then
        make(selectedItem, count)
    else
        if not get(selectedItem, count) then return false end
    end
    -- Reset position and values
    -- TODO factorize
    input:setValue("")
    countInput:setValue(1)
    main:setFocusedObject(input)
    updateInventory()
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
    updateInventory()
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

updateInventory()
updateItemsList()

basalt.autoUpdate()
