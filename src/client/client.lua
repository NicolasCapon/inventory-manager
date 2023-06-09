package.path = package.path .. ';../?.lua'
local gui = require("gui")

local clientGUI = gui:new()
parallel.waitForAll(clientGUI:start(),
    function() clientGUI:listenServerUpdates() end)
