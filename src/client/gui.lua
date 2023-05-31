local basalt = require("basalt")
local utils = require("utils")
local addJobPopUp = require("addJobPopUp")
local liveParamsPopUp = require("liveParamsPopup")
local NetworkHandler = require("network")

local ClientGUI = {}
ClientGUI.__index = ClientGUI

-- ClientGUI constructor
function ClientGUI:new()
    local o = {}
    setmetatable(o, ClientGUI)
    o.network = NetworkHandler:new()
    o.main = basalt.createFrame():addLayout("client.xml")
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
    -- Events
    self:getObject("input"):onKey(self.navigation)
        :onChange(self:getFilterListEvent())
    self:getObject("countInput"):setValue(1):onKey(self.navigation)
    self:getObject("itemsList"):onKey(self.navigation)
    self:getObject("getButton"):onClick(self.getSelectedItem)
    self:getObject("dumpButton"):onClick(self.getDumpEvent)
    self:getObject("learnButton")
        :onClick(function()
            self.network:sendMessage({ endpoint = "craftAndLearn" })
        end)
    self:getObject("newJobButton"):onClick(function()
        addJobPopUp.openNewJob(self)
    end)
    -- Update UI
    self:setFocusedObject(self.input)
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
        for key, _ in pairs(jobs) do
            if string.find(key, filter) then
                table.insert(self.items, key)
                local args = { type = "job", name = key }
                self.itemsList:addItem("@\t" .. key, colors.lime, nil, args)
            end
        end
    else
        for key, value in pairs(inv) do
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

-- Function returning a event function for filtering the item list based on
-- user input
function ClientGUI:getFilterListEvent()
    return function(obj)
        local selection = obj:getValue()
        if string.len(selection) > 2 then
            self.listIsFiltered = true
            self.updateItemsList(self.inventory, selection)
        elseif self.listIsFiltered then
            self.updateItemsList(self.inventory)
            self.listIsFiltered = false
        end
        self.itemsList:selectItem(1)
        self.itemsList:setOffset(0)
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
        self.network:sendMessage({
            endpoint = "craftRecursive",
            item = selectedItem,
            count = count
        })
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
            if not self.network.sendMessage(message, self.modem).ok then
                return false
            end
        end
    else
        local req = self.network.sendMessage({
            endpoint = "getOrCraft",
            item = selectedItem,
            count = count
        })
        if not req.ok then
            return false
        end
    end
    -- Reset position and values
    self:resetState()
end

-- Get function for dumping client inventory
function ClientGUI:getDumpEvent()
    return function()
        self.network:sendMessage({ endpoint = "dumpTurtle" })
        self:resetState()
    end
end

-- Event function handling keyboard navigation
function ClientGUI:navigation(_, _, key)
    local focus = self.main:getFocusedObject()
    local listIndex = self.itemsList:getItemIndex()
    local listMax = self.itemsList:getItemCount()
    if key == keys.tab then
        if focus == self.countInput then
            self.main:setFocusedObject(self.input)
        else
            self.main:setFocusedObject(self.countInput)
            self.countInput:setValue("")
        end
        return true
    elseif key == keys.enter then
        self:getSelectedItem()
        return true
    elseif key == keys.f3 then
        self:getDumpEvent()()
        return true
    elseif (key == keys.up and listIndex > 1) then
        listIndex = listIndex - 1
        self.itemsList:selectItem(listIndex)
        local currentOffset = self.itemsList:getOffset()
        if currentOffset > 0 then
            self.itemsList:setOffset(currentOffset - 1)
        end
        return true
    elseif (key == keys.down and listIndex < listMax) then
        listIndex = listIndex + 1
        self.itemsList:selectItem(listIndex)
        if (listIndex > 4 and listIndex < listMax) then
            self.itemsList:setOffset(self.itemsList:getOffset() + 1)
        end
        return true
    end
end

return ClientGUI
