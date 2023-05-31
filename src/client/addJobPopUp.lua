local lib = {}

function lib.openNewJob(mainGUI)
    local newJobFrame = mainGUI.main:addFrame("newJobFrame")
        :setMovable()
        :setSize("parent.w", "parent.h")
        :setPosition(1, 1)
        :setFocus()

    newJobFrame:addLabel()
        :setSize("parent.w", 1)
        :setBackground(colors.black)
        :setForeground(colors.lightGray)
        :setText("New Job")

    newJobFrame:addProgram("newJobProg")
        :setSize("parent.w", "parent.h - 1")
        :setPosition(1, 2)
        :onDone(function()
            newJobFrame:remove()
            mainGUI:resetState()
        end)
        :setFocus()
        :execute("addJob.lua")

    newJobFrame:addButton()
        :setSize(1, 1)
        :setText("X")
        :setBackground(colors.black)
        :setForeground(colors.red)
        :setPosition("parent.w", 1)
        :onClick(function()
            newJobFrame:remove()
        end)
    return newJobFrame
end

return lib