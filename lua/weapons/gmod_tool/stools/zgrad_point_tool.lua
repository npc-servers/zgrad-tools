TOOL.Category   = "ZGRAD Mapping"
TOOL.Name       = "#zgrad_point_tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["point_type"]     = "red"
TOOL.ClientConVar["point_number"]   = "25"
TOOL.ClientConVar["mode"]           = "place"
TOOL.ClientConVar["place_mode"]     = "surface"
TOOL.ClientConVar["snap_ground"]    = "0"
TOOL.ClientConVar["placement_type"]   = "single"
TOOL.ClientConVar["area_length"]      = "512"
TOOL.ClientConVar["area_width"]       = "512"
TOOL.ClientConVar["area_count"]       = "16"
TOOL.ClientConVar["grid_spacing"]     = "64"
TOOL.ClientConVar["area_min_spacing"] = "64"

if SERVER then
    local function IsAuthorized( ply )
        return ply:IsAdmin() or ply:IsSuperAdmin() or ply:GetUserGroup() == "operator"
    end

    hook.Add( "CanTool", "ZGrad_PointToolCanTool", function( ply, tr, toolname )
        if toolname == "zgrad_point_tool" then
            return IsAuthorized( ply ) or nil
        end
    end )

    local function PointToolClearSelect( ply )
        if ply.ZGrad then ply.ZGrad.ptSelect = nil end
    end

    local function PointToolGetSelect( ply )
        return ply.ZGrad and ply.ZGrad.ptSelect
    end

    local function PointToolSetSelect( ply, pointType, index )
        ply.ZGrad = ply.ZGrad or {}
        ply.ZGrad.ptSelect = { pointType = pointType, index = index }
    end

    local function ChatTell( ply, msg )
        if IsValid( ply ) then ply:ChatPrint( msg ) end
    end

    local function ChatTellAll( actor, msg )
        local prefix = IsValid( actor ) and ( actor:Nick() .. ": " ) or ""
        for _, p in ipairs( player.GetAll() ) do
            p:ChatPrint( prefix .. msg )
        end
    end

    local function DataKeyForType( shortName )
        for k, info in pairs( ZGRAD.SpawnPointsList ) do
            if info[1] == shortName then return k end
        end
    end

    local function UndoAddedPoints( _, dataKey, pointRefs, pointType, ply )
        local pts = ZGRAD.SpawnPointsList[dataKey] and ZGRAD.SpawnPointsList[dataKey][3]
        if not pts then return false end

        local removed = 0
        local blockedHammer = false

        for _, ref in ipairs( pointRefs ) do
            for i = 1, #pts do
                if pts[i] == ref then
                    if pts[i][4] then
                        blockedHammer = true
                    else
                        table.remove( pts, i )
                        removed = removed + 1
                    end
                    break
                end
            end
        end

        if blockedHammer then
            ChatTell( ply, "Hammer-placed points cannot be undone." )
        end

        if removed == 0 then return false end

        ZGRAD.WriteDataMap( dataKey, pts )
        ZGRAD.SendSpawnPoint()

        local label = ( removed == 1 )
            and ( "undid " .. pointType .. " point placement." )
            or  ( "undid placement of " .. removed .. " " .. pointType .. " points." )
        ChatTellAll( ply, label )
    end

    local function NotifyBlocked( ply, reason )
        ChatTell( ply, "Cannot place point: " .. reason )
        net.Start( "zgrad_pt_place_deny" )
        net.Send( ply )
    end

    local function CommitPoints( ply, pointType, dataKey, entries )
        if #entries == 0 then return 0 end

        local pts    = ZGRAD.SpawnPointsList[dataKey][3]
        local points = {}
        for _, e in ipairs( entries ) do
            local point = { e.pos, e.ang, tonumber( e.num ) }
            table.insert( pts, point )
            points[#points + 1] = point
        end

        ZGRAD.WriteDataMap( dataKey, pts )
        ZGRAD.SendSpawnPoint()

        if IsValid( ply ) then
            local label = ( #points == 1 )
                and ( "Undone ZGRAD " .. pointType .. " point" )
                or  ( "Undone ZGRAD " .. pointType .. " placement (" .. #points .. ")" )

            undo.Create( "zgrad_point" )
                undo.SetPlayer( ply )
                undo.AddFunction( UndoAddedPoints, dataKey, points, pointType, ply )
                undo.SetCustomUndoText( label )
            undo.Finish( "ZGRAD " .. pointType .. " point" )
        end

        return #points
    end

    local function DoAdd( ply, pointType, pos, ang, pointNum )
        local dataKey = DataKeyForType( pointType )
        if not dataKey then
            ChatTell( ply, "Unknown point type: " .. tostring( pointType ) )
            return
        end

        local resolved = ZGRAD.ResolvePlacement( pos, pointType )
        if not resolved then
            NotifyBlocked( ply, "no clear space nearby." )
            return
        end

        CommitPoints( ply, pointType, dataKey, {
            { pos = resolved, ang = ang, num = pointNum },
        } )
        ChatTellAll( ply, "added a " .. pointType .. " point to the map." )
    end

    local function PositionIsPlaceable( pos, pointType, batch, minSpacing )
        if ZGRAD.IsPointInWall( pos ) then return false end
        if ZGRAD.FindIntersectingPoint( pos, pointType ) then return false end

        if minSpacing and minSpacing > 0 and ZGRAD.FindNearbyPoint( pos, minSpacing ) then
            return false
        end

        local minSq = ( minSpacing or 0 ) * ( minSpacing or 0 )
        for _, other in ipairs( batch ) do
            if ZGRAD.PointsIntersect( pos, pointType, other, pointType ) then
                return false
            end
            if minSq > 0 and pos:DistToSqr( other ) < minSq then
                return false
            end
        end

        return true
    end

    local function DoAddArea( ply, pointType, candidates, ang, pointNum, snapGround, limit, minSpacing )
        local dataKey = DataKeyForType( pointType )
        if not dataKey then
            ChatTell( ply, "Unknown point type: " .. tostring( pointType ) )
            return
        end

        local entries = {}
        local batch   = {}

        for _, raw in ipairs( candidates ) do
            if limit and #entries >= limit then break end

            local pos = raw
            if snapGround then
                pos = ZGRAD.SnapToGround( raw ) or raw
            end

            if PositionIsPlaceable( pos, pointType, batch, minSpacing ) then
                entries[#entries + 1] = { pos = pos, ang = ang, num = pointNum }
                batch[#batch + 1]     = pos
            end
        end

        local n = CommitPoints( ply, pointType, dataKey, entries )
        if n == 0 then
            NotifyBlocked( ply, "no valid positions in area." )
            return
        end

        ChatTellAll( ply, "added " .. n .. " " .. pointType .. " points to the map." )
    end

    local function FindNearestPointToPos( pos, maxDist )
        local list = ZGRAD.SpawnPointsList
        if not list then return nil end

        local bestDistSq = maxDist * maxDist
        local best = nil

        for dataKey, info in pairs( list ) do
            local pts = info[3]
            if not pts then continue end

            for i = 1, #pts do
                if pts[i][4] then continue end

                local other = ZGRAD.ReadPoint( pts[i] )
                if not other then continue end

                local dSq = pos:DistToSqr( other[1] )
                if dSq < bestDistSq then
                    bestDistSq = dSq
                    best = { dataKey = dataKey, typeName = info[1], index = i }
                end
            end
        end

        return best
    end

    local function DoRemove( ply, pointType, index )
        local dataKey = DataKeyForType( pointType )
        if not dataKey then return end

        local pts = ZGRAD.SpawnPointsList[dataKey][3]
        if not pts[index] then return end

        if pts[index][4] then
            ChatTell( ply, "Hammer-placed points cannot be deleted here." )
            return
        end

        table.remove( pts, index )
        ZGRAD.WriteDataMap( dataKey, pts )

        ZGRAD.SendSpawnPoint()
        ChatTellAll( ply, "removed " .. pointType .. " point #" .. index .. " from the map." )
    end

    local function DoMove( ply, pointType, index, newPos, newAng )
        local dataKey = DataKeyForType( pointType )
        if not dataKey then return false end

        local pts = ZGRAD.SpawnPointsList[dataKey][3]
        if not pts[index] then return false end

        if pts[index][4] then
            ChatTell( ply, "Hammer-placed points cannot be moved." )
            return false
        end

        local resolved = ZGRAD.ResolvePlacement( newPos, pointType, dataKey, index )
        if not resolved then
            NotifyBlocked( ply, "no clear space nearby." )
            return false
        end

        pts[index][1] = resolved
        pts[index][2] = newAng
        ZGRAD.WriteDataMap( dataKey, pts )

        ZGRAD.SendSpawnPoint()
        ChatTellAll( ply, "moved " .. pointType .. " point #" .. index .. "." )
        return true
    end

    function TOOL:LeftClick( trace )
        local ply  = self:GetOwner()
        if not IsAuthorized( ply ) then return true end

        local mode = self:GetClientInfo( "mode" )

        local snapGround = self:GetClientNumber( "snap_ground", 0 ) >= 1

        local function GetRawCursor()
            local placeMode = self:GetClientInfo( "place_mode" )
            return ( placeMode == "self" ) and ply:GetPos() or ( trace.HitPos + Vector( 0, 0, 5 ) )
        end

        local function GetCursorPos()
            local base = GetRawCursor()
            if snapGround then
                local snapped = ZGRAD.SnapToGround( base )
                if snapped then return snapped end
            end
            return base
        end

        if mode == "place" then
            local pointType     = self:GetClientInfo( "point_type" )
            local pointNum      = tonumber( self:GetClientNumber( "point_number", 25 ) ) or 25
            local ang           = Angle( 0, ply:EyeAngles().y, 0 )
            local placementType = self:GetClientInfo( "placement_type" )

            if placementType == "single" then
                DoAdd( ply, pointType, GetCursorPos(), ang, pointNum )
            else
                local center = GetCursorPos()
                local yaw    = ply:EyeAngles().y
                local length = math.max( 32, self:GetClientNumber( "area_length", 512 ) )
                local width  = math.max( 32, self:GetClientNumber( "area_width",  512 ) )

                local minSpacing = math.max( 0, self:GetClientNumber( "area_min_spacing", 64 ) )
                local count      = math.max( 1, math.floor( self:GetClientNumber( "area_count", 16 ) ) )

                local candidates
                if placementType == "grid" then
                    local spacing = math.max( 8, self:GetClientNumber( "grid_spacing", 64 ) )
                    candidates = ZGRAD.GetAreaGridPositions( center, yaw, length, width, spacing, count )
                else
                    candidates = ZGRAD.GetAreaRandomCandidates( center, yaw, length, width, count )
                end

                DoAddArea( ply, pointType, candidates, ang, pointNum, snapGround, count, minSpacing )
            end

        elseif mode == "select" then
            local sel = PointToolGetSelect( ply )
            if sel then
                local newAng = Angle( 0, ply:EyeAngles().y, 0 )
                if DoMove( ply, sel.pointType, sel.index, GetCursorPos(), newAng ) then
                    PointToolClearSelect( ply )
                end
            end
        end

        return true
    end

    function TOOL:RightClick( trace )
        local ply  = self:GetOwner()
        if not IsAuthorized( ply ) then return true end

        local nearest = FindNearestPointToPos( trace.HitPos, 192 )
        if nearest then
            DoRemove( ply, nearest.typeName, nearest.index )
            PointToolClearSelect( ply )
        end

        return true
    end

    function TOOL:Reload( trace )
        PointToolClearSelect( self:GetOwner() )
        return true
    end

    function TOOL:Holster()
        PointToolClearSelect( self:GetOwner() )
    end

    util.AddNetworkString( "zgrad_pt_select" )
    util.AddNetworkString( "zgrad_pt_select_sv" )

    util.AddNetworkString( "zgrad_pt_select_deny" )
    util.AddNetworkString( "zgrad_pt_place_deny" )

    net.Receive( "zgrad_pt_select_sv", function( _, ply )
        local pointType = net.ReadString()
        local index     = net.ReadUInt( 16 )

        local dataKey = DataKeyForType( pointType )
        if dataKey then
            local pts = ZGRAD.SpawnPointsList[dataKey] and ZGRAD.SpawnPointsList[dataKey][3]
            if not pts or not pts[index] or pts[index][4] then
                net.Start( "zgrad_pt_select_deny" )
                net.Send( ply )
                return
            end
        end

        PointToolSetSelect( ply, pointType, index )

        net.Start( "zgrad_pt_select" )
            net.WriteString( pointType )
            net.WriteUInt( index, 16 )
        net.Send( ply )
    end )
end

function TOOL:Deploy() end
function TOOL:Think() end

if CLIENT then
    function TOOL:LeftClick()  return true end
    function TOOL:RightClick() return true end
    function TOOL:Reload()     return true end
end

if CLIENT then

    language.Add( "Tool.zgrad_point_tool.name",  "Map Point Editor (ZGRAD)" )
    language.Add( "Tool.zgrad_point_tool.desc",  "Place and edit ZGRAD/Homigrad spawn and capture points. Saves to garrysmod/data/zgrad/maps/." )
    language.Add( "Tool.zgrad_point_tool.0",
        "[Place] LMB: Place point   |   [Select] LMB: Select / Move   RMB: Delete   R: Deselect   |   Scroll: swap mode" )

    local function IsHoldingPointTool( ply )
        if not IsValid( ply ) then return false end
        local wep = ply:GetActiveWeapon()
        if not IsValid( wep ) or wep:GetClass() ~= "gmod_tool" then return false end
        return ply:GetInfo( "gmod_toolmode" ) == "zgrad_point_tool"
    end

    local SCROLL_COOLDOWN = 0.18
    local lastScrollSwap  = 0
    local pendingMode     = nil

    cvars.AddChangeCallback( "zgrad_point_tool_mode", function( _, _, new )
        if pendingMode == new then pendingMode = nil end
    end, "zgrad_point_tool_mode_pending" )

    local function SwapPointToolMode()
        local cur = pendingMode
        if not cur then
            local cv = GetConVar( "zgrad_point_tool_mode" )
            cur = cv and cv:GetString() or "place"
        end

        local nextMode = ( cur == "place" ) and "select" or "place"
        pendingMode = nextMode
        RunConsoleCommand( "zgrad_point_tool_mode", nextMode )
    end

    hook.Add( "CreateMove", "ZGrad_PointToolScrollSwap", function( cmd )
        if vgui.CursorVisible() or gui.IsGameUIVisible() then return end
        if not IsHoldingPointTool( LocalPlayer() ) then return end

        if cmd:GetMouseWheel() == 0 then return end
        cmd:SetMouseWheel( 0 )

        local now = RealTime()
        if now - lastScrollSwap < SCROLL_COOLDOWN then return end
        lastScrollSwap = now

        SwapPointToolMode()
    end )

    hook.Add( "PlayerBindPress", "ZGrad_PointToolBlockInvScroll", function( ply, bind )
        if bind ~= "invnext" and bind ~= "invprev" then return end
        if not IsHoldingPointTool( ply ) then return end
        return true
    end )

    local HEADER_RULE = Color( 0, 0, 0, 40 )

    local function MakeHeader( panel, text )
        local row = vgui.Create( "DPanel", panel )
        row:SetTall( 16 )
        row:Dock( TOP )
        row:DockMargin( 6, 6, 6, 2 )
        row.Paint = function( _, w, h )
            surface.SetDrawColor( HEADER_RULE )
            surface.DrawRect( 0, h - 1, w, 1 )
        end

        local lbl = vgui.Create( "DLabel", row )
        lbl:SetText( string.upper( text ) )
        lbl:SetFont( "DermaDefaultBold" )
        lbl:SetDark( true )
        lbl:SetContentAlignment( 4 )
        lbl:Dock( FILL )

        panel:AddItem( row )
        return row
    end

    local function MakeHint( panel, text )
        local lbl = vgui.Create( "DLabel", panel )
        lbl:SetText( text )
        lbl:SetFont( "DermaDefault" )
        lbl:SetDark( true )
        lbl:SetWrap( true )
        lbl:SetAutoStretchVertical( true )
        lbl:Dock( TOP )
        lbl:DockMargin( 6, 0, 6, 4 )
        panel:AddItem( lbl )
        return lbl
    end

    function TOOL.BuildCPanel( cpanel )
        cpanel:ClearControls()

        MakeHeader( cpanel, "Mode" )

        local modeCombo = vgui.Create( "DComboBox", cpanel )
        modeCombo:SetTextColor( color_black )

        local currentMode = GetConVar( "zgrad_point_tool_mode" )
        local modeVal = currentMode and currentMode:GetString() or "place"
        modeCombo:AddChoice( "Place",                  "place"  )
        modeCombo:AddChoice( "Select / Move / Delete", "select" )
        modeCombo:SetValue( modeVal == "select" and "Select / Move / Delete" or "Place" )

        modeCombo.OnSelect = function( _, _, _, data )
            RunConsoleCommand( "zgrad_point_tool_mode", data )
        end
        modeCombo:Dock( TOP )
        modeCombo:DockMargin( 4, 0, 4, 4 )
        cpanel:AddItem( modeCombo )

        cvars.AddChangeCallback( "zgrad_point_tool_mode", function( _, _, new )
            if not IsValid( modeCombo ) then return end
            modeCombo:SetValue( new == "select" and "Select / Move / Delete" or "Place" )
        end, "zgrad_point_tool_mode_combo" )

        MakeHeader( cpanel, "Placement Origin" )

        local placeCombo = vgui.Create( "DComboBox", cpanel )
        placeCombo:SetTextColor( color_black )

        local currentPlaceMode = GetConVar( "zgrad_point_tool_place_mode" )
        local placeModeVal = currentPlaceMode and currentPlaceMode:GetString() or "surface"
        placeCombo:AddChoice( "Surface (trace hit)",  "surface" )
        placeCombo:AddChoice( "Self (your feet)",     "self"    )
        placeCombo:SetValue( placeModeVal == "self" and "Self (your feet)" or "Surface (trace hit)" )

        placeCombo.OnSelect = function( _, _, _, data )
            RunConsoleCommand( "zgrad_point_tool_place_mode", data )
        end
        placeCombo:Dock( TOP )
        placeCombo:DockMargin( 4, 0, 4, 2 )
        cpanel:AddItem( placeCombo )

        MakeHint( cpanel, "Use \"Self\" to place capture points\non elevated areas or in mid-air." )

        local snapCheck = vgui.Create( "DCheckBoxLabel", cpanel )
        snapCheck:SetText( "Snap to ground when available" )
        snapCheck:SetConVar( "zgrad_point_tool_snap_ground" )
        snapCheck:SetDark( true )
        snapCheck:Dock( TOP )
        snapCheck:DockMargin( 6, 4, 6, 4 )
        cpanel:AddItem( snapCheck )

        MakeHeader( cpanel, "Point Type" )

        local typeCombo = vgui.Create( "DComboBox", cpanel )
        typeCombo:SetTextColor( color_black )

        local currentType = GetConVar( "zgrad_point_tool_point_type" )
        local typeVal     = currentType and currentType:GetString() or "red"

        local sorted = {}
        for _, info in pairs( ZGRAD.SpawnPointsList or {} ) do
            sorted[#sorted + 1] = info[1]
        end
        table.sort( sorted )

        for _, name in ipairs( sorted ) do
            typeCombo:AddChoice( name )
        end
        typeCombo:SetValue( typeVal )

        typeCombo.OnSelect = function( _, _, value )
            RunConsoleCommand( "zgrad_point_tool_point_type", value )
        end
        typeCombo:Dock( TOP )
        typeCombo:DockMargin( 4, 0, 4, 4 )
        cpanel:AddItem( typeCombo )

        MakeHeader( cpanel, "Point Number / Index" )

        MakeHint( cpanel, "Used as control point index for CP mode\nor as a radius hint for visualization." )

        local numSlider = vgui.Create( "DNumSlider", cpanel )
        numSlider:SetText( "Number" )
        numSlider:SetMinMax( 1, 32 )
        numSlider:SetDecimals( 0 )
        numSlider:SetConVar( "zgrad_point_tool_point_number" )
        numSlider:SetDark( true )
        numSlider:Dock( TOP )
        numSlider:DockMargin( 4, 0, 4, 4 )
        cpanel:AddItem( numSlider )

        MakeHeader( cpanel, "Placement Type" )

        local placementCombo = vgui.Create( "DComboBox", cpanel )
        placementCombo:SetTextColor( color_black )

        local PLACEMENT_LABELS = {
            single = "Single point",
            random = "Area — randomized",
            grid   = "Area — grid",
        }

        for _, key in ipairs( { "single", "random", "grid" } ) do
            placementCombo:AddChoice( PLACEMENT_LABELS[key], key )
        end

        local currentPlacement = GetConVar( "zgrad_point_tool_placement_type" )
        local placementVal     = currentPlacement and currentPlacement:GetString() or "single"
        placementCombo:SetValue( PLACEMENT_LABELS[placementVal] or PLACEMENT_LABELS.single )

        placementCombo:Dock( TOP )
        placementCombo:DockMargin( 4, 0, 4, 4 )
        cpanel:AddItem( placementCombo )

        local function MakeAreaSlider( label, convar, min, max, decimals )
            local s = vgui.Create( "DNumSlider", cpanel )
            s:SetText( label )
            s:SetMinMax( min, max )
            s:SetDecimals( decimals or 0 )
            s:SetConVar( convar )
            s:SetDark( true )
            s:Dock( TOP )
            s:DockMargin( 4, 0, 4, 2 )
            cpanel:AddItem( s )
            return s
        end

        local lenSlider      = MakeAreaSlider( "Length",      "zgrad_point_tool_area_length",      64, 2048, 0 )
        local widthSlider    = MakeAreaSlider( "Width",       "zgrad_point_tool_area_width",       64, 2048, 0 )
        local countSlider    = MakeAreaSlider( "Max points",  "zgrad_point_tool_area_count",        1,  256, 0 )
        local spacingSlider  = MakeAreaSlider( "Grid spacing", "zgrad_point_tool_grid_spacing",    16,  512, 0 )
        local minSpaceSlider = MakeAreaSlider( "Min spacing", "zgrad_point_tool_area_min_spacing",  0,  512, 0 )

        local function ApplyPlacementVisibility( key )
            local isArea = ( key == "random" ) or ( key == "grid" )
            lenSlider:SetVisible(      isArea )
            widthSlider:SetVisible(    isArea )
            countSlider:SetVisible(    isArea )
            spacingSlider:SetVisible(  key == "grid" )
            minSpaceSlider:SetVisible( isArea )
            cpanel:InvalidateLayout()
        end
        ApplyPlacementVisibility( placementVal )

        placementCombo.OnSelect = function( _, _, _, data )
            RunConsoleCommand( "zgrad_point_tool_placement_type", data )
            ApplyPlacementVisibility( data )
        end

        MakeHeader( cpanel, "Controls" )

        MakeHint( cpanel,
            "PLACE MODE\n" ..
            "  LMB (Surface): place at trace hit\n" ..
            "  LMB (Self): place at your feet\n\n" ..
            "SELECT MODE\n" ..
            "  Left-click: select nearest point\n" ..
            "  Left-click again: move to cursor\n" ..
            "  Right-click: delete selected point\n" ..
            "  R (Reload): deselect\n\n" ..
            "GENERAL\n" ..
            "  Scroll: swap Place / Select mode\n" ..
            "  Undo: remove last placed point"
        )
    end

end
