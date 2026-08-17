-- Push-to-talk voice for LAN co-op.
--
-- Raw PCM, no codec. Opus would be a native dependency and a build problem on
-- three platforms to save bandwidth a LAN does not care about: 16kHz mono
-- 16-bit is 32 KB/s per speaker, against the ~55 KB/s the snapshots already
-- spend without anyone noticing. 25ms chunks keep a packet at 800 bytes, well
-- under any MTU, so a chunk is never fragmented.
--
-- Voice is the one thing here that is NOT host-authoritative in spirit: the
-- host relays rather than decides, and the only judgement it makes is the
-- proximity cut, because it is the machine that knows where everybody is.
--
-- Dropped chunks are a click and nothing more, so this rides the unreliable
-- channel and a late one is thrown away rather than played out of order.
--
-- macOS prompts for microphone access the first time a device is started. The
-- prompt is the OS's, it only appears on a real push-to-talk press, and being
-- denied leaves everything else working -- Voice.available just stays false.

local Protocol = require('net.protocol')
local Transport = require('net.transport')
local Keybinds = require('core.keybinds')

local function Session() return require('net.session') end

local Voice = {}

Voice.available = false  -- a capture device opened successfully
Voice.talking = false    -- push-to-talk held right now
Voice.denied = false     -- asked for a mic and did not get one; stop asking

local device = nil
local speaking = {}      -- slot -> secs left on the "is talking" indicator

-- One queueable source per speaker. Mixing four people into one source would
-- mean doing the mixing ourselves; four sources is what OpenAL is for.
local sources = {}

local function cfg() return TUNE.net.voice end

local function chunkSamples()
    local v = cfg()
    return math.floor(v.sampleRate * v.chunkMs / 1000)
end

-- ------------------------------------------------------------------ capture

-- Opened lazily, on the first push-to-talk press: asking for a microphone at
-- boot would put an OS permission prompt in front of a player who may never
-- use it.
local function openDevice()
    if device or Voice.denied then return device end
    local devices = love.audio.getRecordingDevices and love.audio.getRecordingDevices()
    if not devices or #devices == 0 then
        Voice.denied = true
        return nil
    end
    local v = cfg()
    local d = devices[1]
    -- ask for a buffer several chunks deep: getData is polled once a frame
    -- and a frame is not guaranteed to be shorter than a chunk
    local ok = d:start(chunkSamples() * 8, v.sampleRate, v.bitDepth, 1)
    if not ok then
        Voice.denied = true
        return nil
    end
    device = d
    Voice.available = true
    return device
end

function Voice.stop()
    if device then
        pcall(function() device:stop() end)
    end
    device = nil
    Voice.available = false
    Voice.talking = false
    for slot, s in pairs(sources) do
        pcall(function() s:stop() end)
        sources[slot] = nil
    end
    for k in pairs(speaking) do speaking[k] = nil end
end

-- Reset between runs; the device itself is opened on demand.
function Voice.begin()
    Voice.stop()
    Voice.denied = false
end

-- ---------------------------------------------------------------- playback

local function sourceFor(slot)
    if sources[slot] then return sources[slot] end
    local v = cfg()
    local s = love.audio.newQueueableSource(v.sampleRate, v.bitDepth, 1, v.maxQueued + 2)
    sources[slot] = s
    return s
end

-- pcm = raw little-endian samples exactly as they came off the wire.
-- gain 0 means "too far away to hear", which is a proximity decision the
-- receiver makes so the host does not have to send a volume per listener.
function Voice.play(slot, pcm, gain)
    if not pcm or pcm == '' or gain <= 0 then return end
    local v = cfg()
    local src = sourceFor(slot)
    -- a listener whose frames stalled must not build a growing delay: drop
    -- the chunk rather than queue behind a backlog
    if src:getFreeBufferCount() == 0 then return end
    local data = love.data.newByteData(pcm)
    local ok = pcall(function()
        src:queue(data, data:getSize(), v.sampleRate, v.bitDepth, 1)
    end)
    if not ok then return end
    src:setVolume(math.max(0, math.min(1, gain)) * (SETTINGS and SETTINGS.master or 1))
    if not src:isPlaying() then src:play() end
    speaking[slot] = 0.4
end

-- How loud slot `slot` should be for us, given where both of us are standing.
local function gainFor(slot, sx, sy, world)
    if Session().voiceMode ~= 'proximity' then return 1 end
    local me = world and world.player
    if not me then return 1 end
    local mx, my = me:getCenter()
    local dx, dy = sx - mx, sy - my
    local d = math.sqrt(dx * dx + dy * dy)
    local range = cfg().proximityRange
    if d >= range then return 0 end
    -- linear rolloff, floored so someone at the edge is faint rather than
    -- suddenly gone
    return math.max(0, 1 - (d / range)) ^ 0.6
end

-- ------------------------------------------------------------------- wire

local POS = 4

function Voice.send(pcm, world)
    local S = Session()
    if not S.active() or not pcm or pcm == '' then return end
    local me = world and world.player
    local cx, cy = 0, 0
    if me then cx, cy = me:getCenter() end
    local w = Protocol.writer(Protocol.MSG.VOICE)
    w:u8(S.localSlot or 1)
    w:u16(math.max(0, cx) * POS)
    w:u16(math.max(0, cy) * POS)
    w:blob(pcm)
    S.send(Transport.CHAN.VOICE, w:build(), 'unreliable')
end

-- Host: someone spoke. Play it here, then pass it on to everybody else.
-- In proximity mode the cut happens here as well as at each receiver -- the
-- host is the only machine that knows every position, so it can stop sending
-- 32 KB/s to a listener three rooms away rather than making them discard it.
function Voice.hostRelay(senderPeer, senderSlot, sx, sy, pcm, world)
    Voice.play(senderSlot, pcm, gainFor(senderSlot, sx, sy, world))

    local S = Session()
    local w = Protocol.writer(Protocol.MSG.VOICE)
    w:u8(senderSlot)
    w:u16(math.max(0, sx) * POS)
    w:u16(math.max(0, sy) * POS)
    w:blob(pcm)
    local packet = w:build()

    if S.voiceMode ~= 'proximity' then
        S.sendExcept(senderPeer, Transport.CHAN.VOICE, packet, 'unreliable')
        return
    end

    local range = cfg().proximityRange
    for slot, p in pairs(S.players) do
        if slot ~= senderSlot and p.peer then
            local body = world and world.netBySlot and world.netBySlot[slot]
            local send = true
            if body then
                local bx, by = body:getCenter()
                local dx, dy = bx - sx, by - sy
                send = (dx * dx + dy * dy) <= range * range
            end
            if send then
                S.sendTo(slot, Transport.CHAN.VOICE, packet, 'unreliable')
            end
        end
    end
end

-- Client: the host relayed someone (possibly us, which the host never does).
function Voice.receive(slot, sx, sy, pcm, world)
    if slot == Session().localSlot then return end
    Voice.play(slot, pcm, gainFor(slot, sx, sy, world))
end

-- Dispatched from net/session.lua for both roles.
function Voice.handle(r, event, world)
    local slot = r:u8()
    local x, y = r:u16(), r:u16()
    local pcm = r:blob()
    if not r:ok() or not slot then return end
    x, y = (x or 0) / POS, (y or 0) / POS

    if Session().role == 'host' then
        -- the peer decides the slot, not the packet: a client cannot claim
        -- to be somebody else by writing a different byte
        local real = slot
        for s, p in pairs(Session().players) do
            if p.peer == event.peer then real = s end
        end
        Voice.hostRelay(event.peer, real, x, y, pcm, world)
    else
        Voice.receive(slot, x, y, pcm, world)
    end
end

-- ------------------------------------------------------------------- pump

function Voice.update(dt, world)
    for slot, t in pairs(speaking) do
        speaking[slot] = (t > dt) and (t - dt) or nil
    end
    if not Session().active() then return end

    local want = Keybinds.isDown('voice') and not require('ui.chat').open
    if want and not device then openDevice() end
    Voice.talking = want and device ~= nil

    if not device then return end
    if not Voice.talking then
        -- drain whatever was captured while not transmitting, or it goes out
        -- in one lump the moment the key comes back down
        device:getData()
        return
    end

    local data = device:getData()
    if not data or data:getSampleCount() == 0 then return end
    Voice.send(data:getString(), world)
    speaking[Session().localSlot or 1] = 0.4
end

-- for the scoreboard's talking indicator
function Voice.isSpeaking(slot) return speaking[slot] ~= nil end

return Voice
