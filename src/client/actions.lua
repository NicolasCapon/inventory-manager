local utils = require("utils")
local config = require("config")

local ServerActions = {}
ServerActions.__index = ServerActions

-- ServerActions constructor
function ServerActions:new(network)
    local o = {}
    setmetatable(o, ServerActions)
    o.network = network
    return o
end

-- Dump all turtle items to main inventory
function ServerActions:dump()
    for i = 1, 16 do
        local item = turtle.getItemDetail(i, true)
        if item ~= nil then
            local message = { endpoint = "put", item = item, slot = i }
            local request = self.network:sendMessage(message)
            if not request.ok then
                utils.log(request.error)
                local error = "Dump failed: " .. request.error
                return { ok = false, message = request.message, error = error }
            end
        end
    end
    return { ok = true, message = "dump", error = "" }
end

-- Get given item to destination, if not enough items are available, try to
-- craft them
function ServerActions:getOrCraft(name, count, inventory, recipes)
    local maxCount = utils.getItemCount(inventory[name])
    if count > maxCount then
        -- if we need more than what's in inventoru, try to craft first if there
        -- is a recipe for this item
        local recipeCount = count - maxCount
        if recipes[name] then
            if not self:craftRecursive(name, recipeCount, recipes) then
                -- If we cannot craft then only give what's in inventory
                count = maxCount
            else
                -- Dump freshly crafted items before returning the proper amount
                self:dump()
            end
        else
            -- No recipe for this item, only give what's in inventory
            count = maxCount
        end
    end
    local msg = { item = name, endpoint = "get", count = count }
    return self.network:sendMessage(msg)
end

-- Craft a recipe given by its name X times on given crafty turtle
-- Handle inner crafts
-- If not enough items, it does not craft at all
function ServerActions:craftRecursive(name, count, recipes)
    local givenRecipes = recipes[name]
    if not givenRecipes then
        local err = "Recipe not found: " .. name
        utils.log(err)
        return { ok = false, response = "craft", error = err }
    end
    local foundRecipe
    local dependencies
    local missing = {}
    -- Find first recipe available
    for _, recipe in ipairs(givenRecipes) do
        -- For recipe producing more than one item,
        -- adjust count to avoid overproducing
        count = math.ceil(count / recipe.count)
        local msg = { endpoint = "available", recipe = recipe, count = count }
        local request = self.network:sendMessage(msg, true)
        if request.ok then
            foundRecipe = recipe
            dependencies = request.response.dependencies
            break
        else
            table.insert(missing, request.error)
        end
    end
    if not foundRecipe then
        local err = "Missing items: (click)\n" .. textutils.serialize(missing)
        utils.log(err)
        return { ok = false, response = name, error = err }
    end
    -- For the found recipe, use dependencies tree to craft smartly
    local deplvl = dependencies["maxlvl"]
    while deplvl > 0 do
        for dependency, value in pairs(dependencies) do
            -- Avoid maxlvl entry
            if dependency ~= "maxlvl" then
                if value.lvl == deplvl then
                    local req = self:smartCraft(value.recipe, value.count)
                    if not req.ok then
                        return req
                    end
                end
            end
        end
        deplvl = deplvl - 1
    end
    -- finally craft the requested recipe
    local req = self:smartCraft(foundRecipe, count)
    return req
end

-- Create batch of crafts when we want to craft multiple items exceeding per
-- slot count limit
function ServerActions:smartCraft(recipe, count)
    local status = true
    local min = 64 -- default maximum item amount per slot
    -- Find min item.maxCount in recipe items
    for _, item in ipairs(recipe.items) do
        if item.maxCount and item.maxCount < min then
            min = item.maxCount
        end
    end
    if count > min then
        local div = math.floor(count / min)
        local res = count % min
        for _ = 1, div do
            local req =self:craft(recipe, min)
            if not req.ok then
                return req
            end
        end
        local req = self:craft(recipe, res)
        if not req.ok then return req end
    else
        return self:craft(recipe, count)
    end
end

-- Craft given recipe X times
function ServerActions:craft(recipe, count)
    -- Make room first
    local request = self:dump()
    if not request.ok then
        return request
    end
    -- Get all items
    for _, item in ipairs(recipe.items) do
        turtle.select(item.slot)
        local total = item.count * count
        local msg = {
            endpoint = "get",
            item = item.name,
            count = total,
            slot = turtle.getSelectedSlot()
        }
        local req = self.network:sendMessage(msg)
        if not req.ok then
            error = req.error
            utils.log("Error on server endpoint [get] : " .. error, true)
            return request
        end
    end
    -- Some items are not consumed after craft, move crafting result slot to
    -- an unused slot
    turtle.select(config.CRAFTING_SLOT)
    if not turtle.craft(count) then
        error = "error while crafting " .. recipe.name
        utils.log(error, true)
        return { ok = false, response = recipe, error = error }
    end
    return { ok = true, response = recipe, error = error }
end

-- Try crafting using items in turtle inventory, if recipe is new add it to
-- recipe list on server side
function ServerActions:craftAndLearn()
    local recipe = { items = {}, type = "crafting_table" }
    local fns = {}
    -- For speed purpose, construct table with functions to scan turtle
    -- crafting grid in parallel
    for i = 1, 16 do
        local fn = function()
            local item = turtle.getItemDetail(i, true)
            if item ~= nil then
                table.insert(recipe.items, {
                    slot = i,
                    name = item.name,
                    count = item.count,
                    maxCount = item.maxCount
                })
            end
        end
        table.insert(fns, fn)
    end
    local ok, err = pcall(parallel.waitForAll, table.unpack(fns))
    if not ok then
        return { ok = false, response = "craft&learn", error = err }
    end
    turtle.select(config.CRAFTING_SLOT)
    if #recipe.items > 0 and turtle.craft() then
        local item = turtle.getItemDetail(config.CRAFTING_SLOT)
        if item then
            recipe.name = item.name
            recipe.count = item.count
        end
        local msg = { endpoint = "learnRecipe", recipe = recipe }
        local req = self.network:sendMessage(msg, true)
        if req.ok then
            utils.log("You learned a new recipe.")
        end
        return { ok = req.ok, response = "craft&learn", error = req.error }
    else
        utils.log("Invalid recipe")
        return { ok = false, response = "craft&learn", error = err }
    end
end

return ServerActions
