-- Player names for LAN co-op. Typed once and kept in settings.lua.
--
-- Rules: 3-20 characters, letters/digits/underscore, must start with a
-- letter. That blocks "123", blocks blank-looking names, and keeps every
-- character inside what PressStart2P can actually draw -- an accented or
-- CJK name would render as tofu boxes in chat and on the scoreboard.

local Name = {}

Name.MIN = 3
Name.MAX = 20

-- Reasons a name can be refused, as i18n keys for the UI to show
Name.ERR = {
    SHORT   = 'name.err_short',
    LONG    = 'name.err_long',
    START   = 'name.err_start',
    CHARS   = 'name.err_chars',
}

-- Is this a character the player is allowed to type into the name field?
-- The name box filters keystrokes with this so bad input never appears.
function Name.allowedChar(c)
    return c:match('^[%a%d_]$') ~= nil
end

-- true, name | false, errKey
function Name.validate(s)
    s = tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #s < Name.MIN then return false, Name.ERR.SHORT end
    if #s > Name.MAX then return false, Name.ERR.LONG end
    if not s:match('^%a') then return false, Name.ERR.START end
    if not s:match('^[%a%d_]+$') then return false, Name.ERR.CHARS end
    return true, s
end

function Name.valid(s)
    return (Name.validate(s))
end

-- Strip anything illegal rather than rejecting outright: used when loading a
-- name from settings written by an older build. nil if nothing usable is left.
function Name.sanitize(s)
    s = tostring(s or ''):gsub('[^%a%d_]', '')
    s = s:gsub('^[%d_]+', '') -- must start with a letter
    if #s > Name.MAX then s = s:sub(1, Name.MAX) end
    if #s < Name.MIN then return nil end
    return s
end

-- Two players called coffeebreak in one lobby: the second becomes
-- coffeebreak2. `taken` is a set of names already in use. The suffix eats into
-- the 20-char cap rather than pushing past it.
function Name.dedupe(name, taken)
    if not taken or not taken[name] then return name end
    for n = 2, TUNE.net.maxPlayers + 1 do
        local suffix = tostring(n)
        local base = name
        if #base + #suffix > Name.MAX then
            base = base:sub(1, Name.MAX - #suffix)
        end
        local candidate = base .. suffix
        if not taken[candidate] then return candidate end
    end
    return name -- more collisions than there are player slots: cannot happen
end

-- The name this machine plays under. Falls back to a generated one so a
-- player who never opened the field can still host or join.
function Name.get()
    local s = Name.sanitize(SETTINGS and SETTINGS.playerName)
    if s then return s end
    return 'Player' .. tostring(love.math.random(100, 999))
end

function Name.set(s)
    local ok, result = Name.validate(s)
    if not ok then return false, result end
    SETTINGS.playerName = result
    require('core.save').saveSettings(SETTINGS)
    return true, result
end

return Name
