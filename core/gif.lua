-- Pure-Lua GIF decoder for LÖVE.
-- Decodes an animated .gif into one horizontal-strip Image, one quad per
-- frame, and per-frame delays in seconds. Results are cached per path, so
-- creating many animations from the same file only decodes once.

local Gif = {}

local cache = {}

local function le16(data, pos)
    return data:byte(pos) + data:byte(pos + 1) * 256
end

-- Color table: `count` RGB triplets starting at pos. Indexed from 0.
local function readColorTable(data, pos, count)
    local ct = {}
    for i = 0, count - 1 do
        local p = pos + i * 3
        ct[i] = { data:byte(p) / 255, data:byte(p + 1) / 255, data:byte(p + 2) / 255 }
    end
    return ct, pos + count * 3
end

-- Data sub-blocks (size byte + payload, 0 terminates) concatenated into one string.
local function readSubBlocks(data, pos)
    local parts = {}
    while true do
        local size = data:byte(pos)
        pos = pos + 1
        if not size or size == 0 then break end
        parts[#parts + 1] = data:sub(pos, pos + size - 1)
        pos = pos + size
    end
    return table.concat(parts), pos
end

-- GIF-flavored LZW: variable code width (LSB-first bit packing), dictionary
-- entries stored as (prefix code, suffix byte) pairs. Returns a 1-based array
-- of color-table indexes.
local function lzwDecode(minCodeSize, data, expected)
    local clear = 2 ^ minCodeSize
    local eoi = clear + 1
    local out, outN = {}, 0

    local prefix, suffix = {}, {}
    local codeSize, dictSize, prev
    local function resetDict()
        codeSize = minCodeSize + 1
        dictSize = eoi + 1
        prev = nil
        prefix, suffix = {}, {}
    end
    resetDict()

    local bytePos, bitBuf, bitCnt = 1, 0, 0
    local dataLen = #data
    local function readCode()
        while bitCnt < codeSize do
            if bytePos > dataLen then return nil end
            bitBuf = bitBuf + data:byte(bytePos) * 2 ^ bitCnt
            bitCnt = bitCnt + 8
            bytePos = bytePos + 1
        end
        local code = bitBuf % 2 ^ codeSize
        bitBuf = math.floor(bitBuf / 2 ^ codeSize)
        bitCnt = bitCnt - codeSize
        return code
    end

    local stack = {}
    -- Append code's byte sequence to out, return its first byte
    local function expand(code)
        local n, c = 0, code
        while c >= clear do
            n = n + 1
            stack[n] = suffix[c]
            c = prefix[c]
        end
        n = n + 1
        stack[n] = c
        for i = n, 1, -1 do
            outN = outN + 1
            out[outN] = stack[i]
        end
        return c
    end

    local function firstByteOf(code)
        while code >= clear do code = prefix[code] end
        return code
    end

    while outN < expected do
        local code = readCode()
        if code == nil or code == eoi then break end

        if code == clear then
            resetDict()
        elseif prev == nil then
            if code >= clear then break end -- corrupt stream
            expand(code)
            prev = code
        else
            local known = code < clear or (code > eoi and code < dictSize)
            if known then
                local first = expand(code)
                if dictSize < 4096 then
                    prefix[dictSize] = prev
                    suffix[dictSize] = first
                    dictSize = dictSize + 1
                end
            elseif code == dictSize and dictSize < 4096 then
                -- KwKwK: new entry is prev's string + prev's first byte
                prefix[dictSize] = prev
                suffix[dictSize] = firstByteOf(prev)
                dictSize = dictSize + 1
                expand(code)
            else
                break -- corrupt stream
            end
            prev = code
            if dictSize == 2 ^ codeSize and codeSize < 12 then
                codeSize = codeSize + 1
            end
        end
    end

    return out
end

local interlacePasses = { { 0, 8 }, { 4, 8 }, { 2, 4 }, { 1, 2 } }

local function decode(data)
    assert(data:sub(1, 3) == 'GIF', 'not a GIF file')

    local sw, sh = le16(data, 7), le16(data, 9)
    local packed = data:byte(11)
    local pos = 14
    local gct
    if packed >= 128 then
        gct, pos = readColorTable(data, pos, 2 ^ (packed % 8 + 1))
    end

    local canvas = love.image.newImageData(sw, sh) -- starts fully transparent
    local frames, delays = {}, {}
    local delay, transIndex, disposal = 0.1, nil, 0

    while true do
        local b = data:byte(pos)
        pos = pos + 1
        if b == nil or b == 0x3B then break end

        if b == 0x21 then -- extension
            local label = data:byte(pos)
            pos = pos + 1
            if label == 0xF9 then -- graphic control: disposal, delay, transparency
                local p = data:byte(pos + 1)
                disposal = math.floor(p / 4) % 8
                delay = le16(data, pos + 2) * 0.01
                if delay <= 0 then delay = 0.1 end
                transIndex = (p % 2 == 1) and data:byte(pos + 4) or nil
            end
            _, pos = readSubBlocks(data, pos)

        elseif b == 0x2C then -- image descriptor
            local left, top = le16(data, pos), le16(data, pos + 2)
            local w, h = le16(data, pos + 4), le16(data, pos + 6)
            local ipacked = data:byte(pos + 8)
            pos = pos + 9

            local lct
            if ipacked >= 128 then
                lct, pos = readColorTable(data, pos, 2 ^ (ipacked % 8 + 1))
            end
            local ct = lct or gct
            local interlaced = math.floor(ipacked / 64) % 2 == 1

            local minCodeSize = data:byte(pos)
            local lzwData
            lzwData, pos = readSubBlocks(data, pos + 1)
            local pixels = lzwDecode(minCodeSize, lzwData, w * h)

            local snapshot
            if disposal == 3 then
                snapshot = love.image.newImageData(sw, sh)
                snapshot:paste(canvas, 0, 0, 0, 0, sw, sh)
            end

            -- Stream row -> actual row (identity unless interlaced)
            local rows = {}
            if interlaced then
                local i = 0
                for _, pass in ipairs(interlacePasses) do
                    local y = pass[1]
                    while y < h do
                        rows[i] = y
                        i = i + 1
                        y = y + pass[2]
                    end
                end
            else
                for y = 0, h - 1 do rows[y] = y end
            end

            for r = 0, h - 1 do
                local y = top + rows[r]
                local base = r * w
                for x = 0, w - 1 do
                    local ci = pixels[base + x + 1]
                    if ci and ci ~= transIndex then
                        local c = ct and ct[ci]
                        local px = left + x
                        if c and px < sw and y < sh then
                            canvas:setPixel(px, y, c[1], c[2], c[3], 1)
                        end
                    end
                end
            end

            local frame = love.image.newImageData(sw, sh)
            frame:paste(canvas, 0, 0, 0, 0, sw, sh)
            frames[#frames + 1] = frame
            delays[#delays + 1] = delay

            if disposal == 2 then -- restore to background = clear frame rect
                for y = top, math.min(top + h, sh) - 1 do
                    for x = left, math.min(left + w, sw) - 1 do
                        canvas:setPixel(x, y, 0, 0, 0, 0)
                    end
                end
            elseif disposal == 3 and snapshot then
                canvas:paste(snapshot, 0, 0, 0, 0, sw, sh)
            end
            delay, transIndex, disposal = 0.1, nil, 0

        else
            break -- unknown block, stop rather than misparse
        end
    end

    assert(#frames > 0, 'GIF contained no frames')

    local strip = love.image.newImageData(sw * #frames, sh)
    for i, f in ipairs(frames) do
        strip:paste(f, (i - 1) * sw, 0, 0, 0, sw, sh)
    end

    local image = love.graphics.newImage(strip)
    local quads = {}
    for i = 1, #frames do
        quads[i] = love.graphics.newQuad((i - 1) * sw, 0, sw, sh, image)
    end

    return {
        image = image,
        quads = quads,
        delays = delays,
        frames = #frames,
        width = sw,
        height = sh,
    }
end

-- Load (and cache) a gif from the game folder, e.g. Gif.load('assets/images/ak_held.gif')
function Gif.load(path)
    if not cache[path] then
        local data, err = love.filesystem.read(path)
        assert(data, ('could not read %s: %s'):format(path, tostring(err)))
        cache[path] = decode(data)
    end
    return cache[path]
end

-- Drop cached decodes (U-key reload calls this so edited gifs get re-read)
function Gif.clearCache()
    cache = {}
end

return Gif
