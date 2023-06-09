local config = require("config")
local utils = require("utils")
local jobsLib = require("jobs")

-- Unserialize jobs from file if possible else returns empty job list
local function loadJobsFromFile(filename)
    local content = utils.readFile(filename)
    local jobs = { cron = {}, unit = {} }
    if utils.readFile(filename) then
        jobs = textutils.unserialize(content)
    end
    return jobs
end

local JobHandler = {}
JobHandler.__index = JobHandler

-- JobHandler constructor
function JobHandler:new(inventoryHandler, scheduler)
    local o = {}
    setmetatable(o, JobHandler)
    o.inventoryHandler = inventoryHandler
    o.ioChests = inventoryHandler.ioChests
    o.scheduler = scheduler
    o.jobs = loadJobsFromFile(config.JOBS_FILE)
    return o
end

-- Add cron job to scheduler to be executed periodically
function JobHandler:addToScheduler(job)
    local tasks = {
        listenInventory = jobsLib.listenInventory,
        keepMinItemInSlot = jobsLib.keepMinItemInSlot
    }
    for _, task in ipairs(job.tasks) do
        if utils.itemInList(task.exec, config.ACCEPTED_TASKS) then
            task.params.inventoryHandler = self.inventoryHandler
            local fn = function()
                while true do
                    tasks[task.exec](task.params)
                    os.sleep(task.freq)
                end
            end
            self.scheduler:addTask(fn, job.name)
        end
    end
end

-- Remove job from list and scheduler
-- TODO rewrite serialized file
function JobHandler:removeJob(job)
    if job.type == "cron" then
        self.scheduler:removeTasksByName(job.name)
    end
    self.jobs[job.type][job.name] = nil
    return {
        ok = utils.overwriteFile(config.JOBS_FILE, self.jobs),
        response = job,
        error = "Cannot write to file"
    }
end

-- Load all jobs from serialized file
function JobHandler:loadJobs()
    -- Add to scheduler all cron and List chests used by jobs to avoid using
    -- them on scanAll
    for jobType, jobList in pairs(self.jobs) do -- For each type of job
        for _, job in pairs(jobList) do         -- For each job of this type
            if jobType == "cron" then
                self:addToScheduler(job)
            end
            for _, task in ipairs(job.tasks) do -- For each task for this job
                self.ioChests[task.params.location] = true
            end
        end
    end
end

-- Add job to job list if not already registered
function JobHandler:addJob(job)
    local response
    if not self.jobs[job.type][job.name] then
        self.jobs[job.type][job.name] = job
        utils.overwriteFile(config.JOBS_FILE, self.jobs) -- Write down that job
        if job.type == "cron" then
            self:addToScheduler(job)
        end
        response = { ok = true, response = job }
    else
        response = {
            ok = false,
            response = job,
            error = "Job with same name exists"
        }
    end
    return response
end

-- Execute all tasks of given job, if n then multiply count for each tasks by n
-- liveParams override parameters for the tasks if provided. This param should
-- be a list of table with same length as job.tasks
function JobHandler:execJob(name, liveParams, n)
    if not self.jobs.unit[name] then
        return { ok = false, error = "No job for name: " .. name }
    end
    local job = self.jobs.unit[name]
    -- set defaults
    liveParams = liveParams or { {} } -- List of table
    n = n or 1
    local status = true
    local error = ""
    -- Exec each task for given job
    for i, task in ipairs(job.tasks) do
        local p = utils.copy(task["params"])
        -- Override with liveParams if not nil
        liveParams[i] = liveParams[i] or {} -- Default to empty table {}
        for key, value in pairs(liveParams[i]) do
            p[key] = value
        end
        -- Apply multiplier if we need to execJob n times (default=1)
        p.count = tonumber(p.count) or 1
        p.count = p.count * n
        p.inventoryHandler = self.inventoryHandler
        if task.exec == "sendItemToInventory" then
            local request = jobsLib.sendItemToInventory(p)
            if request and not request.ok then
                status = false
                error = error .. "[" .. request.error .. "] "
            end
        end
    end
    utils.updateClients()
    return {
        ok = status,
        response = { job = job },
        error = error
    }
end

return JobHandler
