-- ============================================================
-- Column Tied Reinforcement With Overhangs, Zones And Intermediate Rebars
-- ============================================================
local MIN_REBAR_CLEARANCE = 25

function SetStyleParameterStates(parameters)
    local values = parameters:GetParameterValues()
    local zones = values.General.ReinforcementZones
    local transZones = values.TransverseRebars.ReinforcementZones

    local showTopZone = (zones == "top" or zones == "both") or (transZones == "top" or transZones == "both")
    local showBottomZone = (zones == "bottom" or zones == "both") or (transZones == "bottom" or transZones == "both")

    parameters:GetParameterGroup("TopZone"):SetVisible(showTopZone)
    parameters:GetParameterGroup("BottomZone"):SetVisible(showBottomZone)
end

function getRebarRadius(rebarStyleId)
    local style = GetRebarStyle(rebarStyleId)
    return GetParameterValue(style, "RebarDiameter") / 2
end

-- ============================================================
-- Полный O-образный замкнутый хомут с начальным и конечным крюками
-- ============================================================
function createClosedStirrupCurve(point3D, rebarsCenterWidth, rebarsCenterDepth, angle, bendLengthD, rebarStyleId,
    longRebarStyleId, bendAngleDeg)
    local longR = getRebarRadius(longRebarStyleId)
    local r = getRebarRadius(rebarStyleId)

    local rBending = math.max(3.5 * r, longR + r)
    local lBend = bendLengthD * r * 2

    local shiftRadial = rBending - (longR + r)
    local shiftXY = shiftRadial * math.cos(math.pi / 4)

    local x0 = point3D:GetX()
    local y0 = point3D:GetY()
    local z0 = point3D:GetZ()

    local W = rebarsCenterWidth
    local D = rebarsCenterDepth

    local c1 = Point3D(x0 + shiftXY, y0 + shiftXY, z0)
    local c2 = Point3D(x0 + W - shiftXY, y0 + shiftXY, z0)
    local c3 = Point3D(x0 + W - shiftXY, y0 + D - shiftXY, z0 + 2 * r)
    local c4 = Point3D(x0 + shiftXY, y0 + D - shiftXY, z0 + 2 * r)

    local rotateAxis = Axis3D(point3D, Vector3D(0, 0, 1))

    -- 1. Начальный крюк
    local axis1 = Axis3D(c1, Vector3D(0, 0, 1))
    local p3 = c1:Clone():Shift(0, -rBending, 0)
    local p2 = c1:Clone():Shift(-rBending, 0, 0)
    local p1 = p2:Clone():Shift(0, lBend, 0)

    if bendAngleDeg == 135 then
        p2:Rotate(axis1, -math.pi / 4)
        p1:Rotate(axis1, -math.pi / 4)
    elseif bendAngleDeg == 180 then
        p2:Rotate(axis1, -math.pi / 2)
        p1:Rotate(axis1, -math.pi / 2)
    else
        local rotRad = -math.rad(bendAngleDeg - 90)
        p2:Rotate(axis1, rotRad)
        p1:Rotate(axis1, rotRad)
    end

    local p_mid1 = p3:Clone():Rotate(axis1, -math.rad(bendAngleDeg / 2))

    local startHook = CreateCompositeCurve3D({CreateLineSegment3D(p1, p2), CreateArc3DByThreePoints(p2, p_mid1, p3)})

    -- 2. Обход рамки
    local arc2_start = c2:Clone():Shift(0, -rBending, 0)
    local arc2_end = c2:Clone():Shift(rBending, 0, 0)
    local axis2 = Axis3D(c2, Vector3D(0, 0, 1))
    local arc2_mid = arc2_start:Clone():Rotate(axis2, math.pi / 4)
    local arc2 = CreateArc3DByThreePoints(arc2_start, arc2_mid, arc2_end)

    local arc3_start = c3:Clone():Shift(rBending, 0, 0)
    local arc3_end = c3:Clone():Shift(0, rBending, 0)
    local axis3 = Axis3D(c3, Vector3D(0, 0, 1))
    local arc3_mid = arc3_start:Clone():Rotate(axis3, math.pi / 4)
    local arc3 = CreateArc3DByThreePoints(arc3_start, arc3_mid, arc3_end)

    local arc4_start = c4:Clone():Shift(0, rBending, 0)
    local arc4_end = c4:Clone():Shift(-rBending, 0, 0)
    local axis4 = Axis3D(c4, Vector3D(0, 0, 1))
    local arc4_mid = arc4_start:Clone():Rotate(axis4, math.pi / 4)
    local arc4 = CreateArc3DByThreePoints(arc4_start, arc4_mid, arc4_end)

    local endL = Point3D(c1:GetX() - rBending, c1:GetY(), z0 + 2 * r)

    -- 3. Замыкающий крюк
    local c1_top = Point3D(c1:GetX(), c1:GetY(), z0 + 2 * r)
    local axis1_top = Axis3D(c1_top, Vector3D(0, 0, 1))

    local q2 = c1_top:Clone():Shift(0, -rBending, 0)
    local q1 = q2:Clone():Shift(lBend, 0, 0)

    if bendAngleDeg == 135 then
        q2:Rotate(axis1_top, math.pi / 4)
        q1:Rotate(axis1_top, math.pi / 4)
    elseif bendAngleDeg == 180 then
        q2:Rotate(axis1_top, math.pi / 2)
        q1:Rotate(axis1_top, math.pi / 2)
    else
        local rotRad = math.rad(bendAngleDeg - 90)
        q2:Rotate(axis1_top, rotRad)
        q1:Rotate(axis1_top, rotRad)
    end

    local q_mid = endL:Clone():Rotate(axis1_top, math.rad(bendAngleDeg / 2))

    local endHook = CreateCompositeCurve3D({CreateArc3DByThreePoints(endL, q_mid, q2), CreateLineSegment3D(q2, q1)})

    -- 4. Сборка хомута
    local stirrupCurve = CreateCompositeCurve3D({startHook, CreateLineSegment3D(p3, arc2_start), arc2,
                                                 CreateLineSegment3D(arc2_end, arc3_start), arc3,
                                                 CreateLineSegment3D(arc3_end, arc4_start), arc4,
                                                 CreateLineSegment3D(arc4_end, endL), endHook})

    return stirrupCurve:Rotate(rotateAxis, angle)
end

-- ============================================================
-- Раскладка хомутов
-- ============================================================
function createRebarLayoutWithDobor(container, rebarStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
    bendAngleDeg, longStyleId, zoneBottom, zoneTop, step, useDobor)
    local r = getRebarRadius(rebarStyleId)

    local function addStirrupAt(z)
        local anchor = Point3D(-rebarsCenterWidth / 2, -rebarsCenterDepth / 2, z)
        local curve = createClosedStirrupCurve(anchor, rebarsCenterWidth, rebarsCenterDepth, 0, bendFactor,
            rebarStyleId, longStyleId, bendAngleDeg)
        container:AddRebar(rebarStyleId, curve)
    end

    if zoneTop <= zoneBottom then
        return
    end

    local length = zoneTop - zoneBottom
    local layoutCount = math.floor(length / step)
    local remainder = length - step * layoutCount

    if remainder < r * 2 then
        layoutCount = layoutCount - 1
    end

    local regularCount = layoutCount + 1

    if useDobor then
        local lastLayoutZ = zoneBottom + (regularCount - 1) * step
        local minDistance = 3 * r + MIN_REBAR_CLEARANCE
        if (zoneTop - lastLayoutZ) < minDistance then
            regularCount = regularCount - 1
        end
        addStirrupAt(zoneTop)
    end

    for i = 1, regularCount do
        addStirrupAt(zoneBottom + (i - 1) * step)
    end
end

function createTransverseStirrups(container, styleParameters, cornerX, cornerY, columnHeight)
    local transParams = styleParameters.TransverseRebars
    local stirrupStyleId = transParams.ClosedStirrupStyleId
    local bendFactor = transParams.BendLengthFactor
    local mainStep = transParams.MiddleZoneFirstStep
    local bendAngleDeg = tonumber(transParams.BendAngle)

    local general = styleParameters.General
    local zones = general.ReinforcementZones

    local longParams = styleParameters.LongitudinalRebars
    local longStyleId = longParams.CornerRebarStyleId
    local freeEnd = longParams.FreeEnd

    local rebarsCenterWidth = 2 * cornerX
    local rebarsCenterDepth = 2 * cornerY

    local r = getRebarRadius(stirrupStyleId)

    local Z_axis_bottom = general.BottomCover + freeEnd + r

    local totalTopOffset = freeEnd
    if longParams.TopOverhangEnabled == "no" then
        totalTopOffset = totalTopOffset + general.TopCover
    end

    local Z_axis_top = columnHeight - totalTopOffset - (3 * r)

    local isZonesValid = true
    local topZoneSize = 0
    local bottomZoneSize = 0

    if zones == "top" or zones == "both" then
        topZoneSize = styleParameters.TopZone.ZoneSize
    end
    if zones == "bottom" or zones == "both" then
        bottomZoneSize = styleParameters.BottomZone.ZoneSize
    end

    if (bottomZoneSize + topZoneSize) >= columnHeight then
        isZonesValid = false
        zones = "none"
    end

    if zones == "none" then
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, Z_axis_bottom, Z_axis_top, mainStep, true)
    elseif zones == "top" and isZonesValid then
        local topZoneStep = styleParameters.TopZone.Step
        local axisBorderTop = columnHeight - topZoneSize

        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, Z_axis_bottom, axisBorderTop, mainStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, axisBorderTop, Z_axis_top, topZoneStep, true)
    elseif zones == "bottom" and isZonesValid then
        local bottomZoneStep = styleParameters.BottomZone.Step
        local axisBorderBottom = bottomZoneSize

        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, Z_axis_bottom, axisBorderBottom, bottomZoneStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, axisBorderBottom, Z_axis_top, mainStep, true)
    elseif zones == "both" and isZonesValid then
        local bottomZoneStep = styleParameters.BottomZone.Step
        local topZoneStep = styleParameters.TopZone.Step
        local axisBorderBottom = bottomZoneSize
        local axisBorderTop = columnHeight - topZoneSize

        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, Z_axis_bottom, axisBorderBottom, bottomZoneStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, axisBorderBottom, axisBorderTop, mainStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            bendAngleDeg, longStyleId, axisBorderTop, Z_axis_top, topZoneStep, true)
    end
end
-- ============================================================
-- Создание продольных стержней с разбежкой и промежуточными рядами
-- ============================================================
function createLongitudinalRebars(container, styleParameters, cornerX, cornerY, columnHeight)
    local general = styleParameters.General
    local longParams = styleParameters.LongitudinalRebars
    local cornerStyleId = longParams.CornerRebarStyleId
    local addStyleId = longParams.AdditionalRebarStyleId or cornerStyleId
    local bendOverhang = longParams.BendOverhang or "none"
    local useDisplacement = (longParams.UseOverhangDisplacement == "yes")
    local topOverhangEnabled = (longParams.TopOverhangEnabled == "yes")
    local maxStep = longParams.Step or 200
    local dispFactor = longParams.DisplacementFactor or 1.3
    -- Сбор массива стержней по контуру по часовой стрелке
    local rebarPositions = {}
    -- 1. Угол 1: Низ-лево
    table.insert(rebarPositions, {
        x = -cornerX,
        y = -cornerY,
        dirX = 1,
        dirY = 1,
        styleId = cornerStyleId
    })
    -- 2. Грань X (снизу): от -cornerX до cornerX при y = -cornerY
    local spanX = 2 * cornerX
    local countX = math.floor(spanX / maxStep)
    if (spanX % maxStep) == 0 and countX > 0 then
        countX = countX - 1
    end
    if countX > 0 then
        local stepX = spanX / (countX + 1)
        for i = 1, countX do
            table.insert(rebarPositions, {
                x = -cornerX + i * stepX,
                y = -cornerY,
                dirX = 0,
                dirY = 1,
                styleId = addStyleId
            })
        end
    end
    -- 3. Угол 2: Низ-право
    table.insert(rebarPositions, {
        x = cornerX,
        y = -cornerY,
        dirX = -1,
        dirY = 1,
        styleId = cornerStyleId
    })
    -- 4. Грань Y (справа): от -cornerY до cornerY при x = cornerX
    local spanY = 2 * cornerY
    local countY = math.floor(spanY / maxStep)
    if (spanY % maxStep) == 0 and countY > 0 then
        countY = countY - 1
    end
    if countY > 0 then
        local stepY = spanY / (countY + 1)
        for i = 1, countY do
            table.insert(rebarPositions, {
                x = cornerX,
                y = -cornerY + i * stepY,
                dirX = -1,
                dirY = 0,
                styleId = addStyleId
            })
        end
    end
    -- 5. Угол 3: Верх-право
    table.insert(rebarPositions, {
        x = cornerX,
        y = cornerY,
        dirX = -1,
        dirY = -1,
        styleId = cornerStyleId
    })
    -- 6. Грань X (сверху): от cornerX до -cornerX при y = cornerY
    if countX > 0 then
        local stepX = spanX / (countX + 1)
        for i = 1, countX do
            table.insert(rebarPositions, {
                x = cornerX - i * stepX,
                y = cornerY,
                dirX = 0,
                dirY = -1,
                styleId = addStyleId
            })
        end
    end
    -- 7. Угол 4: Верх-лево
    table.insert(rebarPositions, {
        x = -cornerX,
        y = cornerY,
        dirX = 1,
        dirY = -1,
        styleId = cornerStyleId
    })
    -- 8. Грань Y (слева): от cornerY до -cornerY при x = -cornerX
    if countY > 0 then
        local stepY = spanY / (countY + 1)
        for i = 1, countY do
            table.insert(rebarPositions, {
                x = -cornerX,
                y = cornerY - i * stepY,
                dirX = 1,
                dirY = 0,
                styleId = addStyleId
            })
        end
    end
    -- Построение каждого стержня
    for idx, pos in ipairs(rebarPositions) do
        local rStyleId = pos.styleId
        local longR = getRebarRadius(rStyleId)
        local d = 2 * longR
        local lAnch = d * longParams.AnchorageFactor
        local isShifted = (idx % 2 == 0)
        -- Нижняя отметка
        local zBottom = general.BottomCover
        if topOverhangEnabled and useDisplacement and isShifted then
            zBottom = general.BottomCover + lAnch * dispFactor
        end
        -- Верхняя отметка
        local zTop
        if topOverhangEnabled then
            if isShifted then
                zTop = columnHeight + lAnch * (1.0 + dispFactor)
            else
                zTop = columnHeight + lAnch
            end
        else
            zTop = columnHeight - general.TopCover
        end
        if zTop > zBottom then
            local hCrank = 6 * d
            local rBending = 2.5 * d
            local dx = pos.dirX * d
            local dy = pos.dirY * d
            local curve = nil
            if bendOverhang == "top" and topOverhangEnabled and (columnHeight - hCrank) > zBottom then
                local p1 = Point3D(pos.x, pos.y, zBottom)
                local p2 = Point3D(pos.x, pos.y, columnHeight - hCrank)
                local p3 = Point3D(pos.x + dx, pos.y + dy, columnHeight)
                local p4 = Point3D(pos.x + dx, pos.y + dy, zTop)
                local polyline = CreatePolyline3D({p1, p2, p3, p4})
                FilletCorners3D(polyline, rBending)
                curve = polyline
            elseif bendOverhang == "bottom" and (zBottom + lAnch + hCrank) < zTop then
                local p1 = Point3D(pos.x + dx, pos.y + dy, zBottom)
                local p2 = Point3D(pos.x + dx, pos.y + dy, zBottom + lAnch)
                local p3 = Point3D(pos.x, pos.y, zBottom + lAnch + hCrank)
                local p4 = Point3D(pos.x, pos.y, zTop)
                local polyline = CreatePolyline3D({p1, p2, p3, p4})
                FilletCorners3D(polyline, rBending)
                curve = polyline
            else
                curve = CreateLineSegment3D(Point3D(pos.x, pos.y, zBottom), Point3D(pos.x, pos.y, zTop))
            end
            container:AddRebar(rStyleId, curve)
        end
    end
end
-- ============================================================
-- Точка входа CreateObjectReinforcement
-- ============================================================
function CreateObjectReinforcement(object, styleParameters)
    local result = ReinforcementContainer()
    local profile = GetSectionProfile(object)
    if GetTypeName(profile) ~= "RectangularProfile" then
        return result
    end
    local halfWidth = profile.Width / 2
    local halfDepth = profile.Height / 2
    local general = styleParameters.General
    local axisDistance = general.AxisDistanceSide
    local cornerX = halfWidth - axisDistance
    local cornerY = halfDepth - axisDistance
    if cornerX <= 0 or cornerY <= 0 then
        return result
    end
    local columnHeight = GetParameterValue(object, "ColumnHeight")
    createLongitudinalRebars(result, styleParameters, cornerX, cornerY, columnHeight)
    createTransverseStirrups(result, styleParameters, cornerX, cornerY, columnHeight)
    return result
end
