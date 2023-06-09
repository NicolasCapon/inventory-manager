local basalt = require("basalt")
local utils = require("utils")
local addJobPopUp = require("addJobPopUp")
local liveParamsPopUp = require("jobParams")
local NetworkHandler = require("network")
local ServerActions = require("actions")

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
        obj.actions:dump()
        obj.network:broadcastUpdate()
        obj:resetState()
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

-- Initialize and return main frame with all GUI components
local function initUI()
    local main = basalt.createFrame()
    if not main then
        error("Could not initialize main frame")
    end
    main:addInput("input")
        :setPosition(1, 1)
        :setSize("parent.w", 1)
        :setBackground(colors.white)
    main:addInput("countInput")
        :setPosition("parent.w - 3", 1)
        :setSize(4, 1)
        :setBackground(colors.cyan)
    main:addList("itemsList")
        :setPosition(1, 2)
        :setSize("parent.w", "parent.h - 3")
        :setBackground(colors.pink)
    -- Buttons
    main:addButton("getButton")
        :setPosition("parent.w - 9", "parent.h - 1")
        :setSize(10, 1)
        :setText("GET")
        :setBackground(colors.green)
    main:addButton("dumpButton")
        :setPosition("parent.w - 19", "parent.h - 1")
        :setSize(10, 1)
        :setText("DUMP")
        :setBackground(colors.red)
    main:addButton("learnButton")
        :setPosition("parent.w - 29", "parent.h - 1")
        :setSize(10, 1)
        :setText("CRAFT")
        :setBackground(colors.cyan)
    main:addButton("newJobButton")
        :setPosition("parent.w - 39", "parent.h - 1")
        :setSize(10, 1)
        :setText("JOB")
        :setBackground(colors.gray)
    return main
end

-- ClientGUI constructor
function ClientGUI:new()
    local o = {}
    setmetatable(o, ClientGUI)
    o.network = NetworkHandler:new()
    o.actions = ServerActions:new(o.network)
    o.main = initUI()
    o.input = o.main:getObject("input")
    o.countInput = o.main:getObject("countInput")
    o.itemsList = o.main:getObject("itemsList")
    o.listIsFiltered = false
    o.items = {}
    o.inventory = {}
    o.recipes = {}
    o.jobs = {}
    return o
end

-- Apply all events, sync and update UI
function ClientGUI:start()
    -- Create events
    local fn = function(_, _, event) navigation(_, _, event, self) end
    local fn2 = function(o, _, event) getFilterListEvent(o, _, event, self) end
    local fn3 = function(_, _, _, _, _)
        self.actions:dump()
        self.network:broadcastUpdate()
        self:resetState()
    end
    local fn4 = function() self:getSelectedItem() end
    local fn5 = function()
        if self.actions:craftAndLearn().ok then
            self:sync()
        end
    end
    local fn6 = function() addJobPopUp.openNewJob(self) end
    -- Set events
    self.main:getObject("input"):onKey(fn):onChange(fn2)
    self.main:getObject("countInput"):setValue(1):onKey(fn)
    self.main:getObject("itemsList"):onKey(fn)
    self.main:getObject("getButton"):onClick(fn4)
    self.main:getObject("dumpButton"):onClick(fn3)
    self.main:getObject("learnButton"):onClick(fn5)
    self.main:getObject("newJobButton"):onClick(fn6)
    -- Update UI
    self.main:setFocusedObject(self.input)
    self:sync()
    self:updateItemsList()
    return basalt.autoUpdate
end

-- Get server info to refresh all data on client
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
                    self.itemsList:addItem("%\t" .. key,
                        colors.purple,
                        nil,
                        args)
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
        self.actions:craftRecursive(selectedItem, count, self.recipes)
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
        local req = self.actions:getOrCraft(selectedItem,
                                            count,
                                            self.inventory,
                                            self.recipes)
        if not req.ok then
            return false
        end
    end
    -- Reset position and values
    self.network:broadcastUpdate()
    self:resetState()
end

return ClientGUI
