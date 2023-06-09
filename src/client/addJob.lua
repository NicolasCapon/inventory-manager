local completion = require "cc.completion"
package.path = package.path .. ';../?.lua'
local config = require("config")

local SERVER = config.SERVER_ID
local PROTOCOL = config.PROTOCOLS.MAIN
local TIMEOUT = config.TIMEOUT

local function addJob(job)
    local message = { endpoint = "addJob", job = job }
    rednet.send(SERVER, message, PROTOCOL)
    local _, response = rednet.receive(PROTOCOL, TIMEOUT)
    return response or { ok = false, error = "server unreachable" }
end

-- A JOB declaration
-- job = {name="minecraft:dark_oak_planks", tasks={}}
-- local t = {exec="sendItemToInventory", params={item="minecraft:dark_oak_planks", count=1, location="minecraft:chest_13"}}
-- table.insert(job.tasks, t)

-- a CRON declaration
-- cron = {name="minecraft:chest_13", task="listenInventory"}

local function listUnusedChests()
    local unusedChests = {}
    local message = { endpoint = "satelliteChests" }
    rednet.send(SERVER, message, PROTOCOL)
    local _, response = rednet.receive(PROTOCOL, TIMEOUT)
    if response.ok then
        for chest, _ in pairs(response.response) do
            table.insert(unusedChests, chest)
        end
    end
    return unusedChests
end

local function writeColor(text, col)
    col = col or colors.yellow
    old_color = term.getTextColor()
    term.setTextColor(col)
    write(text)
    term.setTextColor(old_color)
end

local function getServerInfos()
    local message = { endpoint = "all" }
    rednet.send(SERVER, message, PROTOCOL)
    local _, response = rednet.receive(PROTOCOL, TIMEOUT)
    if response.ok then
        return response.response
    end
end

local infos = getServerInfos()
local unusedChests = listUnusedChests()
local itemsName = {}
for key, _ in pairs(infos.inventory) do
    table.insert(itemsName, key)
end
local existingJobs = { unit = infos.jobs, cron = infos.cron }
local acceptedCronTasks = infos.acceptedTasks

local function readCronTask()
    writeColor("Choose type of task for this job (use arrow keys)\n")
    local cronTask = read(nil, nil, function(text)
        return completion.choice(text, acceptedCronTasks)
    end)
    for _, c in ipairs(acceptedCronTasks) do
        if cronTask == c then
            return cronTask
        end
    end
    return readCronTask()
end

local function readInventory()
    writeColor("choose inventory to apply this\n")
    local inv = read(nil, nil, function(text)
        return completion.choice(text, unusedChests)
    end)
    local status = false
    if inv == "*" then
        status = true
    else
        for _, chest in ipairs(unusedChests) do
            if chest == inv then
                status = true
                break
            end
        end
    end
    if not status then
        writeColor("wrong inventory name provided...\n", colors.red)
        return readInventory()
    end
    return inv
end

local function readItemName()
    writeColor("Choose item name\n")
    local it = read(nil, nil, function(text) return completion.choice(text, itemsName) end)
    local status = false
    if it == "*" then
        status = true
    else
        for _, item in ipairs(itemsName) do
            if it == item then
                status = true
                break
            end
        end
    end
    if not status then
        writeColor("wrong item name provided...\n", colors.red)
        return readItemName()
    end
    return it
end

local function readCount()
    writeColor("Choose quantity to move (default=1)\n")
    local count = read(nil, nil, nil, "1")
    return tonumber(count) or "*"
end

local function readMin()
    writeColor("Choose min quantity to keep (default=1)\n")
    local count = read(nil, nil, nil, "1")
    return tonumber(count) or 1
end

local function readFrequency()
    writeColor("Choose job frequency (default=10)\n")
    local count = read(nil, nil, nil, "10")
    return tonumber(count) or 10
end

local function readSlot(default)
    defaultstr = default or "nil"
    writeColor("Choose slot on chest (default=" .. defaultstr .. ")\n")
    local count = read(nil, nil, nil, default)
    return tonumber(count) or default
end

local function readJobName()
    writeColor("Choose name for this job:\n")
    local name = read()
    if name == "" or existingJobs.cron[name] or existingJobs.unit[name] then
        writeColor("Job with name: [" .. name .. "] is not available\n", colors.red)
        return readJobName()
    end
    return name
end

local function addTask(tasklist)
    writeColor("Choosing option for task number" .. #tasklist + 1 .. " ...\n", colors.green)
    local item = readItemName()
    local location = readInventory()
    local count = readCount()
    local slot = readSlot("1")
    if (item and location) then
        local params = { item = item, count = count, location = location, slot = slot }
        table.insert(tasklist, { exec = "sendItemToInventory", params = params })
        return true
    end
end

writeColor("Type of job to add: cron/regular\n> ")
local jobtype = read(nil, nil, function(text) return completion.choice(text, { "regular", "cron" }) end)
if jobtype ~= "cron" then jobtype = "regular" end

if jobtype == "regular" then
    -- TODO: if no chest available display message
    -- Regular job
    local job = { name = readJobName(), tasks = {}, type = "unit" }
    if not addTask(job["tasks"]) then return false end
    writeColor("Would you like to add another task ? [y/n]\n")
    local more = read(nil, nil, nil, "n")
    while more == "y" do
        if not addTask(job["tasks"]) then return false end
        writeColor("Would you like to add another task ? [y/n]\n")
        more = read(nil, nil, nil, "n")
    end
    local resp = addJob(job)
    if resp.ok then
        writeColor("Successfully added job\n", colors.green)
    else
        writeColor(resp.error .. "\n")
    end
    os.sleep(2)
else
    -- Cron job
    local job = { name = readJobName(), tasks = {}, type = "cron" }
    local inv = readInventory()
    if not inv then
        writeColor("Wrong inventory name\n", colors.red)
        return false
    end
    local exec = readCronTask()
    local min, item
    if exec == "keepMinItemInSlot" then
        min = readMin()
        item = readItemName()
    end
    local slot = readSlot()
    local freq = readFrequency()
    local params = { location = inv, slot = slot, min = min, item = item }
    table.insert(job.tasks, { exec = exec, params = params, freq = freq })
    -- TODO add multiple tasks features for cron jobs
    local resp = addJob(job)
    if resp.ok then
        writeColor("Successfully added cron job", colors.green)
        os.sleep(2)
    else
        writeColor(resp.error .. "\n")
    end
end
