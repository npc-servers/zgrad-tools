ZGRAD = ZGRAD or {}
if ZGRAD.WriteDataMap then return end

local mapDir = "zgrad/maps"

file.CreateDir( "zgrad" )
file.CreateDir( mapDir )

ZGRAD.SpawnPointsPage = ZGRAD.SpawnPointsPage or 1

ZGRAD.SpawnPointsList = {
    spawnpointhmcd = {"hmcd",Color(150,150,150)},
    spawnpointst = {"red",Color(255,0,0)},
    spawnpointsct = {"blue",Color(0,0,255)},

    waronterror_vagner = {"vagner",Color(255,0,0)},
    waronterror_nato = {"nato",Color(0,0,255)},

    spawnpointswick = {"spawnpointswick",Color(255,0,0)},
    spawnpointsnaem = {"spawnpointsnaem",Color(0,0,255)},

    spawnpoints_ss_police = {"police",Color(0,0,125)},
    spawnpoints_ss_school = {"school",Color(0,255,0)},

    spawnpoints_ss_exit = {"exit",Color(0,125,0),true},

    controlpoint = {"control_point",Color(25,25,25)},
    boxspawn = {"boxspawn",Color(25,25,25)},
    basedefencebots = {"basedefencebots",Color(155,155,155)},
    basedefenceplayerspawns = {"basedefenceplayerspawns",Color(255,255,0)},

    center = {"center",Color(255,255,255)},

    jailbreak = {"jailbreak",Color(0,125,0)},
    jailbreak_doors = {"jailbreak_doors",Color(255,0,0)},

    glide_zg_conscript_apc = {"glide_zg_conscript_apc",Color(200,255,200)},
    glide_zg_technical_kord = {"glide_zg_technical_kord",Color(200,255,200)},
    glide_zg_technical = {"glide_zg_technical",Color(200,255,200)},
    glide_zg_ah64d = {"glide_zg_ah64d",Color(200,255,200)},
    gtav_insurgent = {"gtav_insurgent",Color(200,255,200)},
    gtav_police_cruiser = {"gtav_police_cruiser",Color(200,255,200)},
    gtav_speedo = {"gtav_speedo",Color(200,255,200)},
    gtav_wolfsbane = {"gtav_wolfsbane",Color(200,255,200)},
    gtav_sanchez = {"gtav_sanchez",Color(200,255,200)},
    gtav_bati801 = {"gtav_bati801",Color(200,255,200)},
    gtav_gauntlet_classic = {"gtav_gauntlet_classic",Color(200,255,200)},
    gtav_dukes = {"gtav_dukes",Color(200,255,200)},
    gtav_airbus = {"gtav_airbus",Color(200,255,200)},
    gtav_infernus = {"gtav_infernus",Color(200,255,200)},
    gtav_stunt = {"gtav_stunt",Color(200,255,200)},
    gtav_dinghy = {"gtav_dinghy",Color(200,255,200)}
}

local function GetDataMapName( name, localToDataFolder )
    local dataPath = mapDir .. "/" .. name .. "/" .. game.GetMap() .. ( ZGRAD.SpawnPointsPage == 1 and "" or ZGRAD.SpawnPointsPage ) .. ".txt"
    dataPath = localToDataFolder and dataPath or "data/" .. dataPath

    return dataPath
end

local function ParseVector( v )
    if isvector( v ) then return v end
    if type( v ) == "string" then
        local s = v:match( "%[?([^%]]+)%]?" )
        local parts = string.Explode( " ", s )
        return Vector( tonumber( parts[1] ) or 0, tonumber( parts[2] ) or 0, tonumber( parts[3] ) or 0 )
    end
    if type( v ) == "table" then
        if v[1] ~= nil then
            return Vector( v[1] or 0, v[2] or 0, v[3] or 0 )
        end
        return Vector( v.x or 0, v.y or 0, v.z or 0 )
    end
    return Vector()
end

local function ParseAngle( a )
    if isangle( a ) then return a end
    if type( a ) == "string" then
        local s = a:match( "{?([^}]+)}?" )
        local parts = string.Explode( " ", s )
        return Angle( tonumber( parts[1] ) or 0, tonumber( parts[2] ) or 0, tonumber( parts[3] ) or 0 )
    end
    if type( a ) == "table" then
        if a[1] ~= nil then
            return Angle( a[1] or 0, a[2] or 0, a[3] or 0 )
        end
        return Angle( a.p or 0, a.y or 0, a.r or 0 )
    end
    return Angle()
end

function ZGRAD.ReadDataMap( name )
    local raw = util.JSONToTable( file.Read( GetDataMapName( name ), "GAME" ) or "" ) or {}
    local out = {}
    for _, pt in ipairs( raw ) do
        if type( pt ) == "table" then
            out[#out + 1] = {
                ParseVector( pt[1] ),
                ParseAngle(  pt[2] ),
                pt[3]
            }
        end
    end
    return out
end

function ZGRAD.WriteDataMap( name, data )
    file.CreateDir( mapDir .. "/" .. name )
    local serialized = {}
    for _, pt in ipairs( data or {} ) do
        if pt[4] then continue end
        local pos = isvector( pt[1] ) and pt[1] or ParseVector( pt[1] )
        local ang = isangle(  pt[2] ) and pt[2] or ParseAngle(  pt[2] )
        serialized[#serialized + 1] = {
            { pos.x, pos.y, pos.z },
            { ang.p, ang.y, ang.r },
            pt[3]
        }
    end
    file.Write( GetDataMapName( name, true ), util.TableToJSON( serialized ) or "" )
end

local function SetupSpawnPointsList()
    for name, info in pairs( ZGRAD.SpawnPointsList ) do
        info[3] = ZGRAD.ReadDataMap( name )
    end
end

SetupSpawnPointsList()

local function ReadMapEntities()
    for _, ent in ipairs( ents.FindByClass( "zgr_spawn_boxspawn" ) ) do
        table.insert( ZGRAD.SpawnPointsList.boxspawn[3], { ent:GetPos(), ent:GetAngles(), false, true } )
    end

    for _, ent in ipairs( ents.FindByClass( "zgr_control_point" ) ) do
        local idx = tonumber( ent:GetKeyValues()["pointindex"] ) or 1
        table.insert( ZGRAD.SpawnPointsList.controlpoint[3], { ent:GetPos(), ent:GetAngles(), idx, true } )
    end

    for _, class in ipairs({ "info_player_terrorist", "info_player_rebel", "zgr_spawn_red" }) do
        for _, ent in ipairs( ents.FindByClass( class ) ) do
            table.insert( ZGRAD.SpawnPointsList.spawnpointst[3], { ent:GetPos(), ent:GetAngles(), false, true } )
        end
    end

    for _, class in ipairs({ "info_player_counterterrorist", "info_player_combine", "zgr_spawn_blue" }) do
        for _, ent in ipairs( ents.FindByClass( class ) ) do
            table.insert( ZGRAD.SpawnPointsList.spawnpointsct[3], { ent:GetPos(), ent:GetAngles(), false, true } )
        end
    end

    for _, class in ipairs({ "info_player_start", "info_player_deathmatch", "zgr_spawn_deathmatch" }) do
        for _, ent in ipairs( ents.FindByClass( class ) ) do
            table.insert( ZGRAD.SpawnPointsList.spawnpointhmcd[3], { ent:GetPos(), ent:GetAngles(), false, true } )
        end
    end
end

hook.Add( "InitPostEntity", "ZGrad_ReadMapSpawnEntities_InitPostEntity", function()
    ReadMapEntities()
end )

hook.Add( "PostCleanupMap", "ZGrad_ReadMapSpawnEntities_PostCleanupMap", function()
    SetupSpawnPointsList()
    ReadMapEntities()
end )

util.AddNetworkString( "zgrad_spawn_points" )

function ZGRAD.SendSpawnPoint( ply )
    net.Start( "zgrad_spawn_points" )
    net.WriteTable( ZGRAD.SpawnPointsList )
    if ply then net.Send( ply ) else net.Broadcast() end
end

function ZGRAD.AddSpawnPoint( caller, pointType, pointNumber )
    local tbl = ZGRAD.ReadDataMap( pointType )
    local point = { caller:GetPos() + Vector( 0, 0, 5 ), Angle( 0, caller:EyeAngles()[2], 0 ), tonumber( pointNumber ) }
    table.insert( tbl, point )
    ZGRAD.WriteDataMap( pointType, tbl )

    SetupSpawnPointsList()
    ReadMapEntities()
    ZGRAD.SendSpawnPoint()
end

function ZGRAD.ResetSpawnPoints( pointType )
    ZGRAD.WriteDataMap( pointType )

    SetupSpawnPointsList()
    ReadMapEntities()
    ZGRAD.SendSpawnPoint()
end

hook.Add( "PlayerInitialSpawn", "ZGrad_SendSpawnPoints", function( ply )
    ZGRAD.SendSpawnPoint( ply )
end )
