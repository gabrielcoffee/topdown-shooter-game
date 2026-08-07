-- Browser build switches.
--
-- The only thing separating the web package from the desktop one is a marker
-- file that `build.sh web` drops into the staged copy. Everything the browser
-- needs to do differently hangs off this flag, so there is exactly one place
-- to look when the two builds disagree.
--
-- Numbers still live in tune.lua, under the `web` table -- Web.applyTune folds
-- those over the real values at boot, so Gabriel keeps tuning one file.

local Web = {}

Web.enabled = love.filesystem.getInfo('WEB_BUILD') ~= nil

local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == 'table' and type(dst[k]) == 'table' then
            merge(dst[k], v)
        else
            dst[k] = v
        end
    end
end

-- Fold TUNE.web over TUNE in place. Runs at boot and again on every hot
-- reload (U), otherwise a reload would quietly restore the desktop values.
function Web.applyTune(T)
    if not Web.enabled or type(T.web) ~= 'table' then return end
    merge(T, T.web)
end

return Web
