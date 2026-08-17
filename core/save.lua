-- Persistence via love.filesystem (save dir set by t.identity in conf.lua).
-- Two files: settings.lua (volumes, language) and run.lua (single save slot).
-- Data is written as a Lua literal and read back with love.filesystem.load.

local Save = {}

local SETTINGS_FILE = 'settings.lua'
local RUN_FILE = 'run.lua'
local BEST_FILE = 'best.lua'

-- Serialize a plain table of numbers/strings/booleans (nested ok, no cycles)
local function serialize(v, indent)
    local t = type(v)
    if t == 'number' then
        -- %.17g round-trips doubles exactly; tostring truncates and would
        -- drift positions a hair on every save/load cycle
        return string.format('%.17g', v)
    elseif t == 'boolean' then
        return tostring(v)
    elseif t == 'string' then
        return string.format('%q', v)
    elseif t == 'table' then
        local pad = (indent or '') .. '  '
        local parts = {}
        for k, val in pairs(v) do
            local key
            if type(k) == 'string' and k:match('^[%a_][%w_]*$') then
                key = k
            else
                key = '[' .. serialize(k) .. ']'
            end
            table.insert(parts, pad .. key .. ' = ' .. serialize(val, pad))
        end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. (indent or '') .. '}'
    end
    error('cannot serialize a ' .. t)
end

-- bumped when the shape of a save table changes; loaders can branch on it
local FORMAT_VERSION = 1

-- Crash-safe write: the new content goes to <name>.tmp first and must load
-- back cleanly before it replaces the real file; the previous good file is
-- kept as <name>.bak (love.filesystem has no rename, so this is the closest
-- to atomic). A crash mid-write can only ever lose the newest snapshot.
-- Note: stamps data.version on the passed table.
local function writeFile(name, data)
    data.version = FORMAT_VERSION
    local body = 'return ' .. serialize(data)

    local tmp = name .. '.tmp'
    if not love.filesystem.write(tmp, body) then return end
    local chunk = love.filesystem.load(tmp)
    if not chunk then return end
    local ok, parsed = pcall(chunk)
    if not ok or type(parsed) ~= 'table' then return end -- never install garbage

    local old = love.filesystem.getInfo(name) and love.filesystem.read(name)
    if old then love.filesystem.write(name .. '.bak', old) end
    love.filesystem.write(name, body)
    love.filesystem.remove(tmp)
end

-- Read the main file; if it's missing or corrupt, quietly fall back to .bak
local function readFile(name)
    for _, candidate in ipairs({ name, name .. '.bak' }) do
        if love.filesystem.getInfo(candidate) then
            local chunk = love.filesystem.load(candidate)
            if chunk then
                local ok, data = pcall(chunk)
                if ok and type(data) == 'table' then return data end
            end
        end
    end
    return nil
end

-- Settings ----------------------------------------------------------------

function Save.saveSettings(s)
    writeFile(SETTINGS_FILE, s)
end

-- Always returns a full settings table; missing fields fall back to defaults
function Save.loadSettings()
    local s = readFile(SETTINGS_FILE) or {}
    return {
        master = s.master or TUNE.audio.masterDefault,
        sfx = s.sfx or TUNE.audio.sfxDefault,
        music = s.music or TUNE.audio.musicDefault,
        language = s.language or 'en',
        -- world ambient light, clamped to the options slider's range
        brightness = math.max(TUNE.lighting.brightnessMin,
            math.min(type(s.brightness) == 'number' and s.brightness
                or TUNE.lighting.ambient, TUNE.lighting.brightnessMax)),
        -- crosshair look (== nil keeps saved false from reading as default)
        crossColor = s.crossColor == 'green' and 'green' or 'white',
        crossOutline = s.crossOutline == nil and true or s.crossOutline,
        -- graphics
        -- 'native' tracks the desktop, so a first run fits whatever screen it
        -- lands on instead of asking a laptop for 1080p it cannot show
        resolution = s.resolution or 'native',
        fullscreen = s.fullscreen == nil and false or s.fullscreen,
        crtInGame = s.crtInGame == nil and false or s.crtInGame,
        -- action -> key; core/keybinds.lua fills the gaps from its defaults
        keybinds = type(s.keybinds) == 'table' and s.keybinds or {},
        -- multiplayer identity, validated by core/name.lua
        playerName = type(s.playerName) == 'string' and s.playerName or nil,
    }
end

-- Best (all-time records shown on the death screen) ------------------------

function Save.loadBest()
    local b = readFile(BEST_FILE) or {}
    return { wave = b.wave or 0, kills = b.kills or 0 }
end

function Save.saveBest(b)
    writeFile(BEST_FILE, b)
end

-- Run (single slot) --------------------------------------------------------

function Save.runExists()
    return love.filesystem.getInfo(RUN_FILE) ~= nil
end

function Save.saveRun(data)
    writeFile(RUN_FILE, data)
end

function Save.loadRun()
    return readFile(RUN_FILE)
end

function Save.deleteRun()
    love.filesystem.remove(RUN_FILE)
    love.filesystem.remove(RUN_FILE .. '.bak') -- a dead run must not resurrect
end

return Save
