-- Wire format for LAN co-op. Everything that goes over ENet is built and
-- parsed here, so no other file has to think about bytes.
--
-- love.data.pack/unpack implement Lua 5.3 string.pack semantics; LuaJIT has
-- no string.pack of its own, so these are the only option. Little-endian is
-- forced rather than native: an ARM Mac hosting for an x86 PC has to agree.
--
-- A writer batches every field into ONE pack call instead of packing per
-- field -- a 40-zombie snapshot is ~250 fields, and 250 pack calls 60 times a
-- second is real waste.

local Protocol = {}

-- bumped whenever a message layout changes; a mismatched client is rejected
-- at HELLO rather than being allowed to misread every packet after it
-- 2: gameplay replication (snapshots, events, chat) plus two new input
--    buttons for the mouse wheel, which widened the button bitmask
-- 3: RELOAD joined the event kinds, so an older client would read the byte
--    after it as the next event and desync the rest of the packet
-- 4: the scoreboard counts kills per player instead of lifetime earnings, so
--    the player record carries a u16 where it used to carry a u32
Protocol.VERSION = 4

Protocol.MSG = {
    HELLO     = 1,  -- client -> host: version + name
    WELCOME   = 2,  -- host -> client: accepted, here is who you are
    REJECT    = 3,  -- host -> client: refused, here is why
    LOBBY     = 4,  -- host -> all: the roster
    READY     = 5,  -- client -> host: ready flag
    START     = 6,  -- host -> all: run begins
    INPUT     = 7,  -- client -> host: one input struct
    SNAPSHOT  = 8,  -- host -> all: world state
    EVENT     = 9,  -- host -> all: one-shot things (kills, doors, pickups)
    CHAT      = 10, -- both ways: one chat line
    VOICE     = 11, -- both ways: one PCM chunk
    FULLSTATE = 12, -- host -> client: serialized world for a drop-in join
    BYE       = 13, -- either way: clean disconnect
    PING      = 14,
}

-- reason codes for REJECT
Protocol.REJECT = {
    VERSION  = 1,
    FULL     = 2,
    BAD_NAME = 3,
    IN_USE   = 4,
}

Protocol.rejectText = {
    [1] = 'net.reject_version',
    [2] = 'net.reject_full',
    [3] = 'net.reject_name',
    [4] = 'net.reject_in_use',
}

-- ------------------------------------------------------------------ writer

local Writer = {}
Writer.__index = Writer

function Protocol.writer(msgId)
    local w = setmetatable({ fmt = { '<' }, vals = {} }, Writer)
    if msgId then w:u8(msgId) end
    return w
end

local function push(w, f, v)
    w.fmt[#w.fmt + 1] = f
    w.vals[#w.vals + 1] = v
    return w
end

function Writer:u8(v)  return push(self, 'B',  math.floor(v) % 256) end
function Writer:u16(v) return push(self, 'I2', math.floor(v) % 65536) end
function Writer:i16(v) return push(self, 'i2', math.max(-32768, math.min(32767, math.floor(v)))) end
-- clamped, not wrapped: a negative here is always a bug upstream, and
-- unclamped it throws out of the middle of building a packet
function Writer:u32(v) return push(self, 'I4', math.max(0, math.min(4294967295, math.floor(v)))) end
function Writer:f32(v) return push(self, 'f',  v) end
function Writer:bool(v) return push(self, 'B', v and 1 or 0) end

-- length-prefixed string. s1 caps at 255 bytes, which is far more than a
-- 20-char name or a chat line needs; s4 carries a serialized world.
function Writer:str(s)
    s = tostring(s or '')
    if #s > 255 then s = s:sub(1, 255) end
    return push(self, 's1', s)
end

function Writer:blob(s) return push(self, 's4', s or '') end

function Writer:build()
    return love.data.pack('string', table.concat(self.fmt), unpack(self.vals))
end

-- ------------------------------------------------------------------ reader

local Reader = {}
Reader.__index = Reader

function Protocol.reader(data)
    return setmetatable({ data = data, pos = 1 }, Reader)
end

-- Every read is guarded: a truncated or hostile packet returns nil instead of
-- throwing out of the middle of the network poll and killing the run.
local function take(r, fmt)
    if r.failed then return nil end
    local ok, v, nextPos = pcall(love.data.unpack, '<' .. fmt, r.data, r.pos)
    if not ok or v == nil then
        r.failed = true
        return nil
    end
    r.pos = nextPos
    return v
end

function Reader:u8()   return take(self, 'B') end
function Reader:u16()  return take(self, 'I2') end
function Reader:i16()  return take(self, 'i2') end
function Reader:u32()  return take(self, 'I4') end
function Reader:f32()  return take(self, 'f') end
function Reader:bool() local v = take(self, 'B'); return v ~= nil and v ~= 0 end
function Reader:str()  return take(self, 's1') end
function Reader:blob() return take(self, 's4') end
function Reader:ok()   return not self.failed end

-- message id without consuming anything else
function Protocol.msgId(data)
    if type(data) ~= 'string' or #data < 1 then return nil end
    return data:byte(1)
end

-- ------------------------------------------------------- input packing

local Input = require('core.input')

-- The button mask is a u32, not a u16: the wheel took the count to 17, and
-- bit 17 of a u16 is silently the same as no bit at all. So an input packet
-- is id(1) + seq(4) + buttons(4) + typing(1) + aim(8) = 18 bytes.
function Protocol.packInput(inp)
    local w = Protocol.writer(Protocol.MSG.INPUT)
    local bits = 0
    for i, b in ipairs(Input.buttons) do
        if inp[b] then bits = bits + 2^(i - 1) end
    end
    w:u32(inp.seq or 0)
    w:u32(bits)
    w:bool(inp.typing)
    w:f32(inp.aimX or 0)
    w:f32(inp.aimY or 0)
    return w:build()
end

-- Writes into an existing struct so the host isn't allocating one per packet
function Protocol.unpackInput(data, inp)
    local r = Protocol.reader(data)
    r:u8() -- message id
    local seq = r:u32()
    local bits = r:u32()
    local typing = r:bool()
    local aimX, aimY = r:f32(), r:f32()
    if not r:ok() then return nil end

    inp = inp or Input.new()
    for i, b in ipairs(Input.buttons) do
        inp[b] = (math.floor(bits / 2^(i - 1)) % 2) == 1
    end
    inp.seq, inp.typing = seq, typing
    inp.aimX, inp.aimY = aimX, aimY
    return inp
end

-- --------------------------------------------------------- beacon payload

-- The LAN beacon is plain UDP, not ENet, and is read by hosts that may be a
-- different build -- so it stays a simple text record rather than a struct
-- whose layout could drift.
function Protocol.packBeacon(info)
    return table.concat({
        'ZCHMB', tostring(Protocol.VERSION), info.hostId or '?', info.name or '?',
        tostring(info.players or 1), tostring(info.maxPlayers or 4),
        info.state or 'lobby', tostring(info.port or 0),
    }, '\31')
end

function Protocol.unpackBeacon(data)
    if type(data) ~= 'string' then return nil end
    local f = {}
    for part in (data .. '\31'):gmatch('([^\31]*)\31') do f[#f + 1] = part end
    if f[1] ~= 'ZCHMB' then return nil end
    return {
        version = tonumber(f[2]),
        -- a host is keyed by this, not by address: the same machine answers on
        -- both 127.0.0.1 and its LAN address, and one game must not list twice
        hostId = f[3],
        name = f[4],
        players = tonumber(f[5]) or 1,
        maxPlayers = tonumber(f[6]) or 4,
        state = f[7] or 'lobby',
        port = tonumber(f[8]) or TUNE.net.gamePort,
    }
end

return Protocol
