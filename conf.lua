-- Provisional logical canvas size, used only until love.load runs. From there
-- ui/screen.lua owns these: the height stays 960 and the width follows the
-- window's aspect ratio, so the canvas always fills the window.
SCREENWIDTH = 1280
SCREENHEIGHT = 960

function love.conf(t)
    t.identity = 'shooter-game' -- stable save directory for settings + run save
                                -- (kept through the Zombie Chamber rename so
                                -- nobody loses their saves)
    t.window.title = 'Zombie Chamber'
    t.window.width = 1920
    t.window.height = 1080
    t.window.resizable = true
    -- no t.window.display: pinning it to a monitor index yanks the window onto
    -- that display at boot on multi-monitor machines and does nothing useful
    -- anywhere else. ui/screen.lua re-applies the saved mode on the display the
    -- window actually opened on.
end
