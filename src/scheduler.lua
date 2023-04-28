local Scheduler = {tasks = {}}

function Scheduler:new(obj, tasks)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    self.tasks = tasks or {}
    return obj
end

function Scheduler:addTask(task, name)
    if type(task.exec) ~= "function" then
        error("bad argument, function expected, got " .. type(task.exec) .. ")", 3)
    else
        local t = 
        table.insert(self.tasks, {name=name,
                                  routine=coroutine.create(task.exec)})
        os.queueEvent("new task")
        return true
    end
end

function Scheduler:removeTasksByName(name)
    for i, task in ipairs(self.tasks) do
        if task.name == name then
            self.tasks[i] = nil
        end
    end
end

function Scheduler:run()
    local count = #self.tasks
    local tFilters = {}
    local eventData = { n = 0 }
    while true do
        if #self.tasks == 0 then
            -- If no task planned, wait for new task before continuing the loop
            os.pullEvent("new task")
        end
        for n = 1, count do
            local r = self.tasks[n].routine
            if r then
                if tFilters[r] == nil or tFilters[r] == eventData[1] or eventData[1] == "terminate" then
                    local ok, param = coroutine.resume(r, table.unpack(eventData, 1, eventData.n))
                    if not ok then
                        error(param, 0)
                    else
                        tFilters[r] = param
                    end
                    if coroutine.status(r) == "dead" then
                        self.tasks[n] = nil
                    end
                end
            end
        end
        for n = 1, count do
            local r = self.tasks[n].routine
            if r and coroutine.status(r) == "dead" then
                self.tasks[n] = nil
            end
        end
        eventData = table.pack(os.pullEventRaw())
    end
end

return Scheduler
