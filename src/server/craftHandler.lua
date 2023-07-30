local config = require("config")
local utils = require("utils")

local CraftHandler = {}
CraftHandler.__index = CraftHandler

-- In case of bulk crafting, remove excess items from recipe
local function removeExcessiveItems(recipe)
    local min = 64
    for _, item in ipairs(recipe.items) do
        if item.count < min then
            min = item.count
        end
        -- Assume a recipe cannot contains more than 1 item per slot
        item.count = 1
    end
    -- Recipe output can contains more than one items, divide this by
    -- previously calculated minimum
    recipe.count = recipe.count / min
    return recipe
end

-- Load recipes from file
local function loadRecipes()
    local recipes = {}
    local idCount = 1
    if not fs.exists(config.RECIPES_FILE) then return {}, 1 end
    for line in io.lines(config.RECIPES_FILE) do
        local recipe = textutils.unserialize(line)
        if not recipes[recipe.name] then
            recipes[recipe.name] = {}
        end
        table.insert(recipes[recipe.name], recipe)
        idCount = idCount + 1
    end
    return recipes, idCount
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

-- Add recipe lvl of dependencies and item count
local function addDependency(dependencies, recipe, count, lvl)
    -- TODO for jobs: add type key (craft|job) for each dependency
    -- use type_id as key for dependencies table
    -- modify client craftRecursive function accordingly
    if dependencies["maxlvl"] < lvl then
        -- lvl up max lvl of dependencies if necessary
        dependencies["maxlvl"] = lvl
    end
    if dependencies[recipe.id] == nil then
        dependencies[recipe.id] = { lvl = lvl, count = count, recipe = recipe }
    else
        if dependencies[recipe.id].lvl < lvl then
            -- lvl up dependency
            dependencies[recipe.id].lvl = lvl
        end
        dependencies[recipe.id].count = dependencies[recipe.id].count + count
    end
    return dependencies
end

-- Check a recipe for missing materials and keep track of inventory lvl with
-- var inventoryCount
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
                -- item never encountered
                toCraft[item.name] = diff
            else
                -- item already encountered, update missing count
                toCraft[item.name] = toCraft[item.name] + diff
            end
        else
            -- update what is left in inventory
            inventoryCount[item.name] = math.abs(diff)
        end
    end
    return inventoryCount, toCraft
end

local function getItemCount(recipe)
    total = {}
    for _, item in ipairs(recipe.items) do
        if total[item.name] then
            total[item.name] = total[item.name] + item.count
        else
            total[item.name] = item.count
        end
    end
    return total
end

-- Compare inputs and output of 2 recipes to tell if they are the same
-- return either true or false
local function recipeIsSame(rec1, rec2)
    local same = true
    if rec1.name == rec2.name then
        -- If rec1 and rec2 have same output, compare inputs
        local totalRec1 = getItemCount(rec1)
        local totalRec2 = getItemCount(rec2)
        for item, count in pairs(totalRec1) do
            if totalRec2[item] then
                if totalRec2[item] ~= count then
                    same = false
                end
            end
        end
    end
    return same
end

-- CraftHandler constructor
function CraftHandler:new(inventoryHandler, modem)
    local o = {}
    setmetatable(o, CraftHandler)
    o.modem = modem
    o.recipes, o.idCount = loadRecipes()
    o.inventoryHandler = inventoryHandler
    o.inventory = inventoryHandler.inventory
return o
end


function CraftHandler:saveRecipe(recipe)
    -- Test if recipe already exists
    recipe = removeExcessiveItems(recipe)
    if self.recipes[recipe.name] then
        for _, r in ipairs(self.recipes[recipe.name]) do
            if recipeIsSame(recipe, r) then
                return { ok = false,
                         response = recipe,
                         error = "Recipe already exists" }
            end
        end
    end
    recipe.id = self.idCount
    self.idCount = self.idCount + 1
    local file = fs.open(config.RECIPES_FILE, "a")
    file.write(textutils.serialize(recipe, { compact = true }) .. "\n")
    file.close()
    if not self.recipes[recipe.name] then
        self.recipes[recipe.name] = {}
    end
    table.insert(self.recipes[recipe.name], recipe)
    return { ok = true, response = recipe, error = "" }
end

-- Get if recipe can be crafted with current state of the inventory
-- Take into account inner recipes if items are missing and have a recipe
function CraftHandler:getAvailability(recipe,
                                      count,
                                      dependencies,
                                      lvl,
                                      inventoryCount,
                                      missing,
                                      inventory,
                                      encountered)
    -- Keep track of encountered recipe to avoid infinite recursion
    encountered = encountered or {}
    encountered[recipe.name] = true
    -- get recipe dependencies for crafting in the right order
    dependencies = dependencies or { maxlvl = 0 }
    -- lvl is the lvl of recursion for this recipe
    lvl = lvl or 0
    -- keep track of inventory count for items
    inventoryCount = inventoryCount or {}
    -- keep track of missing items
    missing = missing or {}
    local ok = true

    -- check items for this recipe
    local inventoryCount, toCraft = checkMaterials(recipe,
        count,
        inventoryCount,
        self.inventory)
    lvl = lvl + 1
    for name, rCount in pairs(toCraft) do
        local recipeToCraft = self.recipes[name]
        if recipeToCraft ~= nil and not encountered[name] then
            encountered[name] = true
            local recipeFound = false
            local request
            for _, rec in ipairs(recipeToCraft) do
                -- if recipe produce more than one item, adjust number to craft
                rCount = math.ceil(rCount / rec.count) -- round up
                -- Recurse this function
                request = self:getAvailability(rec,
                    rCount,
                    dependencies,
                    lvl,
                    inventoryCount,
                    missing,
                    inventory,
                    encountered)
                -- if a step fail, whole status must be false
                if request.ok then
                    recipeFound = rec
                    break
                end
            end
            if not recipeFound then
                -- TODO
                -- No recipe available. Search in jobs
                -- local jobsToDo = self.jobs[name] or {}
                -- for _, job in ipairs(jobsToDo) do
                --   getAvailability of this job and add it to dependencies
                missing[name] = rCount
                ok = false
            else
                -- update recursive values
                inventoryCount = request.response.inventoryCount
                missing = request.response.missing
                dependencies = addDependency(request.response.dependencies,
                    recipeFound,
                    rCount,
                    lvl)
            end
        else
            -- Item is raw material without enough quantity or
            -- we dont have a recipe for it. Throw error
            ok = false
            if not missing[name] then
                missing[name] = rCount
            else
                missing[name] = missing[name] + rCount
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
