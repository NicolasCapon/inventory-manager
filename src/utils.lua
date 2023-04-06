function getItemCount(item)
    local total = 0
    for _, s in ipairs(item) do
        total = total + s.slot.count
    end
    return total
end

function toNumberOrDefault(str, default)
    if pcall(tonumber, str) then
        return tonumber(str)
    else
        return default
    end
end

function string:endswith(ending)
    return ending == "" or self:sub(-#ending) == ending
end

function sendMessage(message, modem)
    local SERVER = 6 --TODO put real computer ID here
    local PROTOCOL = "INVENTORY"
    local TIMEOUT = 5

    message["from"] = modem.getNameLocal()
    rednet.send(SERVER, message, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, TIMEOUT)
    if not id then
        response = {ok=false, response={}, error="Server not responding"}
        printError(response.error)
    elseif not response.ok then
        printError(response.error)
    end
    return response
end
    
function itemInList(item, list)
    for _, value in ipairs(list) do
        if value == item then
            return true
        end
    end
    return false
end

function printColor(message, col)
    term.setTextColour(col)
    print(message)
    term.setTextColour(colors.white)
end

function printError(message)
    -- TODO: print message in red
    term.setTextColour(colors.red)
    print(message)
    term.setTextColour(colors.white)
end

function split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

function getItemsFromInventory(inventory)
    local keyset = {}
    local n = 0
    for key, value in pairs(inventory) do
        if value ~= nil then
            n = n + 1
            local s = split(key, ":")
            keyset[n] = s[2] .. ":" .. s[1]
        end
    end
    return keyset
end
