local utils = require("utils")
local completion = require "cc.completion"
local basalt = require("basalt")
local modem = peripheral.find("modem") or error("No modem attached", 0)

-- TODO voyant d'indication si ok
-- TODO popup de message d'erreur

rednet.open("right")
listIsFiltered = false
local inventory = {}
-- TODO factorize
local request = sendMessage({endpoint="info"}, modem)
if request.ok then
    inventory = request.response
end
items = {}

function learnRecipe(self, event, button, x, y)
    -- Check for slots that should be empty
    local empty = {4, 8, 12, 13, 14, 15, 16}
    for _,i in ipairs(empty) do
        if turtle.getItemDetail(i) ~= nil then
            return help()
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
        return help()
    end

    -- craft in last slot
    turtle.select(16)
    if turtle.craft() then
        recipe["name"]  = turtle.getItemDetail(16).name
        recipe["count"] = turtle.getItemDetail(16).count
        local request = sendMessage({endpoint="add", recipe=recipe}, modem)
        if not request.ok then
            printError(request.error)
        else
            printColor("New recipe [" .. recipe["name"] .. "] learned.", colors.green)
        end
    else
        printError("Invalid recipe")
    end
end

function dump(self, event, button, x, y)
    for i=1,16 do
        local item = turtle.getItemDetail(i)
        if item ~= nil then
            local message = {endpoint="put", item=item.name, count=item.count, slot=i}
            local request = sendMessage(message, modem)
            if not request.ok then
                printError(request.error)
                local error = "Dump failed: " .. request.error
                return {ok=false, message=request.message, error=error}
            end
        end
    end
    -- TODO factorize
    local request = sendMessage({endpoint="info"}, modem)
    if request.ok then
        inventory = request.response
        -- TODO factorize
        items = {}
        itemsList:clear()
        for key, value in pairs(inventory) do
            table.insert(items, key)
            itemsList:addItem(getItemCount(value) .. "\t" .. key)
        end
    end
    sub[1]:setFocusedObject(input)
    return {ok=true, message="dump", error=""}
end

function checkForEmptySlots()
    for i=1,16 do
        if turtle.getItemDetail(i) ~= nil then
            printError("Remove items in turtle inventory first (use command dump)")
            return false
        end
    end
    return true
end

local selection = ""

function getSelectedItem(self, event, button, x, y)
    if not checkForEmptySlots() then
        basalt.debug("Dump first")
        return false
    end
    turtle.select(1)
    local selectedItem = items[itemsList:getItemIndex()]
    local count = tonumber(countInput:getValue())
    local maxCount = getItemCount(inventory[selectedItem])
    if count > maxCount then
        count = maxCount
    end
    local message = {item=selectedItem, endpoint="get", count=count, slot=turtle.getSelectedSlot()}
    sendMessage(message, modem)
    -- Reset position and values
    input:setValue("")
    countInput:setValue(1)
    sub[1]:setFocusedObject(input)
    -- TODO factorize
    local request = sendMessage({endpoint="info"}, modem)
    if request.ok then
        inventory = request.response
        -- TODO factorize
        items = {}
        itemsList:clear()
        for key, value in pairs(inventory) do
            table.insert(items, key)
            itemsList:addItem(getItemCount(value) .. "\t" .. key)
        end
        countInput:setValue(1)
        itemsList:selectItem(1)
        itemsList:setOffset(0)
    end
end

function navigation(self, event, key)
    local focus = sub[1]:getFocusedObject()
    local listIndex = itemsList:getItemIndex()
    local listMax = itemsList:getItemCount()
    if key == keys.tab then
        if focus == countInput then
            sub[1]:setFocusedObject(input)
        else
            sub[1]:setFocusedObject(countInput)
            countInput:setValue("")
        end
        return true
    elseif key == keys.enter then
        getSelectedItem()
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

function filterList(self, event, key)
    selection = self:getValue()
    if string.len(selection) > 2 then
        listIsFiltered = true
        itemsList:clear()
        items = {}
        for key, value in pairs(inventory) do
            if string.find(key, selection) ~= nil then
                table.insert(items, key)
                itemsList:addItem(key .. " (" .. getItemCount(value) .. ")")
            end
        end
    elseif listIsFiltered then
        for key, value in pairs(inventory) do
            itemsList:addItem(key .. " (" .. getItemCount(value) .. ")")
        end
        listIsFiltered = false
    end
end

local theme = {FrameBG = colors.lightGray, FrameFG = colors.black}
local main = basalt.createFrame()
sub = {
    main:addFrame():setPosition(1, 2):setSize("parent.w", "parent.h - 1"),
    main:addFrame():setPosition(1, 2):setSize("parent.w", "parent.h - 1"):hide(),
}

local function openSubFrame(id) -- we create a function which switches the frame for us
    if(sub[id]~=nil)then
        for k,v in pairs(sub)do
            v:hide()
        end
        sub[id]:show()
        -- TODO set focus on input here ?
        -- Maybe add function that handle loading of recipe or items depending
        -- of the frame
    end
end

local menubar = main:addMenubar()-- :setScrollable() -- we create a menubar in our main frame.
    :setSize("parent.w")
    :onChange(function(self, val)
        openSubFrame(self:getItemIndex()) -- here we open the sub frame based on the table index
    end)
    :addItem("Get")
    :addItem("Craft")

input = sub[1]:addInput()
              :setInputType("text")
              :setPosition(1, 2)
              :setSize("parent.w - 4", 1)
              :setBackground(colors.white)
              :setFocus()
              :onKeyUp(filterList)
              :onKey(navigation)

countInput = sub[1]:addInput()
                   :setInputType("number")
                   :setPosition("parent.w - 3", 2)
                   :setSize(4, 1)
                   :setBackground(colors.cyan)
                   :onKey(navigation)
                   :setValue(1)

itemsList = sub[1]:addList()
                  :setPosition(1,3)
                  :setScrollable(true)
                  :setBackground(colors.pink)
                  :setSize("parent.w", "parent.h - 3")
                  :onKey(navigation)

recipeInput = sub[2]:addInput()
              :setInputType("text")
              :setPosition(1, 2)
              :setSize("parent.w - 4", 1)
              :setBackground(colors.white)
              :setFocus()
              :onKeyUp(filterList)
              :onKey(navigation)

recipesList = sub[2]:addList()
                  :setPosition(1,3)
                  :setScrollable(true)
                  :setBackground(colors.pink)
                  :setSize("parent.w", "parent.h - 3")
                  :onKey(navigation)

-- TODO factorize
for key, value in pairs(inventory) do
    table.insert(items, key)
    itemsList:addItem(getItemCount(value) .. "\t" .. key)
end

local getButton = sub[1]:addButton():setText("GET"):setSize(10, 1):setPosition("parent.w - 9", "parent.h"):setBackground(colors.green)
local dumpButton = sub[1]:addButton():setText("DUMP"):setSize(10, 1):setPosition("parent.w - 19", "parent.h"):setBackground(colors.red)

local craftButton = sub[2]:addButton():setText("CRAFT"):setSize(10, 1):setPosition("parent.w - 9", "parent.h"):setBackground(colors.green)
local recipeDumpButton = sub[2]:addButton():setText("DUMP"):setSize(10, 1):setPosition("parent.w - 19", "parent.h"):setBackground(colors.red)
local learnRecipeButton = sub[2]:addButton():setText("LEARN"):setSize(10, 1):setPosition("parent.w - 29", "parent.h"):setBackground(colors.cyan)

-- inventory frame
getButton:onClick(getSelectedItem)
dumpButton:onClick(dump)
-- recipe frame
-- TODO craft button
recipeDumpButton:onClick(dump)
learnRecipeButton:onClick(learnRecipe)

basalt.autoUpdate()

-- TODO repeat this script for each endpoint
-- if #arg > 2 then
-- printError("Incorrect number of arguments, usage:\nget <item> <quantity>")
-- return
-- elseif #arg == 0 then
--     -- interactive prompt mode
--     local history = {} -- TODO load history from file ?
--     local items = {}
--     local request = sendMessage({endpoint="info"}, modem)
--     if request.ok then
--         inventory = request.response
--         items = getItemsFromInventory(inventory)
--     end
-- 
--     printColor("Choose item to get:", colors.lightBlue)
--     item = read(nil, history, function(text) return completion.choice(text, items) end, "")
--     if not itemInList(item, items) then
--         printError("Item not found")
--     else
--         local s = split(item, ":")
--         item = s[2] .. ":" .. s[1]
--         local max = getItemCount(inventory[item])
--         printColor("Choose quantity (max=".. max .. "):", colors.lightBlue)
--         quantity = toNumberOrDefault(read(), 1)
--     end
-- elseif #arg == 1 then
--     item = arg[1]
-- elseif #arg == 2 then
--     item = arg[1]
--     quantity = toNumberOrDefault(arg[2], 1)
-- end
-- 
-- -- Send request to server
-- local message = {item=item, endpoint="get", count=quantity, slot=turtle.getSelectedSlot()}
-- 
-- 
-- sendMessage(message, modem)
