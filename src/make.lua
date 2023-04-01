require("utils")
require("dump")
local completion = require "cc.completion"

local modem = peripheral.find("modem") or error("No modem attached", 0)
rednet.open("bottom")

function make(recipe, recursive, count)
    -- if recursive -> getSubCrafts() else check #getMissingItems() == 0
    if recursive then 
        local dependencies = {}
        local message = {}
        local request = sendMessage({endpoint="make", recipe=recipe, count=count}, modem) 
        if request.ok then
            dependencies = request.response.dependencies
        end
        local deplvl = dependencies["maxlvl"]
        while deplvl > 0 do
            for dependency, value in pairs(dependencies) do
                -- Avoid maxlvl entry
                if dependency ~= "maxlvl" then
                    if value.lvl == deplvl then
                        craft(recipes[dependency], value.count)
                    end
                end
            end
            deplvl = deplvl - 1
        end
        craft(recipe, count)
    else
        local missingItems = getMissingItems(recipe)
        if #missingItems == 0 then
            craft(recipe, count)
        else
            printError("Missing Items: ")
            -- TODO print items missing
        end
    end
end

function getMaxCountForRecipe(recipe)
    local max = 64
    for _, item in recipe do
        local limit = turtle.getItemLimit(item.index)
        local cmax = math.modf(limit / item.count)
        if cmax < max then
            max = cmax
        end
    end
    return max
end

function craft(recipe, count)
    -- TODO check if count is not too high first ?
    -- Do items can have multiple in same slot ? if not max = 64 ?

    -- We have all dep, just craft
    local status = true
    local error = ""
    -- Make room first
    local request = dump()
    if not request.ok then
        status = false
        return request
    end
    -- Get all items
    for _, item in ipairs(recipe.items) do
        turtle.select(item.slot)
        local total = item.count * count
        local message = {endpoint="get", item=item.name, count=total, slot=turtle.getSelectedSlot()}
        request = sendMessage(message, modem)
        if not request.ok then
            error = request.error
            printError(error)
            status = false
            return request
        end
    end
    -- Some items are not consumed after craft, move crafting result slot to
    -- an unused slot
    turtle.select(4)
    if not turtle.craft(count) then
        error = "error while crafting " .. recipe.name
        printError(error)
        status = false
        return {ok=status, message=recipe, error=error}
    end
    return {ok=status, message=recipe, error=error}
end

recipes = {}
local recipesName = {}
local history = {}
local request = sendMessage({endpoint="recipes"}, modem)
if request.ok then
    recipes = request.response
    recipesName = getItemsFromInventory(recipes)
else
    return false
end
printColor("Choose a crafting recipe:", colors.lightBlue)
local recipe = read(nil, history, function(text) return completion.choice(text, recipesName) end, "")

if not itemInList(recipe, recipesName) then
    printError("Recipe not found")
    return false
else
    -- back to not normal item nomenclature
    local s = split(recipe, ":")
    recipe = s[2] .. ":" .. s[1]
    recipe = recipes[recipe]
end

-- TODO ask for count
local count = 1
-- Check if recipe if doable
local recursive = true
make(recipe, recursive, count)

-- Send request to server
-- local message = {item=item, endpoint="make", count=quantity}
-- sendMessage(message, modem)
