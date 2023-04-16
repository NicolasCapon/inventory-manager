local completion = require "cc.completion"
local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open("right")

local SERVER = 6
local PROTOCOL = "INVENTORY"
local TIMEOUT = 5

function execJob(job, count)
    local message = {endpoint="execJob", job=job, count=count}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    return response
end

function addJob(job)
    local message = {endpoint="addJob", job=job}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    return response
end

function addCronJob(job)
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

function getExistingJobs()
    local existingJobs = {}
    local message = {endpoint="jobs"}
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    if response.ok then
        existingJobs = response.response
    end
    return existingJobs
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

function writeColor(text, col)
    col = col or colors.yellow
    old_color = term.getTextColor()
    term.setTextColor(col)
    write(text)
    term.setTextColor(old_color)
end

local unusedChests = listUnusedChests()
local itemsName = getItemsName()
local existingJobs = getExistingJobs()

function readInventory()
    writeColor("choose inventory to apply this\n")
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
        return status
    end
    return inv
end

function readItemName()
    writeColor("Choose item name\n")
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
        return status
    end
    return it
end

function readCount()
    writeColor("Choose quantity to move (default=1)\n")
    local count = read(nil, nil, nil, "1")
    return tonumber(count) or 1
end

function readJobName()
    writeColor("Choose name for this job:\n")
    local name = read(nil, nil, function(text) return completion.choice(text, itemsName) end)
    if name == "" or existingJobs[name] then
        writeColor("Job with name: [" .. name .. "] is not available\n", colors.red)
        return readJobName()
    end
    return name
end

function addTask(tasklist)
    writeColor("Choosing option for task number" .. #tasklist + 1 .. " ...\n", colors.green)
    local item = readItemName()
    local location = readInventory()
    local count = readCount()
    if (item and location) then
        local params = {item=item, count=count, location=location}
        table.insert(tasklist, {exec="sendItemToInventory", params=params}) 
        return true
    end
end

writeColor("Type of job to add: cron/regular [c/r]\n> ")
local jobtype = read(nil, nil, nil, "r")
if jobtype ~= "c" then jobtype = "r" end

if jobtype == "r" then
    -- Regular job
    local job = {name=readJobName(), tasks={}}
    if not addTask(job["tasks"]) then return false end
    writeColor("Would you like to add another task ? [y/n]\n")
    local more = read(nil, nil, nil, "n")
    while more == "y" do
        if not addTask(job["tasks"]) then return false end
    end
    local resp = addJob(job)
    if resp.ok then
        writeColor("Successfully added job", colors.green)
    else
        writeColor(resp.error .. "\n")
    end
else
    -- Cron job
    local inv = readInventory()
    if not inv then 
        writeColor("Wrong inventory name\n", colors.red)
        return false
    end
    local job = {name=inv, task="listenInventory"}
    local resp = addCronJob(job)
    if resp.ok then
        writeColor("Successfully added cron job", colors.green)
    else
        writeColor(resp.error .. "\n")
    end
end