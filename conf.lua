SCREENWIDTH = 1280
SCREENHEIGHT = 960

function love.conf(t)
    t.identity = 'shooter-game' -- stable save directory for settings + run save
    t.window.title = 'DEADWAVE'
    t.window.width = SCREENWIDTH
    t.window.height = SCREENHEIGHT
    t.window.display = 2
end
