local basalt = require("basalt")
local utils = require("utils")
local addJobPopUp = require("addJobPopUp")
local liveParamsPopUp = require("jobParams")
local NetworkHandler = require("network")
local config = require("config")

local ClientGUI = {}
ClientGUI.__index = ClientGUI

-- Event function handling keyboard navigation
local function navigation(self, event, key, obj)
    local focus = obj.main:getFocusedObject()
    local listIndex = obj.itemsList:getItemIndex()
    local listMax = obj.itemsList:getItemCount()
    if key == keys.tab then
        if focus == obj.countInput then
            obj.main:setFocusedObject(obj.input)
        else
            obj.main:setFocusedObject(obj.countInput)
            obj.countInput:setValue("")
        end
        return true
    elseif key == keys.enter then
        obj:getSelectedItem()
        return true
    elseif key == keys.f3 then
        obj:dump(true)
        return true
    elseif (key == keys.up and listIndex > 1) then
        listIndex = listIndex - 1
        obj.itemsList:selectItem(listIndex)
        local currentOffset = obj.itemsList:getOffset()
        if currentOffset > 0 then
            obj.itemsList:setOffset(currentOffset - 1)
        end
        return true
    elseif (key == keys.down and listIndex < listMax) then
        listIndex = listIndex + 1
        obj.itemsList:selectItem(listIndex)
        if (listIndex > 4 and listIndex < listMax) then
            obj.itemsList:setOffset(obj.itemsList:getOffset() + 1)
        end
        return true
    end
end

-- Function filtering the item list based on user input
local function getFilterListEvent(self, event, value, obj)
    local selection = self:getValue()
    if string.len(selection) > 2 then
        obj.listIsFiltered = true
        obj:updateItemsList(selection)
    elseif obj.listIsFiltered then
        obj:updateItemsList()
        obj.listIsFiltered = false
    end
    obj.itemsList:selectItem(1)
    obj.itemsList:setOffset(0)
end


-- ClientGUI constructor
function ClientGUI:new()
    local o = {}
    setmetatable(o, ClientGUI)
    o.network = NetworkHandler:new()
    o.main = basalt.createFrame():addLayout("client.xml") 
    -- o.input = o.main:getObject("input"):onKey(self.navigation)
    o.input = o.main:addInput("input"):setPosition(1,1):setSize("parent.w", 1):setBackground(colors.white)
    -- o.countInput = o.main:getObject("countInput")
    o.countInput = o.main:addInput("countInput"):setPosition("parent.w - 3", 1):setSize(4, 1):setBackground(colors.cyan)
    -- o.itemsList = o.main:getObject("itemsList")
    o.itemsList = o.main:addList("itemsList"):setPosition(1, 2):setSize("parent.w", "parent.h - 3"):setBackground(colors.pink)
    o.main:addButton("getButton"):setPosition("parent.w - 9", "parent.h - 1"):setSize(10, 1):setText("GET"):setBackground(colors.green)
    o.main:addButton("dumpButton"):setPosition("parent.w - 19", "parent.h - 1"):setSize(10, 1):setText("DUMP"):setBackground(colors.red)
    o.main:addButton("learnButton"):setPosition("parent.w - 29", "parent.h - 1"):setSize(10, 1):setText("CRAFT"):setBackground(colors.cyan)
    o.main:addButton("newJobButton"):setPosition("parent.w - 39", "parent.h - 1"):setSize(10, 1):setText("JOB"):setBackground(colors.gray)
    o.listIsFiltered = false
    o.items = {}
    o.inventory = {}
    o.recipes = {}
    o.jobs = {}
    return o
end

-- Apply all events, sync and update UI
function ClientGUI:start()
    -- Events
    local fn = function(_, _, event) navigation(_, _, event, self) end
    local fn2 = function(o, _, event) getFilterListEvent(o, _, event, self) end
    local fn3 = function(_, _, _, _, _) self:dump(true) end
    self.main:getObject("input"):onKey(fn)
                                :onChange(fn2)
    self.main:getObject("countInput"):setValue(1):onKey(fn)
    self.main:getObject("itemsList"):onKey(fn)
    self.main:getObject("getButton"):onClick(function() self:getSelectedItem()end)
    self.main:getObject("dumpButton"):onClick(fn3)
    self.main:getObject("learnButton")
        :onClick(function()
            self:craftAndLearn()
        end)
    self.main:getObject("newJobButton"):onClick(function()
        addJobPopUp.openNewJob(self)
    end)
    -- Update UI
    self.main:setFocusedObject(self.input)
    self:sync()
    self:updateItemsList()
    return basalt.autoUpdate
end

function ClientGUI:sync()
    local request = self.network:sendMessage({ endpoint = "all" })
    if request.ok then
        self.inventory = request.response.inventory
        self.recipes   = request.response.recipes
        self.jobs      = request.response.jobs
    end
    return request.ok
end

-- Reset focus and objects state, update values with server as fresh UI
function ClientGUI:resetState()
    self.input:setValue("")
    self.countInput:setValue(1)
    self.main:setFocusedObject(self.input)
    self:sync()
    self:updateItemsList()
    self.itemsList:selectItem(1)
    self.itemsList:setOffset(0)
end

-- Listen for server notification about updating inventory
function ClientGUI:listenServerUpdates()
    while true do
        local id, message = rednet.receive("NOTIFICATION")
        if id then
            if message.type == "UPDATE_UI" then
                self:updateItemsListCount(message.inventory)
            elseif message.type == "SERVER_START" then
                self:resetState()
            end
        end
    end
end

-- Update items count in itemsList
function ClientGUI:updateItemsListCount(inv)
    local itemIndex = self.itemsList:getItemIndex()
    for i, item in ipairs(self.itemsList:getAll()) do
        local targs = table.unpack(item.args)
        if targs.type == "inventory" then
            local updated = false
            for name, value in pairs(inv) do
                if targs.name == name then
                    local itname = utils.getItemCount(value) .. "\t" .. name
                    local args = { type = "inventory", name = name }
                    self.itemsList:editItem(i, itname, nil, nil, args)
                    updated = true
                end
            end
            if not updated then
                local itname = "0 \t" .. targs.name
                local args = { type = "inventory", name = targs.name }
                self.itemsList:editItem(i, itname, nil, nil, args)
            end
        end
    end
    self.itemsList:selectItem(itemIndex)
    self.inventory = inv
end

-- Update items in list based on a string filter
function ClientGUI:updateItemsList(filter)
    self.items = {}
    self.itemsList:clear()
    if filter then
        for key, value in pairs(self.inventory) do
            if string.find(key, filter) then
                table.insert(self.items, key)
                local itname = utils.getItemCount(value) .. "\t" .. key
                local args = { type = "inventory", name = key }
                self.itemsList:addItem(itname, nil, nil, args)
            end
        end
        -- Display available recipes for unavailable items
        for key, _ in pairs(self.recipes) do
            if not self.inventory[key] then
                -- Item not in inventory, display recipe instead
                if string.find(key, filter) then
                    table.insert(self.items, key)
                    local args = { type = "recipe", name = key }
                    self.itemsList:addItem("%\t" .. key, colors.purple, nil, args)
                end
            end
        end
        -- Display jobs
        for key, _ in pairs(self.jobs) do
            if string.find(key, filter) then
                table.insert(self.items, key)
                local args = { type = "job", name = key }
                self.itemsList:addItem("@\t" .. key, colors.lime, nil, args)
            end
        end
    else
        for key, value in pairs(self.inventory) do
            table.insert(self.items, key)
            local itname = utils.getItemCount(value) .. "\t" .. key
            local args = { type = "inventory", name = key }
            self.itemsList:addItem(itname, nil, nil, args)
        end
        -- Display available recipes for unavailable items
        for key, _ in pairs(self.recipes) do
            if not self.inventory[key] then
                -- Item not in inventory, display recipe instead
                table.insert(self.items, key)
                local args = { type = "recipe", name = key }
                self.itemsList:addItem("%\t" .. key, nil, nil, args)
            end
        end
        -- Display jobs
        for key, _ in pairs(self.jobs) do
            table.insert(self.items, key)
            local args = { type = "job", name = key }
            self.itemsList:addItem("@\t" .. key, colors.lime, nil, args)
        end
    end
end

-- Event function handling get item or job
function ClientGUI:getSelectedItem()
    local index = self.itemsList:getItemIndex()
    local selectedItem = self.items[index]
    local count = tonumber(self.countInput:getValue())
    if not self.itemsList:getItem(index) then
        return false
    end
    local selectedItemText = self.itemsList:getItem(index).text
    if utils.isRecipe(selectedItemText) then
        self:craftRecursive(selectedItem, count)
    elseif utils.isJob(selectedItemText) then
        local job = self.jobs[selectedItem]
        if liveParamsPopUp.getLiveParams(job, count, self) then
            self.main:getObject("popup"):setFocus()
                :getObject("focus"):setFocus()
            return true -- Dont update and dont set focus to main frame
        else
            local message = {
                endpoint = "execJob",
                job = selectedItem,
                count = count
            }
            if not self.network:sendMessage(message).ok then
                return false
            end
        end
    else
        local req = self:getOrCraft(selectedItem, count)
        if not req.ok then
            return false
        end
    end
    -- Reset position and values
    self.network:broadcastUpdate()
    self:resetState()
end

function ClientGUI:dump(update)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i, true)
        if item ~= nil then
            local message = { endpoint = "put", item = item, slot = i }
            local request = self.network:sendMessage(message)
            if not request.ok then
                utils.log(request.error)
                local error = "Dump failed: " .. request.error
                return { ok = false, message = request.message, error = error }
            end
        end
    end
    if update then
        -- Avoid calling this when using this function without handler
        self.network:broadcastUpdate()
        self:resetState()
    end
    return { ok = true, message = "dump", error = "" }
end

-- Get given item to destination, if not enough items are available, try to
-- craft them
function ClientGUI:getOrCraft(name, count)
    local maxCount = utils.getItemCount(self.inventory[name])
    if count > maxCount then
        -- if we need more than what's in inventoru, try to craft first if there
        -- is a recipe for this item
        local recipeCount = count - maxCount
        if recipeCount > 64 then
            -- Cap the max to 64
            recipeCount = 64
        end
        if self.recipes[name] then
            if not self:craftRecursive(name, recipeCount) then
                -- If we cannot craft then only give what's in inventory
                count = maxCount
            else
                self:dump()
            end
        else
            -- No recipe for this item, only give what's in inventory
            count = maxCount
        end
    end
    local msg = { item = name, endpoint = "get", count = count }
    return self.network:sendMessage(msg)
end

-- Craft a recipe given by its name X times on given crafty turtle
-- Handle inner crafts
function ClientGUI:craftRecursive(name, count)
    local givenRecipes = self.recipes[name]
    if not givenRecipes then
        local err = "Recipe not found: " .. name
        utils.log(err)
        return { ok = false, response = "craft", error = err }
    end
    local foundRecipe
    local dependencies
    local missing = {}
    -- Find first recipe available
    for _, recipe in ipairs(givenRecipes) do
        -- For recipe producing more than one, adjust count to avoid overproducing
        count = math.ceil(count / recipe.count)
        local msg = { endpoint = "available", recipe = recipe, count = count }
        local request = self.network:sendMessage(msg, true)
        if request.ok then
            foundRecipe = recipe
            dependencies = request.response.dependencies
            break
        else
            table.insert(missing, request.error)
        end
    end
    if not foundRecipe then
        local err = "Missing items: (click)\n" .. textutils.serialize(missing)
        utils.log(err)
        return { ok = false, response = name, error = err }
    end
    -- For the found recipe, use dependencies tree to craft smartly
    local deplvl = dependencies["maxlvl"]
    while deplvl > 0 do
        for dependency, value in pairs(dependencies) do
            -- Avoid maxlvl entry
            if dependency ~= "maxlvl" then
                if value.lvl == deplvl then
                    local req = self:craft(value.recipe, value.count)
                    if not req.ok then
                        return req
                    end
                end
            end
        end
        deplvl = deplvl - 1
    end
    -- finally craft the requested recipe
    local req = self:craft(foundRecipe, count)
    self.network:broadcastUpdate()
    return req
end

function ClientGUI:craft(recipe, count)
    -- Make room first
    local request = self:dump()
    if not request.ok then
        return request
    end
    -- Get all items
    local fns = {}
    -- For speed purpose, construct table for executing get in parallel
    for _, item in ipairs(recipe.items) do
        turtle.select(item.slot)
        local total = item.count * count
        local slot = turtle.getSelectedSlot()
        local msg = { endpoint = "get",
                      item = item.name,
                      count = total,
                      slot = turtle.getSelectedSlot() }
        local req = self.network:sendMessage(msg)
        if not req.ok then
            error = req.error
            utils.log("Error while reaching server endpoint [get] : " .. error, true)
            status = false
            return request
        end
    end
    -- Some items are not consumed after craft, move crafting result slot to
    -- an unused slot
    turtle.select(config.CRAFTING_SLOT)
    if not turtle.craft(count) then
        error = "error while crafting " .. recipe.name
        utils.log(error, true)
        return { ok = false, response = recipe, error = error }
    end
    return { ok = true, response = recipe, error = error }
end

function ClientGUI:craftAndLearn()
    local recipe = { items = {}, type = "crafting_table" }
    local fns = {}
    -- For speed purpose, construct table with functions to scan turtle
    -- crafting grid in parallel
    for i = 1, 16 do
        local fn = function()
            local item = turtle.getItemDetail(i)
            if item ~= nil then
                table.insert(recipe.items, { slot = i,
                                             name = item.name,
                                             count = item.count })
            end
        end
        table.insert(fns, fn)
    end
    local ok, err = pcall(parallel.waitForAll, table.unpack(fns))
    turtle.select(config.CRAFTING_SLOT)
    if #recipe.items > 0 and turtle.craft() then
        local item = turtle.getItemDetail(config.CRAFTING_SLOT)
        if item then
            recipe.name = item.name
            recipe.count = item.count
        end
        local msg = { endpoint = "learnRecipe", recipe = recipe }
        local req = self.network:sendMessage(msg, true)
        if req.ok then
            utils.log("You learned a new recipe.")
            self:sync()
        end
    else
        utils.log("Invalid recipe")
        return { ok = false, response = "craft&learn", error = err}
    end
end

return ClientGUI
