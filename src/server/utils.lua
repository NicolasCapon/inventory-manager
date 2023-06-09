local config = require("config")

local lib = {}

-- Log message to given file
function lib.log(message, filename)
    local filename = filename or LOG_FILE
    local file = fs.open(filename, "a")
    file.write(textutils.serialize(message, { compact = true }) .. "\n")
    file.close()
end

-- Read file given by path and return its content
function lib.readFile(path)
    local content
    if fs.exists(path) then
        local f = io.open(path, "r")
        if f == nil then
            content = ""
        else
            content = f:read("*all")
            f:close()
        end
    end
    return content
end

-- Send notifications to all clients for updating UI
-- TODO merge with server.lua updateClients
function lib.updateClients()
    local msg = { endpoint = "updateClients" }
    rednet.send(6, msg, config.PROTOCOLS.MAIN)
end

-- Test if item is in list
function lib.itemInList(it, list)
    if not list then return false end
    for _, o in ipairs(list) do
        if it == o then
            return true
        end
    end
end

-- Write content to file by overwritting
function lib.overwriteFile(path, content)
    local file = fs.open(path, "w")
    file.write(textutils.serialize(content, { compact = true }))
    file.close()
    return true
end

-- Return a copy of a simple table
function lib.copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[lib.copy(k)] = lib.copy(v) end
    return res
end

-- TODO merge with server utils
function lib.getItemCount(item)
    local total = 0
    for _, s in ipairs(item) do
        total = total + s.slot.count
    end
    return total
end

return lib
