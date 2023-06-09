local utils = require("utils")

local lib = {}

-- Regular job functions

-- Send X item from main inventory to given inventory
function lib.sendItemToInventory(...)
    -- Take table as input:
    -- {item=itemName, location=chestName, count=itemCount, slot=chestSlot}
    local args = ...
    if not args.item then return end
    if not args.location then return end
    local count = args.count or 1
    local inventoryHandler = args.inventoryHandler
    return inventoryHandler:get(args.item, count, args.location, args.slot)
end


-- Cron Job functions

-- Listen inventory for new items.
-- Suck up those items to main inventory every x seconds
function lib.listenInventory(...)
    local args = ...
    local inv = args.location
    local slot = args.slot
    local inventoryHandler = args.inventoryHandler
    local modem = inventoryHandler.modem
    if slot then
        -- If slot specified, only call put on that slot
        local ok, item = pcall(modem.callRemote, inv, "getItemDetail", slot)
        if (ok and item) then
            local request = inventoryHandler:put(item, inv, slot)
            if not request.ok then
                print("error in job listenInventory: " .. request.error)
                return request
            else
                utils.updateClients()
                return { ok = true, response = inv }
            end
        else
            return {
                ok = false,
                response = { inv = inv, slot = slot },
                error = item
            }
        end
    end
    -- Else, listen only for first slot until it encounter an empty slot
    local n = 1
    local ok, item = pcall(modem.callRemote, inv, "getItemDetail", n)
    -- TODO: add log when pcall catch an error
    while (ok and item) do
        local request = inventoryHandler:put(item, inv, n)
        if not request.ok then
            return request
        end
        n = n + 1
        ok, item = pcall(modem.callRemote, inv, "getItemDetail", n)
    end
    utils.updateClients()
    return { ok = true, response = inv }
end

-- Keep a minimum amount of item in given inventory (ex: 1 minecraft:coal)
function lib.keepMinItemInSlot(...)
    local args = ...
    local inv = args.location
    local slot = args.slot or 1
    local min = args.min or 1
    local itName = args.item
    local inventoryHandler = args.inventoryHandler
    local modem = inventoryHandler.modem
    local ok, item = pcall(modem.callRemote, inv, "getItemDetail", slot)
    if ok then
        if not item then
            local req = inventoryHandler:get(itName, min, inv, slot)
            if not req.ok then
                return req
            else
                utils.updateClients()
                return { ok = true, response = args }
            end
        elseif item.count < min then
            local diff = min - item.count
            local req = inventoryHandler:get(itName, diff, inv, slot)
            if not req.ok then
                return req
            else
                utils.updateClients()
                return { ok = true, response = args }
            end
        end
    end
end

return lib
