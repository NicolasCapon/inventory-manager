local basalt = require("basalt")

local lib = {}

-- Check if given title correspond to a recipe
function lib.isRecipe(name)
    return string.sub(name, 1, 1) == "%"
end

-- Check if given title correspond to a job
function lib.isJob(name)
    return string.sub(name, 1, 1) == "@"
end

function lib.log(message, keep)
    if not keep then basalt.debugList:clear() end
    basalt.debug(textutils.serialize(message))
end

-- TODO merge with server utils
function lib.getItemCount(item)
    local total = 0
    for _, s in ipairs(item) do
        total = total + s.slot.count
    end
    return total
end

-- TODO remove ?
function lib.checkForEmptySlots()
    for i = 1, 16 do
        if turtle.getItemDetail(i) ~= nil then
            lib.log("Remove items in turtle inventory first (use command dump)")
            return false
        end
    end
    return true
end

return lib
