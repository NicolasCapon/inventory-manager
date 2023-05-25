require("config")
local utils = require("utils")

local CraftHandler = {}
CraftHandler.__index = CraftHandler

-- Load recipes from file
local function loadRecipes()
    local recipes = {}
    if not fs.exists(RECIPES_FILE) then return {} end
    for line in io.lines(RECIPES_FILE) do
        local recipe = textutils.unserialize(line)
        if not recipes[recipe.name] then
            recipes[recipe.name] = {}
        end
        table.insert(recipes[recipe.name], recipe)
    end
    return recipes
end

-- Count total of an item in inventory
local function countItem(item, inventory)
    local total = 0
    if inventory[item] == nil then return 0 end
    for _, location in ipairs(inventory[item]) do
        total = total + location.slot.count
    end
    return total
end

local function addDependency(dependencies, recipe, count, lvl)
    -- add recipe lvl of dependencies and item count
    if dependencies["maxlvl"] < lvl then
        -- lvl up max lvl of dependencies if necessary
        dependencies["maxlvl"] = lvl
    end
    if dependencies[recipe.name] == nil then
        dependencies[recipe.name] = { lvl = lvl, count = count }
    else
        if dependencies[recipe.name].lvl < lvl then
            -- lvl up dependency
            dependencies[recipe.name].lvl = lvl
        end
        dependencies[recipe.name].count = dependencies[recipe.name].count + count
    end
    return dependencies
end

-- Check a recipe for missing materials and keep track of inventory lvl
local function checkMaterials(recipe, count, inventoryCount, inventory)
    local toCraft = {} -- items unavailable in inventory
    for _, item in ipairs(recipe.items) do
        -- if inventoryCount not set, initialize it to inventory lvl
        if inventoryCount[item.name] == nil then
            inventoryCount[item.name] = countItem(item.name, inventory)
        end
        local diff = (item.count * count) - inventoryCount[item.name]
        if diff > 0 then
            -- materials are missing
            inventoryCount[item.name] = 0
            if toCraft[item.name] == nil then
                toCraft[item.name] = diff
            else
                -- usefull if recipe contains multiple of the same item
                toCraft[item.name] = toCraft[item.name] + diff
            end
        else
            -- update what is left in inventory
            inventoryCount[item.name] = math.abs(diff)
        end
    end
    return inventoryCount, toCraft
end

local function removeExcessiveItems(recipe)
    local min = 64
    for _, item in ipairs(recipe.items) do
        if item.count < min then
            min = item.count
        end
        item.count = 1
    end
    recipe.count = recipe.count / min
    return recipe
end

-- CraftHandler constructor
function CraftHandler:new()
    local o = {}
    setmetatable(o, CraftHandler)
    o.recipes = loadRecipes()
    return o
end

function CraftHandler:loadRecipes()
end

function CraftHandler:saveRecipe(recipe)
    if self.recipes[recipe.name] ~= nil then
        -- recipe already exist print error
        return { ok = false, response = recipe, error = "Recipe already exists" }
    end
    -- Assume each recipe cannot contains more than one item per slot
    recipe = removeExcessiveItems(recipe)
    local file = fs.open(RECIPES_FILE, "a")
    file.write(textutils.serialize(recipe, { compact = true }) .. "\n")
    file.close()
    if not self.recipes[recipe.name] then
        self.recipes[recipe.name] = {}
    end
    table.insert(self.recipes[recipe.name], recipe)
    return { ok = true, response = recipe, error = "" }
end

function CraftHandler:createRecipe(name, turtleID)
    -- create recipe from turtle inventory and serialize it to file
    local turtle = peripheral.wrap(turtleID)
    local recipe = { name = name, items = {} }
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item ~= nil then
            table.insert(recipe["items"],
                { slot = i, name = item.name, count = item.count })
        end
    end
    self:saveRecipe(recipe)
end

-- Get if recipe can be crafted with current state of the inventory
-- Take into account inner recipes if items are missing and have a recipe
function CraftHandler:getAvailability(recipe,
                                      count,
                                      dependencies,
                                      lvl,
                                      inventoryCount,
                                      missing,
                                      ok,
                                      inventory)
    -- get recipe dependencies for crafting in the right order
    dependencies = dependencies or { maxlvl = 0 }
    -- lvl is the lvl of recursion for this recipe
    lvl = lvl or 0
    -- keep track of inventory count for items
    inventoryCount = inventoryCount or {}
    -- keep track of missing items
    missing = missing or {}
    if ok == nil then ok = true end

    -- check items for this recipe
    local inventoryCount, toCraft = checkMaterials(recipe,
        count,
        inventoryCount,
        inventory)
    lvl = lvl + 1
    for key, value in pairs(toCraft) do
        local recipeToCraft = self.recipes[key]
        if recipeToCraft ~= nil then
            local recipeFound = false
            local request
            for _, rec in ipairs(recipeToCraft) do
                -- if recipe produce more than one item, adjust number to craft
                value = math.ceil(value / rec.count) -- round up
                -- Recurse this function
                request = self:getAvailability(rec,
                    value,
                    utils.copy(dependencies),
                    lvl,
                    utils.copy(inventoryCount),
                    utils.copy(missing),
                    ok,
                    inventory)
                -- if a step fail, whole status must be false
                if request.ok then
                    recipeFound = rec
                    break
                end
            end
            if not recipeFound then
                ok = false
                -- TODO could break here ?
            end
            -- update recursive values
            inventoryCount = request.response.inventoryCount
            missing = request.response.missing
            dependencies = addDependency(request.response.dependencies,
                recipeFound,
                value,
                lvl)
        else
            -- Item is raw material without enough quantity or
            -- we dont have a recipe for it. Throw error
            ok = false
            if not missing[key] then
                missing[key] = value
            else
                missing[key] = missing[key] + value
            end
        end
    end
    return {
        ok = ok,
        response = {
            recipe = recipe,
            count = count,
            dependencies = dependencies,
            missing = missing,
            inventoryCount = inventoryCount
        },
        error = missing
    }
end

return CraftHandler
