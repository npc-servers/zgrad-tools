local TOOL_NAME         = "zgrad_point_tool"
local HOVER_RADIUS_SQ   = 160 * 160
local SPHERE_SEGS       = 12
local CP_CAPTURE_RADIUS = 256

local RENDER_DIST       = 4000
local RENDER_DIST_SQ    = RENDER_DIST * RENDER_DIST
local FADE_START        = 1200
local FADE_RANGE        = RENDER_DIST - FADE_START
local LABEL_DIST_SQ     = 1200 * 1200

local SELECTED_COLOR    = Color( 255, 230, 60 )
local HOVER_COLOR       = Color( 255, 180, 50 )
local HAMMER_COLOR      = Color( 120, 120, 120 )

local TYPE_RADIUS = {
    control_point = CP_CAPTURE_RADIUS,
    boxspawn      = 48,
}
local DEFAULT_SPAWN_RADIUS = 24

local ARROW_LENGTH     = 40
local ARROW_HEAD       = 16
local ARROW_HEAD_WING  = ARROW_HEAD * 0.6

local LABEL_BG     = Color( 0, 0, 0, 160 )

local PANEL_FONT = "DermaLarge"

local _col = Color( 0, 0, 0, 0 )
local function MutColor( col, alpha )
    _col.r = col.r
    _col.g = col.g
    _col.b = col.b
    _col.a = math.Clamp( alpha, 0, 255 )
    return _col
end

local selectedPoint  = nil
local hoveredPoint   = nil

local pointCache     = {}
local typeColorCache = {}

local function RebuildCache()
    pointCache    = {}
    typeColorCache = {}

    for dataKey, info in pairs( ZGRAD.SpawnPointsList or {} ) do
        local typeName   = info[1]
        local baseColor  = info[2]
        local pts        = info[3]
        local gameRadius = TYPE_RADIUS[typeName] or DEFAULT_SPAWN_RADIUS

        typeColorCache[typeName] = baseColor

        if not pts then continue end

        for i, rawPt in ipairs( pts ) do
            local p = ZGRAD.ReadPoint( rawPt )
            if not p then continue end

            pointCache[#pointCache + 1] = {
                pos        = p[1],
                ang        = p[2],
                num        = p[3],
                typeName   = typeName,
                baseColor  = baseColor,
                gameRadius = gameRadius,
                dataIndex  = i,
                hammer     = rawPt[4] == true,
            }
        end
    end
end

local function DataKeyForShortName( shortName )
    for k, info in pairs( ZGRAD.SpawnPointsList or {} ) do
        if info[1] == shortName then return k end
    end
end

net.Receive( "zgrad_pt_select", function()
    local pointType = net.ReadString()
    local index     = net.ReadUInt( 16 )

    local key  = DataKeyForShortName( pointType )
    local info = key and ZGRAD.SpawnPointsList and ZGRAD.SpawnPointsList[key]
    if not info then return end

    local pts = info[3]
    if not pts or not pts[index] then return end

    local p = ZGRAD.ReadPoint( pts[index] )
    selectedPoint = {
        pointType = pointType,
        index     = index,
        pos       = p[1],
        ang       = p[2],
    }
end )

net.Receive( "zgrad_pt_select_deny", function()
    surface.PlaySound( "buttons/button10.wav" )
    chat.AddText( Color( 255, 80, 80 ), "[ZGRAD]", color_white, " Cannot select Hammer-placed points." )
end )

local function IsToolActive()
    local ply = LocalPlayer()
    if not IsValid( ply ) then return false end
    local wep = ply:GetActiveWeapon()
    if not IsValid( wep ) then return false end
    if wep:GetClass() ~= "gmod_tool" then return false end
    return ply:GetInfo( "gmod_toolmode" ) == TOOL_NAME
end

local _eyePos = Vector()
local _eyeFwd = Vector()

local function FindClosestPointToScreen( screenX, screenY, maxDistSq )
    local best, bestDistSq = nil, maxDistSq or math.huge

    for _, entry in ipairs( pointCache ) do
        if entry.hammer then continue end

        local pos = entry.pos
        if pos:DistToSqr( _eyePos ) > RENDER_DIST_SQ then continue end

        local dx = pos.x - _eyePos.x
        local dy = pos.y - _eyePos.y
        local dz = pos.z - _eyePos.z
        if _eyeFwd.x * dx + _eyeFwd.y * dy + _eyeFwd.z * dz <= 0 then continue end

        local sp = pos:ToScreen()
        if not sp.visible then continue end

        local sdx = sp.x - screenX
        local sdy = sp.y - screenY
        local dSq = sdx * sdx + sdy * sdy

        if dSq < bestDistSq then
            bestDistSq = dSq
            best = entry
        end
    end

    return best
end

local ringCache = {}

local function GetRingVerts( radius, segs )
    local key = radius .. "_" .. segs
    if ringCache[key] then return ringCache[key] end

    local verts = {}
    local step  = ( math.pi * 2 ) / segs
    for i = 0, segs do
        local a = i * step
        verts[i + 1] = { math.cos( a ), math.sin( a ) }
    end
    ringCache[key] = verts
    return verts
end

local _rp1 = Vector()
local _rp2 = Vector()

local function DrawGroundRing( pos, radius, col, segs )
    local verts = GetRingVerts( radius, segs )
    local pz    = pos.z
    render.SetColorMaterial()
    for i = 1, #verts - 1 do
        local v1 = verts[i]
        local v2 = verts[i + 1]
        _rp1.x = pos.x + v1[1] * radius  _rp1.y = pos.y + v1[2] * radius  _rp1.z = pz
        _rp2.x = pos.x + v2[1] * radius  _rp2.y = pos.y + v2[2] * radius  _rp2.z = pz
        render.DrawLine( _rp1, _rp2, col, true )
    end
end

local function DrawDirectionArrow( pos, ang, color )
    local base = pos + Vector( 0, 0, 4 )
    local fwd  = ang:Forward()
    local rgt  = ang:Right()
    fwd.z = 0
    rgt.z = 0

    local tip  = base + fwd * ARROW_LENGTH
    local back = tip  - fwd * ARROW_HEAD

    render.SetColorMaterial()
    render.DrawLine( base, tip,                        color, true )
    render.DrawLine( tip,  back + rgt * ARROW_HEAD_WING, color, true )
    render.DrawLine( tip,  back - rgt * ARROW_HEAD_WING, color, true )
end

local FADE_START_SQ = FADE_START * FADE_START

local function DistAlpha( distSq )
    if distSq <= FADE_START_SQ then return 1 end
    local dist = math.sqrt( distSq )
    return 1 - ( dist - FADE_START ) / FADE_RANGE
end

local function DrawAllPoints()
    for _, entry in ipairs( pointCache ) do
        local pos    = entry.pos
        local distSq = pos:DistToSqr( _eyePos )
        if distSq > RENDER_DIST_SQ then continue end

        local dx = pos.x - _eyePos.x
        local dy = pos.y - _eyePos.y
        local dz = pos.z - _eyePos.z
        if _eyeFwd.x * dx + _eyeFwd.y * dy + _eyeFwd.z * dz <= 0 then continue end

        local fade = DistAlpha( distSq )

        local col, solidAlpha, fadeAlpha
        if entry.hammer then
            col        = HAMMER_COLOR
            solidAlpha = math.floor( 80 * fade )
            fadeAlpha  = math.floor( 15 * fade )
        else
            local isSel = selectedPoint
                and selectedPoint.pointType == entry.typeName
                and selectedPoint.index     == entry.dataIndex
            local isHov = hoveredPoint
                and hoveredPoint.typeName  == entry.typeName
                and hoveredPoint.dataIndex == entry.dataIndex

            col        = isSel and SELECTED_COLOR or ( isHov and HOVER_COLOR or entry.baseColor )
            solidAlpha = math.floor( 200 * fade )
            fadeAlpha  = math.floor(  40 * fade )
        end

        render.SetColorMaterial()

        if entry.typeName == "control_point" then
            render.DrawWireframeSphere( pos, entry.gameRadius, SPHERE_SEGS, SPHERE_SEGS,
                MutColor( col, fadeAlpha ) )
            DrawGroundRing( pos, entry.gameRadius, MutColor( col, solidAlpha ), 48 )
        else
            DrawGroundRing( pos, entry.gameRadius, MutColor( col, fadeAlpha ), 16 )
        end

        render.DrawSphere( pos, 4, 8, 8, MutColor( col, solidAlpha ) )
        DrawDirectionArrow( pos, entry.ang, MutColor( col, solidAlpha ) )
    end
end

local function GetPlacementPos( ply )
    if ply:GetInfo( "zgrad_point_tool_place_mode" ) == "self" then
        return ply:GetPos()
    end

    local tr = util.TraceLine({
        start  = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 1024,
        filter = ply,
    })
    return tr.Hit and ( tr.HitPos + Vector( 0, 0, 5 ) ) or nil
end

local function DrawGhostPreview()
    local ply  = LocalPlayer()
    local mode = ply:GetInfo( "zgrad_point_tool_mode" )

    local typeName, pos
    if mode == "place" then
        typeName = ply:GetInfo( "zgrad_point_tool_point_type" )
        pos = GetPlacementPos( ply )
    elseif mode == "select" and selectedPoint then
        typeName = selectedPoint.pointType
        pos = GetPlacementPos( ply )
    end

    if not pos then return end

    local col        = typeColorCache[typeName] or color_white
    local gameRadius = TYPE_RADIUS[typeName] or DEFAULT_SPAWN_RADIUS
    local ang        = Angle( 0, ply:EyeAngles().y, 0 )

    render.SetColorMaterial()

    if typeName == "control_point" then
        render.DrawWireframeSphere( pos, gameRadius, SPHERE_SEGS, SPHERE_SEGS,
            MutColor( col, 25 ) )
        DrawGroundRing( pos, gameRadius, MutColor( col, 160 ), 48 )
    else
        DrawGroundRing( pos, gameRadius, MutColor( col, 80 ), 16 )
    end

    render.DrawSphere( pos, 4, 8, 8, MutColor( col, 160 ) )
    DrawDirectionArrow( pos, ang, MutColor( col, 160 ) )

    if mode == "select" and selectedPoint and selectedPoint.pos then
        local from  = selectedPoint.pos
        local steps = 8
        render.SetColorMaterial()
        for s = 0, steps - 1, 2 do
            render.DrawLine(
                LerpVector( s / steps,       from, pos ),
                LerpVector( ( s + 1 ) / steps, from, pos ),
                MutColor( col, 120 ), true
            )
        end
    end
end

local function DrawScreenLabels()
    local plyPos = LocalPlayer():GetPos()

    for _, entry in ipairs( pointCache ) do
        local pos    = entry.pos
        local distSq = pos:DistToSqr( plyPos )
        if distSq > LABEL_DIST_SQ then continue end

        local sp = pos:ToScreen()
        if not sp.visible then continue end

        local fade = DistAlpha( distSq )

        local col, label
        if entry.hammer then
            col   = HAMMER_COLOR
            label = entry.typeName .. " #" .. entry.dataIndex .. " [H]"
        else
            local isSel = selectedPoint
                and selectedPoint.pointType == entry.typeName
                and selectedPoint.index     == entry.dataIndex
            local isHov = hoveredPoint
                and hoveredPoint.typeName  == entry.typeName
                and hoveredPoint.dataIndex == entry.dataIndex

            col   = isSel and SELECTED_COLOR or ( isHov and HOVER_COLOR or entry.baseColor )
            label = entry.typeName .. " #" .. entry.dataIndex

            local tw = #label * 6 + 10
            draw.RoundedBox( 4, sp.x - tw / 2, sp.y - 22, tw, 14,
                MutColor( LABEL_BG, math.floor( 160 * fade ) ) )
            draw.SimpleText( label, "DefaultFixedDropShadow", sp.x, sp.y - 15,
                MutColor( col, math.floor( 220 * fade ) ),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

            if isSel then
                draw.SimpleText( "SELECTED", "DefaultFixedDropShadow", sp.x, sp.y - 2,
                    MutColor( SELECTED_COLOR, math.floor( 220 * fade ) ),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
            end
            continue
        end

        draw.SimpleText( label, "DefaultFixedDropShadow", sp.x, sp.y - 15,
            MutColor( col, math.floor( 140 * fade ) ),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end
end

hook.Add( "PlayerButtonDown", "ZGrad_PointToolSelectInput", function( ply, button )
    if ply ~= LocalPlayer() then return end
    if not IsToolActive() then return end
    if button ~= MOUSE_LEFT then return end
    if ply:GetInfo( "zgrad_point_tool_mode" ) ~= "select" then return end
    if selectedPoint then return end

    local nearest = FindClosestPointToScreen( ScrW() / 2, ScrH() / 2, HOVER_RADIUS_SQ * 4 )
    if not nearest then return end

    net.Start( "zgrad_pt_select_sv" )
        net.WriteString( nearest.typeName )
        net.WriteUInt( nearest.dataIndex, 16 )
    net.SendToServer()
end )

hook.Add( "PlayerButtonDown", "ZGrad_PointToolDeselect", function( ply, button )
    if ply ~= LocalPlayer() then return end
    if not IsToolActive() then return end
    if button ~= KEY_R then return end
    selectedPoint = nil
end )

hook.Add( "WeaponEquipped", "ZGrad_PointToolClearOnSwitch", function( wep, ply )
    if not IsValid( ply ) or ply ~= LocalPlayer() then return end
    if IsValid( wep ) and wep:GetClass() ~= "gmod_tool" then
        selectedPoint = nil
        hoveredPoint  = nil
    end
end )

hook.Add( "ZGrad_SpawnPointsUpdated", "ZGrad_ClearOnSpawnPointsUpdate", function()
    selectedPoint = nil
    hoveredPoint  = nil
    RebuildCache()
end )

hook.Add( "PostDrawTranslucentRenderables", "ZGrad_PointToolDraw3D", function( bDepth, bSkybox )
    if bDepth or bSkybox then return end
    if not IsToolActive() then return end

    local ply = LocalPlayer()
    local eyeAng = ply:EyeAngles()
    local eyePos = ply:EyePos()
    _eyePos:Set( eyePos )
    _eyeFwd:Set( eyeAng:Forward() )

    hoveredPoint = FindClosestPointToScreen( ScrW() / 2, ScrH() / 2, HOVER_RADIUS_SQ )

    DrawAllPoints()
    DrawGhostPreview()
end )

hook.Add( "HUDPaint", "ZGrad_PointToolDraw2D", function()
    if not IsToolActive() then return end

    DrawScreenLabels()

    local ply       = LocalPlayer()
    local mode      = ply:GetInfo( "zgrad_point_tool_mode" )
    local placeMode = ply:GetInfo( "zgrad_point_tool_place_mode" )
    local typeName  = ply:GetInfo( "zgrad_point_tool_point_type" )
    local sw, sh    = ScrW(), ScrH()

    local originTxt = placeMode == "self" and "Self" or "Surface"
    local modeLabel = mode == "place" and "Place" or "Select"

    local margin  = 14
    local pad     = 16
    local lineGap = 10

    local l1 = "Map Point Editor"
    local l2 = "Mode: " .. modeLabel
    local l3 = "Origin: " .. originTxt
    local l4 = "Type: " .. ( typeName or "?" )

    surface.SetFont( PANEL_FONT )
    local _, fh = surface.GetTextSize( "M" )
    local w = math.max(
        surface.GetTextSize( l1 ),
        surface.GetTextSize( l2 ),
        surface.GetTextSize( l3 ),
        surface.GetTextSize( l4 )
    )

    local panelW = w + pad * 2
    local panelH = pad * 2 + 4 * fh + 3 * lineGap
    local bx     = sw - panelW - margin
    local by     = margin

    surface.SetDrawColor( 0, 0, 0, 160 )
    surface.DrawRect( bx, by, panelW, panelH )

    local tx = bx + pad
    local ty = by + pad
    draw.SimpleText( l1, PANEL_FONT, tx, ty, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
    ty = ty + fh + lineGap
    draw.SimpleText( l2, PANEL_FONT, tx, ty, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
    ty = ty + fh + lineGap
    draw.SimpleText( l3, PANEL_FONT, tx, ty, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
    ty = ty + fh + lineGap
    draw.SimpleText( l4, PANEL_FONT, tx, ty, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

    if selectedPoint then
        local label = "Selected: " .. selectedPoint.pointType .. " #" .. selectedPoint.index
        if mode == "select" then
            label = label .. " — LMB move, RMB delete"
        end

        surface.SetFont( PANEL_FONT )
        local tw = surface.GetTextSize( label )
        local barW = tw + pad * 2
        local barH = fh + pad * 2
        local sx = sw / 2
        local sy = sh / 2 + 24

        surface.SetDrawColor( 0, 0, 0, 160 )
        surface.DrawRect( sx - barW / 2, sy, barW, barH )
        draw.SimpleText( label, PANEL_FONT, sx, sy + barH / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end
end )

RebuildCache()
