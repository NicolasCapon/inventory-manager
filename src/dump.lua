local utils = require("utils")
local completion = require "cc.completion"

local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open("bottom")

function dump()
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
    return {ok=true, message="dump", error=""}
end

dump()
