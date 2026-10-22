-- ============================================================
-- Column Tied Reinforcement With Overhangs And Zones
-- ============================================================
-- Минимальный зазор между стержнями в свету по СП 63.13330.2018 (мм)
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
-- Поддерживает углы отгиба 135° и 180°
-- ============================================================
function createClosedStirrupCurve(point3D, rebarsCenterWidth, rebarsCenterDepth, angle, bendLengthD, rebarStyleId, longRebarStyleId, bendAngleDeg)
    local longR = getRebarRadius(longRebarStyleId)
    local r = getRebarRadius(rebarStyleId)

    -- Радиус оси гиба хомута по СП 63
    local rBending = math.max(3.5 * r, longR + r)
    local lBend = bendLengthD * r * 2

    -- Радиальное смещение центра дуги гиба от центра углового стержня под 45°
    local shiftRadial = rBending - (longR + r)
    local shiftXY = shiftRadial * math.cos(math.pi / 4)

    local x0 = point3D:GetX()
    local y0 = point3D:GetY()
    local z0 = point3D:GetZ()

    local W = rebarsCenterWidth
    local D = rebarsCenterDepth

    -- Центры дуг 4 углов со смещением строго по биссектрисам углов
    local c1 = Point3D(x0 + shiftXY,     y0 + shiftXY,     z0)          -- Низ-лево (Z = 0)
    local c2 = Point3D(x0 + W - shiftXY, y0 + shiftXY,     z0)          -- Низ-право (Z = 0)
    local c3 = Point3D(x0 + W - shiftXY, y0 + D - shiftXY, z0 + 2 * r)  -- Верх-право (Z = 2*r)
    local c4 = Point3D(x0 + shiftXY,     y0 + D - shiftXY, z0 + 2 * r)  -- Верх-лево (Z = 2*r)

    local rotateAxis = Axis3D(point3D, Vector3D(0, 0, 1))

    if not bendAngleDeg then
        bendAngleDeg = 135
    end

    -- ============================================================
    -- 1. НАЧАЛЬНЫЙ КРЮК (Угол c1, Z = z0)
    -- ============================================================
    local axis1 = Axis3D(c1, Vector3D(0, 0, 1))
    local p3 = c1:Clone():Shift(0, -rBending, 0)         -- Выход в нижнюю грань хомута
    local p2 = c1:Clone():Shift(-rBending, 0, 0)         -- Конец дуги для угла 90°
    local p1 = p2:Clone():Shift(0, lBend, 0)             -- Кончик крюка для угла 90°

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

    local startHook = CreateCompositeCurve3D({
        CreateLineSegment3D(p1, p2),
        CreateArc3DByThreePoints(p2, p_mid1, p3)
    })

    -- ============================================================
    -- 2. ОБХОД РАМКИ ПО 4 УГЛАМ
    -- ============================================================
    -- Угол 2 (Правый нижний, Z = z0)
    local arc2_start = c2:Clone():Shift(0, -rBending, 0)
    local arc2_end   = c2:Clone():Shift(rBending, 0, 0)
    local axis2      = Axis3D(c2, Vector3D(0, 0, 1))
    local arc2_mid   = arc2_start:Clone():Rotate(axis2, math.pi / 4)
    local arc2       = CreateArc3DByThreePoints(arc2_start, arc2_mid, arc2_end)

    -- Угол 3 (Правый верхний, Z = z0 + 2*r)
    local arc3_start = c3:Clone():Shift(rBending, 0, 0)
    local arc3_end   = c3:Clone():Shift(0, rBending, 0)
    local axis3      = Axis3D(c3, Vector3D(0, 0, 1))
    local arc3_mid   = arc3_start:Clone():Rotate(axis3, math.pi / 4)
    local arc3       = CreateArc3DByThreePoints(arc3_start, arc3_mid, arc3_end)

    -- Угол 4 (Левый верхний, Z = z0 + 2*r)
    local arc4_start = c4:Clone():Shift(0, rBending, 0)
    local arc4_end   = c4:Clone():Shift(-rBending, 0, 0)
    local axis4      = Axis3D(c4, Vector3D(0, 0, 1))
    local arc4_mid   = arc4_start:Clone():Rotate(axis4, math.pi / 4)
    local arc4       = CreateArc3DByThreePoints(arc4_start, arc4_mid, arc4_end)

    -- Точка прихода левой грани обратно к углу 1 на высоте Z = z0 + 2*r
    local endL = Point3D(c1:GetX() - rBending, c1:GetY(), z0 + 2 * r)

    -- ============================================================
    -- 3. ЗАМЫКАЮЩИЙ КРЮК (Угол c1_top, Z = z0 + 2*r)
    -- ============================================================
    local c1_top = Point3D(c1:GetX(), c1:GetY(), z0 + 2 * r)
    local axis1_top = Axis3D(c1_top, Vector3D(0, 0, 1))

    -- Базовые точки для 90°: от endL (-rBending, 0) дуга идет к (0, -rBending)
    local q2 = c1_top:Clone():Shift(0, -rBending, 0)     -- Конец дуги для 90°
    local q1 = q2:Clone():Shift(lBend, 0, 0)             -- Прямой кончик для 90°

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

    local endHook = CreateCompositeCurve3D({
        CreateArc3DByThreePoints(endL, q_mid, q2),
        CreateLineSegment3D(q2, q1)
    })

    -- ============================================================
    -- 4. СБОРКА ПОЛНОГО ХОМУТА
    -- ============================================================
    local stirrupCurve = CreateCompositeCurve3D({
        startHook,                                      -- Начальный крюк
        CreateLineSegment3D(p3, arc2_start),            -- Нижняя грань (Z = z0)
        arc2,                                           -- Правый нижний гибочный угол
        CreateLineSegment3D(arc2_end, arc3_start),      -- Правая грань (подъем на 2*r)
        arc3,                                           -- Правый верхний гибочный угол
        CreateLineSegment3D(arc3_end, arc4_start),      -- Верхняя грань (Z = z0 + 2*r)
        arc4,                                           -- Левый верхний гибочный угол
        CreateLineSegment3D(arc4_end, endL),            -- Левая грань (Z = z0 + 2*r)
        endHook                                         -- Замыкающий крюк
    })

    return stirrupCurve:Rotate(rotateAxis, angle)
end


-- ============================================================
-- Очищенная раскладка стержней строго от zoneBottom до zoneTop по осям
-- ============================================================
function createRebarLayoutWithDobor(container, rebarStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
    longStyleId, zoneBottom, zoneTop, step, useDobor)
    local r = getRebarRadius(rebarStyleId)

    local function addStirrupAt(z)
        local anchor = Point3D(-rebarsCenterWidth / 2, -rebarsCenterDepth / 2, z)
        local curve = createClosedStirrupCurve(anchor, rebarsCenterWidth, rebarsCenterDepth, 0, bendFactor,
            rebarStyleId, longStyleId, 135)
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

-- ============================================================
-- Раскладка хомутов по высоте с учетом зон (Строго по осям)
-- ============================================================
function createTransverseStirrups(container, styleParameters, cornerX, cornerY, columnHeight)
    local transParams = styleParameters.TransverseRebars
    local stirrupStyleId = transParams.ClosedStirrupStyleId
    local bendFactor = transParams.BendLengthFactor
    local mainStep = transParams.MiddleZoneFirstStep

    local general = styleParameters.General
    local zones = general.ReinforcementZones

    local longParams = styleParameters.LongitudinalRebars
    local longStyleId = longParams.CornerRebarStyleId
    local freeEnd = longParams.FreeEnd

    local rebarsCenterWidth = 2 * cornerX
    local rebarsCenterDepth = 2 * cornerY

    local r = getRebarRadius(stirrupStyleId)

    -- 1. Нижняя ось каркаса неизменна
    local Z_axis_bottom = general.BottomCover + freeEnd + r

    -- 2. Динамический расчет верхнего отступа хомута (свободный конец или свободный конец + TopCover)
    local totalTopOffset = freeEnd
    if longParams.TopOverhangEnabled == "no" then
        totalTopOffset = totalTopOffset + general.TopCover
    end

    -- Итоговая верхняя координата оси с учетом фактора отступа нахлеста хомута (3 * r)
    local Z_axis_top = columnHeight - totalTopOffset - (3 * r)

    -- Считываем проектные абсолютные оси границ зон
    local isZonesValid = true
    local topZoneSize = 0
    local bottomZoneSize = 0

    if zones == "top" or zones == "both" then
        topZoneSize = styleParameters.TopZone.ZoneSize
    end
    if zones == "bottom" or zones == "both" then
        bottomZoneSize = styleParameters.BottomZone.ZoneSize
    end

    -- Защита от дурака: аварийный сброс в основную зону при пересечении зон
    if (bottomZoneSize + topZoneSize) >= columnHeight then
        isZonesValid = false
        zones = "none"
    end

    -- ============================================================
    -- Раскладка хомутов по комбинациям (Строго по осям)
    -- ============================================================

    -- 1. Зоны усиления отсутствуют (none) или аварийный сброс
    if zones == "none" then
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, Z_axis_bottom, Z_axis_top, mainStep, true)

        -- 2. Усиление только сверху (top)
    elseif zones == "top" and isZonesValid then
        local topZoneStep = styleParameters.TopZone.Step
        local axisBorderTop = columnHeight - topZoneSize

        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, Z_axis_bottom, axisBorderTop, mainStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, axisBorderTop, Z_axis_top, topZoneStep, true)

        -- 3. Усиление только снизу (bottom)
    elseif zones == "bottom" and isZonesValid then
        local bottomZoneStep = styleParameters.BottomZone.Step
        local axisBorderBottom = bottomZoneSize

        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, Z_axis_bottom, axisBorderBottom, bottomZoneStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, axisBorderBottom, Z_axis_top, mainStep, true)

        -- 4. Усиление и сверху, и снизу (both)
    elseif zones == "both" and isZonesValid then
        local bottomZoneStep = styleParameters.BottomZone.Step
        local topZoneStep = styleParameters.TopZone.Step
        local axisBorderBottom = bottomZoneSize
        local axisBorderTop = columnHeight - topZoneSize

        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, Z_axis_bottom, axisBorderBottom, bottomZoneStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, axisBorderBottom, axisBorderTop, mainStep, false)
        createRebarLayoutWithDobor(container, stirrupStyleId, rebarsCenterWidth, rebarsCenterDepth, bendFactor,
            longStyleId, axisBorderTop, Z_axis_top, topZoneStep, true)
    end
end

-- ============================================================
-- Создание продольных стержней
-- ============================================================
function createLongitudinalRebars(container, styleParameters, cornerX, cornerY, zBottom, zTop)
    local longParams = styleParameters.LongitudinalRebars
    local cornerStyleId = longParams.CornerRebarStyleId
    local curve = CreateLineSegment3D(Point3D(0, 0, zBottom), Point3D(0, 0, zTop))
    local corners = {{
        x = -cornerX,
        y = -cornerY
    }, {
        x = -cornerX,
        y = cornerY
    }, {
        x = cornerX,
        y = -cornerY
    }, {
        x = cornerX,
        y = cornerY
    }}
    for _, c in ipairs(corners) do
        container:AddRebar(cornerStyleId, curve:Clone():Shift(c.x, c.y, 0))
    end
end
-- ============================================================
-- Основная функция плагина Renga STDL
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
    local zBottom = general.BottomCover
    local zTop = columnHeight - general.TopCover
    local longParams = styleParameters.LongitudinalRebars
    if longParams.TopOverhangEnabled == "yes" then
        local longRebarRadius = getRebarRadius(longParams.CornerRebarStyleId)
        local anchorageFactor = longParams.AnchorageFactor
        zTop = zTop + longRebarRadius * 2 * anchorageFactor
    end
    if zTop <= zBottom then
        return result
    end
    -- 1. Продольные стержни
    createLongitudinalRebars(result, styleParameters, cornerX, cornerY, zBottom, zTop)
    -- 2. Поперечные хомуты
    createTransverseStirrups(result, styleParameters, cornerX, cornerY, columnHeight)
    return result
end
