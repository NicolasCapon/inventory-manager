local config = require("config")

-- Remove empty slots from inventory
local function clearInventory(input)
    local n = #input
    for i = 1, n do
        if input[i].status == "TO_REMOVE" then
            input[i] = nil
        end
    end
    local j = 0
    for i = 1, n do
        if input[i] ~= nil then
            j = j + 1
            input[j] = input[i]
        end
    end
    for i = j + 1, n do
        input[i] = nil
    end
    if not next(input) then input = nil end
    return input
end

-- create a unique identifier from given item based on name and nbt
local function scanItem(item)
    if item.nbt then
        item.name = item.name .. "@" .. item.nbt
    end
    return item
end

local InventoryHandler = {}
InventoryHandler.__index = InventoryHandler

-- InventoryHandler constructor
function InventoryHandler:new(modem)
    local o = {}
    setmetatable(o, InventoryHandler)
    o.modem = modem
    o.free = {}
    o.inventory = {}
    o.ioChests = {}
    o.inventoryChests = {}
    return o
end

-- satelliteChests are for importing/exporting items in the core inventory
-- They are mainly used by jobs
-- Call this method only after scanAll first call
function InventoryHandler:listSatelliteChests()
    local satelliteChests = {}
    for _, remote in ipairs(self.modem.getNamesRemote()) do
        if not self.inventoryChests[remote] then
            satelliteChests[remote] = true
        end
    end
    return satelliteChests
end

-- scan remote inventory and populate global inventory
function InventoryHandler:scanRemoteInventory(remote, variableLimit)
    if variableLimit == nil then variableLimit = false end
    local chest = peripheral.wrap(remote)
    for cslot = 1, chest.size() do
        local item = chest.getItemDetail(cslot)
        if item == nil then
            -- no item, add this slot to free slots
            local limit = 64
            if variableLimit then
                limit = chest.getItemLimit(cslot)
            end
            table.insert(self.free,
                {
                    chest = remote,
                    slot = { index = cslot, limit = limit }
                })
        else
            item = scanItem(item)
            local slots = self.inventory[item.name]
            if slots == nil then
                -- new item, add it and its associated slot
                self.inventory[item.name] = { {
                    chest = remote,
                    slot = {
                        index = cslot,
                        limit = item.maxCount,
                        count = item.count
                    }
                } }
            else
                -- item already listed, add this slot only
                table.insert(self.inventory[item.name],
                    {
                        chest = remote,
                        slot = {
                            index = cslot,
                            limit = item.maxCount,
                            count = item.count
                        }
                    })
            end
        end
    end
end

-- Scann all autorised chests (see config) and populate inventory
-- TODO add option to fine tune chest selection
function InventoryHandler:scanAll()
    local remotes = self.modem.getNamesRemote()
    local scans = {}
    for i, remote in pairs(remotes) do
        if (config.ALLOWED_INVENTORIES[self.modem.getTypeRemote(remote)]
                and self.ioChests[remote] == nil) then
            self.inventoryChests[remote] = true
            table.insert(scans,
                function()
                    self:scanRemoteInventory(remote, false)
                end)
        end
    end
    parallel.waitForAll(table.unpack(scans))
end

-- Move X items from inventory to given destination
function InventoryHandler:get(name, count, destination, slot)
    local item = self.inventory[name]
    if item == nil then
        local error = name .. " not found"
        return {
            ok = false,
            response = { name = name, count = count },
            error = error
        }
    else
        for i, location in ipairs(item) do
            local chest = location.chest
            local inventory_count = location.slot.count
            local left = inventory_count - count
            if left > 0 then
                -- Enough items in this slot
                local _, ret = pcall(self.modem.callRemote,
                    chest,
                    "pushItems",
                    destination,
                    location.slot.index,
                    count,
                    slot)
                -- update inventory
                self.inventory[name][i]["slot"]["count"] = inventory_count - ret
                count = count - ret
                if count == 0 then break end
            elseif left == 0 then
                -- just enough item
                local ok, ret = pcall(self.modem.callRemote,
                    chest,
                    "pushItems",
                    destination,
                    location.slot.index,
                    count,
                    slot)
                -- add free slot and remove inventory slot
                count = count - ret
                local slot_count = inventory_count - ret
                self.inventory[name][i]["slot"]["count"] = slot_count
                if slot_count == 0 then
                    table.insert(self.free, {
                        chest = chest,
                        slot = {
                            index = location.slot.index,
                            limit = location.slot.limit
                        }
                    })
                    self.inventory[name][i].status = "TO_REMOVE"
                end
                if count == 0 then break end
            else
                -- not enough items get the maximum for this slot
                -- and continue the loop
                local _, ret = pcall(self.modem.callRemote,
                    chest,
                    "pushItems",
                    destination,
                    location.slot.index,
                    inventory_count,
                    slot)
                -- add free slot, remove inventory slot and update count
                table.insert(self.free, {
                    chest = chest,
                    slot = {
                        index = location.slot.index,
                        limit = location.slot.limit
                    }
                })
                count = count - ret
                self.inventory[name][i].status = "TO_REMOVE"
            end
        end
        -- if not enough items, clear what was still extracted
        self.inventory[name] = clearInventory(self.inventory[name])
        if count > 0 then
            local error = "Not enough item " .. name ..
                " or place for it, missing " .. count
            return {
                ok = false,
                response = { name = name, count = count },
                error = error
            }
        else
            return {
                ok = true,
                response = { name = name, count = count },
                error = ""
            }
        end
    end
end

-- Put item in from destination to main inventory free slot
function InventoryHandler:put_in_free_slot(item, count, destination, slot)
    local name = item.name
    local maxCount = item.maxCount or 64
    for i, fslot in ipairs(self.free) do
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
            local ok, ret = pcall(self.modem.callRemote,
                fslot.chest,
                "pullItems",
                destination,
                slot,
                count,
                fslot.slot.index)
            if not ok then
                -- if error occurs, clean free and stop
                self.free = clearInventory(self.free) or {}
                return {
                    ok = false,
                    response = {
                        name = name,
                        count = count,
                        maxCount = maxCount,
                        destination = destination,
                        slot = slot
                    },
                    error = ret
                }
            end
            -- add item in inventory
            table.insert(self.inventory[name], {
                chest = chest,
                slot = {
                    index = fslot.slot.index,
                    limit = limit,
                    count = ret
                }
            })
            self.free[i].status = "TO_REMOVE"
            -- update free
            count = count - ret
            if count == 0 then break end
        else
            -- put exceed slot limit, put max and continue loop
            local ok, ret = pcall(self.modem.callRemote,
                chest,
                "pullItems",
                destination,
                slot,
                limit,
                fslot.slot.index)
            if not ok then
                -- if error occurs, clean free and stop
                self.free = clearInventory(self.free) or {}
                return {
                    ok = false,
                    response = {
                        name = name,
                        count = count,
                        maxCount = maxCount,
                        destination = destination,
                        slot = slot
                    },
                    error = ret
                }
            end
            -- update inventory
            table.insert(self.inventory[name], {
                chest = chest,
                slot = {
                    index = fslot.slot.index,
                    limit = limit,
                    count = ret
                }
            })
            -- remove free slot
            count = count - ret
            self.free[i].status = "TO_REMOVE"
        end
    end
    self.free = clearInventory(self.free) or {}
    if count > 0 then
        return {
            ok = false,
            response = {
                name = name,
                count = count,
                maxCount = maxCount,
                destination = destination,
                slot = slot
            },
            error = "Not enough free space"
        }
    else
        return {
            ok = true,
            response = {
                name = name,
                count = count,
                maxCount = maxCount,
                destination = destination,
                slot = slot
            }
        }
    end
end

-- Put item from destination slot to main inventory
function InventoryHandler:put(item, dest, slot)
    local name = item.name
    local count = item.count
    local maxCount = item.maxCount
    local invItem = self.inventory[name]
    if invItem == nil then
        -- if item not in inventory, fill free slots
        self.inventory[name] = {}
        return self:put_in_free_slot(item, count, dest, slot)
    else
        -- try to fill already used slots
        for i, islot in ipairs(invItem) do
            local available = islot.slot.limit - islot.slot.count
            if available > 0 then
                local left = available - count
                -- free space available in this slot
                if left > -1 then
                    -- free space for this slot is enough
                    local ok, ret = pcall(self.modem.callRemote,
                        islot.chest,
                        "pullItems",
                        dest,
                        slot,
                        count,
                        islot.slot.index)
                    if not ok then
                        -- if error occurs, stop immediately
                        return {
                            ok = false,
                            response = {
                                name = name,
                                count = count,
                                maxCount = maxCount,
                                dest = dest,
                                slot = slot
                            },
                            error = ret
                        }
                    end
                    self.inventory[name][i].slot.count = islot.slot.count + ret
                    return {
                        ok = true,
                        response = { name = name, count = count },
                        error = ""
                    }
                else
                    -- not enough space, put max and continue
                    local ok, ret = pcall(self.modem.callRemote,
                        islot.chest, "pullItems",
                        dest,
                        slot,
                        available,
                        islot.slot.index)
                    if not ok then
                        -- if error occurs, stop immediately
                        return {
                            ok = false,
                            response = {
                                name = name,
                                count = count,
                                maxCount = maxCount,
                                dest = dest,
                                slot = slot
                            },
                            error = ret
                        }
                    end
                    self.inventory[name][i].slot.count = islot.slot.count + ret
                    count = count - ret
                end
            end
        end
        if count > 0 then
            -- use free space
            return self:put_in_free_slot(item, count, dest, slot)
        end
    end
end

return InventoryHandler
