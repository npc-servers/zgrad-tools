ZGRAD = ZGRAD or {}

ZGRAD.SpawnPointsList = ZGRAD.SpawnPointsList or {}

local incoming = { buffer = "", expected = 0 }

local function DecodePayload( raw )
    local decompressed = util.Decompress( raw )
    if not decompressed or decompressed == "" then return nil end

    local decoded = util.JSONToTable( decompressed )
    if not decoded then return nil end

    local out = {}
    for dataKey, entry in pairs( decoded ) do
        local color = entry.c or { 255, 255, 255, 255 }
        local pts   = {}

        for _, p in ipairs( entry.p or {} ) do
            local pt = {
                Vector( p.px or 0, p.py or 0, p.pz or 0 ),
                Angle(  p.ap or 0, p.ay or 0, p.ar or 0 ),
                p.n,
            }
            if p.h then pt[4] = true end
            pts[#pts + 1] = pt
        end

        out[dataKey] = {
            entry.t,
            Color( color[1] or 255, color[2] or 255, color[3] or 255, color[4] or 255 ),
            pts,
        }
    end

    return out
end

net.Receive( "zgrad_spawn_points", function()
    local total  = net.ReadUInt( 32 )
    local offset = net.ReadUInt( 32 )
    local chunk  = net.ReadUInt( 32 )
    local last   = net.ReadBool()

    if total == 0 then
        ZGRAD.SpawnPointsList = {}
        hook.Run( "ZGrad_SpawnPointsUpdated" )
        return
    end

    if offset == 0 then
        incoming.buffer   = ""
        incoming.expected = total
    end

    if incoming.expected ~= total then
        incoming.buffer   = ""
        incoming.expected = total
    end

    if chunk > 0 then
        incoming.buffer = incoming.buffer .. net.ReadData( chunk )
    end

    if not last then return end

    local decoded = DecodePayload( incoming.buffer )
    incoming.buffer   = ""
    incoming.expected = 0

    if not decoded then return end

    ZGRAD.SpawnPointsList = decoded
    hook.Run( "ZGrad_SpawnPointsUpdated" )
end )

hook.Add( "InitPostEntity", "ZGrad_RequestSpawnPoints", function()
    net.Start( "zgrad_spawn_points_request" )
    net.SendToServer()
end )

if LocalPlayer and IsValid( LocalPlayer() ) then
    timer.Simple( 0, function()
        net.Start( "zgrad_spawn_points_request" )
        net.SendToServer()
    end )
end
