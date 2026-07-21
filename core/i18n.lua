-- Tiny localization: locales/<code>.lua are flat key -> string tables.
-- Use the global T('some.key') everywhere a player-facing string appears.
-- Missing keys return the key itself so nothing ever crashes.

local i18n = {}

i18n.codes = { 'en', 'pt', 'es' }
i18n.names = { en = 'English', pt = 'Português', es = 'Español' }
i18n.lang = 'en'

local strings = {}

function i18n.setLanguage(code)
    if not i18n.names[code] then code = 'en' end
    i18n.lang = code
    strings = require('locales.' .. code)
end

-- Cycle helper for the options screen (dir = 1 or -1)
function i18n.nextLanguage(dir)
    local idx = 1
    for i, c in ipairs(i18n.codes) do
        if c == i18n.lang then idx = i end
    end
    idx = ((idx - 1 + dir) % #i18n.codes) + 1
    return i18n.codes[idx]
end

_G.T = function(key, ...)
    local s = strings[key] or key
    if select('#', ...) > 0 then
        return s:format(...)
    end
    return s
end

return i18n
