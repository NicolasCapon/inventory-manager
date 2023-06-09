package.path = package.path .. ';../?.lua'
local config = require("config")
local Scheduler = require("scheduler")
local InventoryHandler = require("inventoryHandler")
local JobHandler = require("jobHandler")
local CraftHandler = require("craftHandler")

-- Find modem attached to server
local modem = peripheral.find("modem") or error("No modem attached", 0)
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
peripheral.find("modem", rednet.open)

-- Initialize modules
local scheduler = Scheduler:new()
local inventoryHandler = InventoryHandler:new(modem)
inventoryHandler:scanAll()
local jobHandler = JobHandler:new(inventoryHandler, scheduler)
jobHandler:loadJobs()
local craftHandler = CraftHandler:new(inventoryHandler, modem)

-- Helper function for sending response to client
local function sendResponse(client, response)
    -- client, {ok, reponse, error}
    rednet.send(client, response, config.PROTOCOLS.MAIN)
end

-- Broadcast notification message to all clients
local function notifyClients(type, msg)
    msg = msg or {}
    msg.type = type
    rednet.broadcast(msg, config.PROTOCOLS.NOTIF.MAIN)
    return { ok = true, response = msg }
end

-- Notify all client about inventory changes
local function updateClients()
    local message = {
        inventory = inventoryHandler.inventory,
        recipes = craftHandler.recipes,
        jobs = jobHandler.jobs.unit,
        acceptedTasks = config.ACCEPTED_TASKS,
        cron = jobHandler.jobs.cron
    }
    return notifyClients(config.PROTOCOLS.NOTIF.UI, message)
end

-- Get number of used slots in inventory
local function getInventorySlotsNumber()
    local total = 0
    for _, value in pairs(inventoryHandler.inventory) do
        total = total + #value
    end
    return total
end

-- Display progress bar onto attached monitor
local function progressBar(text)
    monitor.clear()
    local current = getInventorySlotsNumber()
    local free = inventoryHandler.free
    local max = current + #free
    local x, _ = monitor.getSize()
    local ratio = (current * x) / max
    monitor.setTextColor(colors.black)
    monitor.setBackgroundColor(colors.red)
    local cpt = 1
    while cpt <= ratio do
        monitor.setCursorPos(cpt, 2)
        monitor.write(" ")
        cpt = cpt + 1
    end
    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.write(text .. ": " .. math.floor((current / max * 100) + 0.5) .. "%")
end

-- Return response to client depending on endpoint they requested
local function decodeMessage(message, client)
    local response
    if message.endpoint == "get" then
        response = inventoryHandler:get(message.item, message.count, message.from, message.slot)
    elseif message.endpoint == "put" then
        response = inventoryHandler:put(message.item, message.from, message.slot)
    elseif message.endpoint == "info" then
        progressBar("DU")
        response = { ok = true, response = inventoryHandler.inventory }
    elseif message.endpoint == "all" then
        progressBar("DU")
        response = {
            ok = true,
            response = {
                inventory = inventoryHandler.inventory,
                recipes = craftHandler.recipes,
                jobs = jobHandler.jobs.unit,
                acceptedTasks = config.ACCEPTED_TASKS,
                cron = jobHandler.jobs.cron
            }
        }
    elseif message.endpoint == "inventoryChests" then
        response = { ok = true, response = inventoryHandler.inventoryChests }
    elseif message.endpoint == "satelliteChests" then
        response = { ok = true, response = inventoryHandler:listSatelliteChests() }
    elseif message.endpoint == "recipes" then
        response = { ok = true, response = craftHandler.recipes }
    elseif message.endpoint == "learnRecipe" then
        response = craftHandler:saveRecipe(message.recipe)
        updateClients()
    elseif message.endpoint == "available" then
        response = craftHandler:getAvailability(message.recipe, message.count)
    elseif message.endpoint == "jobs" then
        response = { ok = true, response = jobHandler.jobs.unit }
    elseif message.endpoint == "cronjobs" then
        response = { ok = true, response = jobHandler.jobs.cron }
    elseif message.endpoint == "addJob" then
        response = jobHandler:addJob(message.job)
    elseif message.endpoint == "removeJob" then
        response = jobHandler:removeJob(message.job)
    elseif message.endpoint == "execJob" then
        response = jobHandler:execJob(message.job, message.params, message.count)
    elseif message.endpoint == "updateClients" then
        response = updateClients()
    elseif message.endpoint == "getOrCraft" then
        response = craftHandler:getOrCraft(message.item, message.count, message.from)
        updateClients()
    elseif message.endpoint == "craftRecursive" then
        response = craftHandler:craftRecursive(message.item, message.count, message.from)
        updateClients()
    elseif message.endpoint == "craftAndLearn" then
        response = craftHandler:craftAndLearn(message.from)
    elseif message.endpoint == "dumpTurtle" then
        response = inventoryHandler:dumpTurtle(message.from)
        updateClients()
    end
    local ok, err = pcall(sendResponse, client, response)
    if not ok then print(err) end
end

-- Listen for all clients requests
local function handleRequests()
    while true do
        local client, message = rednet.receive(config.PROTOCOLS.MAIN)
        if client and message then
            decodeMessage(message, client)
        end
    end
end

progressBar("DU")
notifyClients("server_start")
print("Waiting for clients requests...")
parallel.waitForAll(handleRequests, function() scheduler:run() end)
