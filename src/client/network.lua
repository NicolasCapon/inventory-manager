local config = require("config")
local utils = require("utils")

local NetworkHandler = {}
NetworkHandler.__index = NetworkHandler

-- NetworkHandler constructor
function NetworkHandler:new()
    local o = {}
    setmetatable(o, NetworkHandler)
    o.modem = peripheral.find("modem") or error("No modem attached", 0)
    peripheral.find("modem", rednet.open)
    return o
end

-- Send message to server and handle server response
function NetworkHandler:sendMessage(msg, ignoreErrors)
    msg.from = self.modem.getNameLocal()
    rednet.send(config.SERVER_ID, msg, config.PROTOCOLS.MAIN)
    local id, response = rednet.receive(config.PROTOCOLS.MAIN)--, config.TIMEOUT)
    if not id then
        response = { ok = false, response = {}, error = "Server unreachable" }
        utils.log(response.error, true)
    elseif not response.ok and not ignoreErrors then
        local error = string.format("Error on server endpoint %s", msg.endpoint)
        utils.log(error, true)
        utils.log(response.error, true)
    end
    return response
end

-- Notify all clients that we update inventory
function NetworkHandler:broadcastUpdate()
    return self:sendMessage({ endpoint = "updateClients" })
end

return NetworkHandler
