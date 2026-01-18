local Sound = {}

local function addSound(filepath)
    return love.audio.newSource('sounds/'..filepath, 'static')
end

local function addMusic(filepath)
    return love.audio.newSource('sounds/'..filepath, 'static')
end

Sound.weapons = {
    ak47_shot = addSound('weapons/ak47-shot.mp3'),
    m4a1_shot = addSound('weapons/m4a1-shot.mp3'),
    mac10_shot = addSound('weapons/mac10-shot.mp3'),
    shotgun_shot = addSound('weapons/shotgun-shot.mp3')
}

return Sound