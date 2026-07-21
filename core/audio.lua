-- Sound effects with per-name source pools (rapid gunfire never cuts off).
-- Volumes: effective = master * category. Music category exists but has no
-- tracks yet; hook tracks in here when music lands.

local Audio = {}

Audio.master = 1
Audio.sfx = 1
Audio.music = 1

local files = {
    ak47_shot      = 'assets/sounds/weapons/ak47-shot.mp3',
    m4a1_shot      = 'assets/sounds/weapons/m4a1-shot.mp3',
    mac10_shot     = 'assets/sounds/weapons/mac10-shot.mp3',
    shotgun_shot   = 'assets/sounds/weapons/shotgun-shot.mp3',
    shotgun_reload = 'assets/sounds/weapons/shotgun-reload.mp3',
    shell1         = 'assets/sounds/weapons/shotgun-shell-01.mp3',
    shell2         = 'assets/sounds/weapons/shotgun-shell-02.mp3',
    shell3         = 'assets/sounds/weapons/shotgun-shell-03.mp3',
    bullet_hit1    = 'assets/sounds/effects/bullet_hit1.mp3',
    bullet_hit2    = 'assets/sounds/effects/bullet_hit2.mp3',
    grenade_blast  = 'assets/sounds/effects/grenade-blast-01-242d60bd.mp3',
}

local pools = {}

function Audio.load()
    for name, path in pairs(files) do
        pools[name] = { love.audio.newSource(path, 'static') }
    end
end

-- Play a sound; gain (default 1) scales this one play, on top of the volumes
function Audio.play(name, gain)
    local pool = pools[name]
    if not pool then return end

    local src
    for _, s in ipairs(pool) do
        if not s:isPlaying() then
            src = s
            break
        end
    end
    if not src then
        if #pool >= TUNE.audio.poolSize then return end -- pool full, drop the play
        src = pool[1]:clone()
        table.insert(pool, src)
    end

    src:setVolume(Audio.master * Audio.sfx * (gain or 1))
    src:play()
end

function Audio.setVolumes(master, sfx, music)
    Audio.master = master or Audio.master
    Audio.sfx = sfx or Audio.sfx
    Audio.music = music or Audio.music

    -- already-playing sources follow the new volume immediately
    for _, pool in pairs(pools) do
        for _, s in ipairs(pool) do
            if s:isPlaying() then
                s:setVolume(Audio.master * Audio.sfx)
            end
        end
    end
end

return Audio
