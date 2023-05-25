local Scheduler = require("scheduler")
local modem = peripheral.find("modem") or error("No modem attached", 0)
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
peripheral.find("modem", rednet.open)

RECIPES_FILE = "recipes.txt"
JOBS_FILE = "jobs.txt"

local acceptedTasks = {"listenInventory", "keepMinItemInSlot"}
local inventoryChests = {} -- Chests used for storing items
local recipes = {}
local inventory = {}
local free = {}
local ioChests = {}
local jobs = {cron={}, unit={}}
local scheduler = Scheduler:new()

function sendResponse(client, response)
    -- client, {ok, reponse, error}
    local protocol = "INVENTORY"
    rednet.send(client, response, protocol)
end

function decodeMessage(message, client)
    local response
    if message.endpoint == "get" then
        response = get(message.item, message.count, message.from, message.slot)
    elseif message.endpoint == "info" then
        progressBar("DU")
        response = {ok=true, response=inventory}
    elseif message.endpoint == "all" then
        progressBar("DU")
        response = {ok=true, response={inventory=inventory, recipes=recipes, jobs=jobs.unit, acceptedTasks=acceptedTasks, cron=jobs.cron}}
    elseif message.endpoint == "inventoryChests" then
        response = {ok=true, response=inventoryChests}
    elseif message.endpoint == "satelliteChests" then
        response = {ok=true, response=listSatelliteChests()}
    elseif message.endpoint == "put" then
        response = put(message.item, message.from, message.slot)
    elseif message.endpoint == "recipes" then
        response = {ok=true, response=recipes}
    elseif message.endpoint == "make" then
        response = getAvailability(message.recipe, message.count)
    elseif message.endpoint == "add" then
        response = saveRecipe(message.recipe)
    elseif message.endpoint == "jobs" then
        response = {ok=true, response=jobs.unit}
    elseif message.endpoint == "cronjobs" then
        response = {ok=true, response=jobs.cron}
    elseif message.endpoint == "addJob" then
        response = addJob(message.job)
    elseif message.endpoint == "removeJob" then
        response = removeJob(message.job)
    elseif message.endpoint == "execJob" then
        response = execJob(message.job, message.params, message.count)
    elseif message.endpoint == "updateClients" then
        response = updateClients()
    end
    local ok, err = pcall(sendResponse, client, response)
    if not ok then print(err) end
end

function notifyClients(type, msg)
    msg = msg or {}
    msg.type = type
    rednet.broadcast(msg, "notification")
    return { ok = true, response = msg }
end

-- Notify all client about inventory changes
function updateClients()
    local message = { inventory=inventory,
                      recipes=recipes,
                      jobs=jobs.unit,
                      acceptedTasks=acceptedTasks,
                      cron=jobs.cron }
    return notifyClients("inventory_update", message)
end

function handleRequests()
    while true do
        client, message = rednet.receive("INVENTORY")
        if client ~= nil then 
            decodeMessage(message, client)
        end
    end
end


function getInventorySlotsNumber()
    total = 0
    for key, value in pairs(inventory) do
        total = total + #value
    end
    return total
end

function progressBar(text)
    monitor.clear()
    local current = getInventorySlotsNumber()
    local max = current + #free
    local x, y = monitor.getSize()
    local ratio = (current * x) / max
    local percent = tonumber(current/max*100)
    monitor.setTextColor(colors.black)
    local barColor = nil
    if percent < 50 then
        barColor = colors.green
    elseif percent < 70 then
        barColor = colors.yellow
    elseif percent < 90 then
        barColor = colors.yellow
    else
        barColor = colors.red
    end
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
    monitor.write(text .. ": ".. math.floor((current/max*100)+0.5) .."%")
end

loadJobs()
scanAll()
loadRecipes()
progressBar("DU")
notifyClients("server_start")
print("Waiting for clients requests...")
parallel.waitForAll(handleRequests, function() scheduler:run() end)