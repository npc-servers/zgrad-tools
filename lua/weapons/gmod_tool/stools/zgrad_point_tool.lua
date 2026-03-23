TOOL.Category   = "ZGRAD Mapping"
TOOL.Name       = "#zgrad_point_tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["point_type"]   = "red"
TOOL.ClientConVar["point_number"] = "25"
TOOL.ClientConVar["mode"]         = "place"
TOOL.ClientConVar["place_mode"]   = "surface"

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

    local function DoAdd( ply, pointType, pos, ang, pointNum )
        local dataKey = DataKeyForType( pointType )
        if not dataKey then
            ChatTell( ply, "Unknown point type: " .. tostring( pointType ) )
            return
        end

        local point = { pos, ang, tonumber( pointNum ) }
        table.insert( ZGRAD.SpawnPointsList[dataKey][3], point )
        ZGRAD.WriteDataMap( dataKey, ZGRAD.SpawnPointsList[dataKey][3] )

        ZGRAD.SendSpawnPoint()
        ChatTellAll( ply, "added a " .. pointType .. " point to the map." )
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
        if not dataKey then return end

        local pts = ZGRAD.SpawnPointsList[dataKey][3]
        if not pts[index] then return end

        if pts[index][4] then
            ChatTell( ply, "Hammer-placed points cannot be moved." )
            return
        end

        pts[index][1] = newPos
        pts[index][2] = newAng
        ZGRAD.WriteDataMap( dataKey, pts )

        ZGRAD.SendSpawnPoint()
        ChatTellAll( ply, "moved " .. pointType .. " point #" .. index .. "." )
    end

    function TOOL:LeftClick( trace )
        local ply  = self:GetOwner()
        if not IsAuthorized( ply ) then return true end

        local mode = self:GetClientInfo( "mode" )

        if mode == "place" then
            local pointType  = self:GetClientInfo( "point_type" )
            local pointNum   = tonumber( self:GetClientNumber( "point_number", 25 ) ) or 25
            local placeMode  = self:GetClientInfo( "place_mode" )
            local pos        = ( placeMode == "self" ) and ply:GetPos() or ( trace.HitPos + Vector( 0, 0, 5 ) )
            local ang        = Angle( 0, ply:EyeAngles().y, 0 )
            DoAdd( ply, pointType, pos, ang, pointNum )

        elseif mode == "select" then
            local sel = PointToolGetSelect( ply )
            if sel then
                local placeMode = self:GetClientInfo( "place_mode" )
                local newPos    = ( placeMode == "self" ) and ply:GetPos() or ( trace.HitPos + Vector( 0, 0, 5 ) )
                local newAng    = Angle( 0, ply:EyeAngles().y, 0 )
                DoMove( ply, sel.pointType, sel.index, newPos, newAng )
                PointToolClearSelect( ply )
            end
        end

        return true
    end

    function TOOL:RightClick( trace )
        local ply  = self:GetOwner()
        if not IsAuthorized( ply ) then return true end

        local mode = self:GetClientInfo( "mode" )

        if mode == "select" then
            local sel = PointToolGetSelect( ply )
            if sel then
                DoRemove( ply, sel.pointType, sel.index )
                PointToolClearSelect( ply )
            end
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
        "[Place] LMB: Place point   |   [Select] LMB: Select / Move   RMB: Delete   R: Deselect" )

    local TEXT_WHITE = Color( 240, 240, 240 )
    local TEXT_GRAY  = Color( 160, 160, 160 )

    local function MakeHeader( panel, text )
        local lbl = vgui.Create( "DLabel", panel )
        lbl:SetText( text )
        lbl:SetFont( "DermaDefaultBold" )
        lbl:SetTextColor( TEXT_WHITE )
        lbl:SetContentAlignment( 5 )
        lbl:SetTall( 22 )
        lbl:Dock( TOP )
        lbl:DockMargin( 4, 8, 4, 2 )
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

        local placeHint = vgui.Create( "DLabel", cpanel )
        placeHint:SetText( "Use \"Self\" to place capture points\non elevated areas or in mid-air." )
        placeHint:SetFont( "DermaDefault" )
        placeHint:SetTextColor( TEXT_GRAY )
        placeHint:SetWrap( true )
        placeHint:SetAutoStretchVertical( true )
        placeHint:Dock( TOP )
        placeHint:DockMargin( 6, 0, 6, 4 )
        cpanel:AddItem( placeHint )

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

        local hint = vgui.Create( "DLabel", cpanel )
        hint:SetText( "Used as control point index for CP mode\nor as a radius hint for visualization." )
        hint:SetFont( "DermaDefault" )
        hint:SetTextColor( TEXT_GRAY )
        hint:SetWrap( true )
        hint:SetAutoStretchVertical( true )
        hint:Dock( TOP )
        hint:DockMargin( 6, 0, 6, 2 )
        cpanel:AddItem( hint )

        local numSlider = vgui.Create( "DNumSlider", cpanel )
        numSlider:SetText( "Number" )
        numSlider:SetMinMax( 1, 32 )
        numSlider:SetDecimals( 0 )
        numSlider:SetConVar( "zgrad_point_tool_point_number" )
        numSlider:Dock( TOP )
        numSlider:DockMargin( 4, 0, 4, 4 )
        cpanel:AddItem( numSlider )

        MakeHeader( cpanel, "Controls" )

        local info = vgui.Create( "DLabel", cpanel )
        info:SetText(
            "PLACE MODE\n" ..
            "  LMB (Surface): place at trace hit\n" ..
            "  LMB (Self): place at your feet\n\n" ..
            "SELECT MODE\n" ..
            "  Left-click: select nearest point\n" ..
            "  Left-click again: move to cursor\n" ..
            "  Right-click: delete selected point\n" ..
            "  R (Reload): deselect"
        )
        info:SetFont( "DermaDefault" )
        info:SetTextColor( TEXT_GRAY )
        info:SetWrap( true )
        info:SetAutoStretchVertical( true )
        info:Dock( TOP )
        info:DockMargin( 6, 0, 6, 8 )
        cpanel:AddItem( info )
    end

end
