local utils = require("utils")

local popup = {}

-- Verify if this job contains live parameters == "*"
-- If it contains, then pop up the right frame to handle theses params
function popup.getLiveParams(job, count, gui)
    local atLeastOne = false
    local liveParams = {}
    for _, task in ipairs(job.tasks) do
        local params = {}
        for key, value in pairs(task.params) do
            if value == "*" then
                params[key] = value
                atLeastOne = true
            end
        end
        table.insert(liveParams, params)
    end
    if atLeastOne then
        popup.invokeLiveParamsPopup(job, liveParams, count, gui)
    end
    return atLeastOne
end

-- Show a frame dynamically created to get missing liveParams for a job
function popup.invokeLiveParamsPopup(job, liveParams, count, gui)
    -- Collect all basalt object for this popup to be destroyed later on
    -- Create a UI bloc and return a function to collect item name
    local function createItemBloc(y, frame, text, focus)
        local valueObj = frame:addList():setPosition(1, y + 2)
            :setSize("parent.w", 3)
            :setBackground(colors.yellow)

        local function filter(self)
            local filterStr = self:getValue()
            if filterStr:len() > 2 then
                valueObj:clear()
                for key, _ in pairs(gui.inventory) do
                    if string.find(key, filterStr) then
                        valueObj:addItem(key)
                    end
                end
            else
                for key, _ in pairs(gui.inventory) do
                    valueObj:addItem(key)
                end
            end
        end
        frame:addLabel():setText(text):setPosition(1, y)
        y = y + 1
        if focus then focus = "focus" end
        frame:addInput(focus):setPosition(1, y)
            :setSize("parent.w", 1)
            :setBackground(colors.white)
            :onChange(filter)

        y = y + 5 -- also add +1 for valueObj that we set earlier
        for key, _ in pairs(gui.inventory) do
            valueObj:addItem(key)
        end
        local function getValue()
            return valueObj:getValue().text
        end
        return y, getValue
    end

    -- Create a UI bloc and return a function to collect item count
    local function createCntBloc(y, frame, text, focus)
        frame:addLabel():setText(text):setPosition(1, y)
        y = y + 1
        if focus then focus = "focus" end
        local valueObj = frame:addInput(focus):setInputType("number")
            :setPosition(1, y)
            :setSize("parent.w", 1)
            :setBackground(colors.white)
            :setDefaultText("1")
        y = y + 2
        local function getValue()
            return valueObj:getValue()
        end
        return y, getValue
    end

    -- Create a UI bloc and return a function to collect destination chest
    local function createLocBloc(y, frame, text, focus)
        frame:addLabel():setText(text):setPosition(1, y)
        y = y + 1
        if focus then focus = "focus" end
        local valueObj = frame:addDropdown(focus):setPosition(1, y)
            :setSize("parent.w - 1", 1)
            :setBackground(colors.white)
        -- Request chests names and add them as items to the dropDown
        local satelliteChests = {}
        local message = { endpoint = "satelliteChests" }
        local request = gui.network:sendMessage(message)
        if request.ok then
            satelliteChests = request.response
        end
        for _, chest in ipairs(satelliteChests) do
            valueObj:addItem(chest)
        end
        y = y + 2
        local function getValue()
            return valueObj:getValue()
        end
        return y, getValue()
    end

    -- Create popup frame
    local f = gui.main:addFrame("popup"):setSize("parent.w", "parent.h")
        :setScrollable()
    -- params is a list of table where each item of the list is a table of
    -- functions for collecting params of each task
    local params = {}
    local y = 1 -- store y value for dynamically construct UI
    local first = true
    for i, task in ipairs(liveParams) do
        -- dynamically construct the UI by looping through tasks
        local getValueFns = {}
        local firstParam = true
        for param, _ in pairs(task) do
            if firstParam then
                -- we need to construct this title inside the loop
                -- in case liveParams = {}
                f:addLabel():setText("Task " .. i)
                    :setPosition(1, y)
                    :setForeground(colors.orange)
                    :setSize("parent.w", 1)
                    :setBackground(colors.blue)
                y = y + 1
                firstParam = false
            end
            if param == "item" then
                y, getValueFns[param] = createItemBloc(y, f, "- Item name", first)
            elseif param == "count" then
                y, getValueFns[param] = createCntBloc(y, f, "- Item count", first)
            elseif param == "location" then
                y, getValueFns[param] = createLocBloc(y, f, "- Export to", first)
            end
            if first then first = false end -- next tasks are not the first
        end
        table.insert(params, getValueFns)
    end

    -- Button functions
    local function collectValues()
        local jobParams = {}
        -- Collect values of each UI Objects of interest
        for _, task in ipairs(params) do
            local taskParams = {}
            for p, fn in pairs(task) do
                taskParams[p] = fn()
            end
            table.insert(jobParams, taskParams)
        end
        -- Submit the job with collected live params
        local message = {
            endpoint = "execJob",
            job = job.name,
            count = count,
            params = jobParams
        }
        local request = gui.network:sendMessage(message)
        if request.ok then
            f:remove() -- We dont need the popup anymore, destroy it
        else
            utils.log(request.error)
        end
        gui.main:setFocusedObject(gui.input)
    end

    local function nav(_, _, key)
        if key == keys.enter then
            collectValues()
        end
    end
    f:getObject("focus"):onKey(nav)

    -- Finally add buttons
    f:addButton("okLive"):setText("OK")
        :setPosition("parent.w - 9", "parent.h")
        :setSize(10, 1)
        :setBackground(colors.green)
        :onClick(collectValues)
    f:addButton("cancelLive"):setText("Cancel")
        :setPosition(1, "parent.h")
        :setSize(10, 1)
        :setBackground(colors.red)
        :onClick(function() f:remove() end)
    return params
end

return popup
