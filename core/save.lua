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

local function writeFile(name, data)
    love.filesystem.write(name, 'return ' .. serialize(data))
end

local function readFile(name)
    if not love.filesystem.getInfo(name) then return nil end
    local chunk = love.filesystem.load(name)
    local ok, data = pcall(chunk)
    if ok and type(data) == 'table' then return data end
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
        -- crosshair look (== nil keeps saved false from reading as default)
        crossColor = s.crossColor or 'white',
        crossSize = s.crossSize or 1,
        crossTilt = s.crossTilt == nil and true or s.crossTilt,
        crossOutline = s.crossOutline == nil and true or s.crossOutline,
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
end

return Save
