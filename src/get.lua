local utils = require("utils")
local completion = require "cc.completion"

local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open("bottom")

function getItemCount(item)
    local total = 0
    for _, s in ipairs(item) do
        total = total + s.slot.count
    end
    return total
end

local inventory = {}
local item = ""
local quantity = 1
-- TODO repeat this script for each endpoint
if  #arg > 2 then
    printError("Incorrect number of arguments, usage:\nget <item> <quantity>")
    return
elseif #arg == 0 then
    -- interactive prompt mode
    local history = {} -- TODO load history from file ?
    local items = {}
    local request = sendMessage({endpoint="info"}, modem)
    if request.ok then
        inventory = request.response
        items = getItemsFromInventory(inventory)
    end

    printColor("Choose item to get:", colors.lightBlue)
    item = read(nil, history, function(text) return completion.choice(text, items) end, "")
    if not itemInList(item, items) then
        printError("Item not found")
    else
        local s = split(item, ":")
        item = s[2] .. ":" .. s[1]
        local max = getItemCount(inventory[item])
        printColor("Choose quantity (max=".. max .. "):", colors.lightBlue)
        quantity = toNumberOrDefault(read(), 1)
    end
elseif #arg == 1 then
    item = arg[1]
elseif #arg == 2 then
    item = arg[1]
    quantity = toNumberOrDefault(arg[2], 1)
end

-- Send request to server
local message = {item=item, endpoint="get", count=quantity, slot=turtle.getSelectedSlot()}


sendMessage(message, modem)
