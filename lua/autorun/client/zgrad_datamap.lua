ZGRAD = ZGRAD or {}
if net.Receivers and net.Receivers["zgrad_spawn_points"] then return end

ZGRAD.SpawnPointsList = ZGRAD.SpawnPointsList or {}

net.Receive( "zgrad_spawn_points", function()
    ZGRAD.SpawnPointsList = net.ReadTable()
    hook.Run( "ZGrad_SpawnPointsUpdated" )
end )
