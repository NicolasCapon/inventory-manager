local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open("right")

local SERVER = 6
local PROTOCOL = "INVENTORY"
local TIMEOUT = 5

function execJob(job, count)
    print("execJob")
    local message = {endpoint="execJob", job=job, count=count}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    return response
end

function addJob(job)
    print("addJob")
    local message = {endpoint="addJob", job=job}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    return response
end

function addCronJob(job)
    print("addCronJob")
    local message = {endpoint="addCronJob", job=job}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    return response
end

-- A JOB declaration
-- job = {name="minecraft:dark_oak_planks", tasks={}}
-- local t = {exec="sendItemToInventory", params={item="minecraft:dark_oak_planks", count=1, location="minecraft:chest_13"}}
-- table.insert(job.tasks, t)

-- a CRON declaration
-- cron = {name="minecraft:chest_13", task="listenInventory"}

function listUsedChests()
    local usedChests = {}
    local message = {endpoint="inventoryChests"}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    if response.ok then
        for _, chest in ipairs(response.response) do
            usedChests[chest] = true
        end
    end
    return usedChests
end

function listUnusedChests()
    local used = listUsedChests()
    local allc = modem.getNamesRemote()
    local unused = {}
    for _, remote in ipairs(modem.getNamesRemote()) do
        if not used[remote] then
            table.insert(unused, remote)
        end
    end
    return unused
end

function getItemsName()
    local names = {}
    local message = {endpoint="info"}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    if response.ok then
        for k, v in pairs(response.response) do
            table.insert(names, k)
        end
    end
    return names
end

local unusedChests = listUnusedChests()
local itemsName = getItemsName()
write("Type of job to add: cron/regular [c/r]\n")
local jobtype = read()
if jobtype ~= "c" then jobtype = "r" end
write("choose inventory to apply this\n")
local completion = require "cc.completion"
local inv = read(nil, nil, function(text) return completion.choice(text, unusedChests) end)
local status = false
for _, chest in ipairs(unusedChests) do
    if chest == inv then
        status = true
        break
    end
end
if not status then
    print("wrong inventory name provided...")
    return false
end
if jobtype == "r" then
    write("Choose item name\n")
    local it = read(nil, nil, function(text) return completion.choice(text, itemsName) end)
    status = false
    for _, item in ipairs(itemsName) do
        if it == item then
            status = true
            break
        end
    end
    if not status then
        print("wrong item name provided...")
        return false
    end

    local job = {name=it, tasks={}}
    local t = {exec="sendItemToInventory", params={item=it, count=1, location=inv}}
    table.insert(job.tasks, t)

    local resp = addJob(job)
    if resp.ok then
        print("Successfully added job")
    else
        print(resp.error)
    end
else
    local job = {name=inv, task=listenInventory}
    local resp = addCronJob(job)
    if resp.ok then
        print("Successfully added job")
    else
        print(resp.error)
    end
end
