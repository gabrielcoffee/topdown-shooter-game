-- Logical canvas size (4:3, the only supported ratio). The real window is set
-- from saved graphics settings in love.load via ui/screen.lua; these are just
-- the provisional values used before that runs.
SCREENWIDTH = 1280
SCREENHEIGHT = 960

function love.conf(t)
    t.identity = 'shooter-game' -- stable save directory for settings + run save
    t.window.title = 'DEADWAVE'
    t.window.width = 1920
    t.window.height = 1080
    t.window.resizable = true
    t.window.display = 2
end
