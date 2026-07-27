-- Persistence via love.filesystem (save dir set by t.identity in conf.lua).
-- Two files: settings.lua (volumes, language) and run.lua (single save slot).
-- Data is written as a Lua literal and read back with love.filesystem.load.

local Save = {}

local SETTINGS_FILE = 'settings.lua'
local RUN_FILE = 'run.lua'

-- Serialize a plain table of numbers/strings/booleans (nested ok, no cycles)
local function serialize(v, indent)
    local t = type(v)
    if t == 'number' or t == 'boolean' then
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
        -- money model picked in the main menu: 'kills' pays on the killing
        -- blow, 'hits' pays per hit + a small kill bonus
        economy = s.economy == 'hits' and 'hits' or 'kills',
        -- crosshair look (== nil keeps saved false from reading as default)
        crossColor = s.crossColor == 'green' and 'green' or 'white',
        crossOutline = s.crossOutline == nil and true or s.crossOutline,
        -- graphics
        resolution = s.resolution or '1920x1080',
        fullscreen = s.fullscreen == nil and false or s.fullscreen,
        crtInGame = s.crtInGame == nil and false or s.crtInGame,
    }
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
