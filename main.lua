-- ============================================================
-- Column Tied Reinforcement With Overhangs, Zones, Ties and Internal Stirrups
-- ============================================================
local MIN_REBAR_CLEARANCE = 25

-- 1. УПРАВЛЕНИЕ ПАРАМЕТРАМИ

function SetStyleParameterStates(parameters)
    local values = parameters:GetParameterValues()
    local zones = values.General.ReinforcementZones
    local transZones = values.TransverseRebars.ReinforcementZones

    local showTopZone = (zones == "top" or zones == "both") or (transZones == "top" or transZones == "both")
    local showBottomZone = (zones == "bottom" or zones == "both") or (transZones == "bottom" or transZones == "both")

    local grpTop = parameters:GetParameterGroup("TopZone")
    if grpTop then grpTop:SetVisible(showTopZone) end
    local grpBottom = parameters:GetParameterGroup("BottomZone")
    if grpBottom then grpBottom:SetVisible(showBottomZone) end

    -- Промежуточные стержни
    local countX = tonumber(values.LongitudinalRebars.AdditionalRebarsCountX) or 0
    local countY = tonumber(values.LongitudinalRebars.AdditionalRebarsCountY) or 0
    local hasAdditional = (countX > 0 or countY > 0)

    local pAddStyle = parameters:GetParameter("LongitudinalRebars", "AdditionalRebarStyleId")
    if pAddStyle then pAddStyle:SetVisible(hasAdditional) end
    local pAddMark = parameters:GetParameter("LongitudinalRebars", "AdditionalRebarMark")
    if pAddMark then pAddMark:SetVisible(hasAdditional) end

    -- Внутренний прямоугольный хомут (только при 2 стержнях по X или Y)
    local hasInternalStirrup = (countX == 2 or countY == 2)
    local pIntStyle = parameters:GetParameter("TransverseRebars", "InternalStirrupStyleId")
    if pIntStyle then pIntStyle:SetVisible(hasInternalStirrup) end
    local pIntMark = parameters:GetParameter("TransverseRebars", "InternalStirrupMark")
    if pIntMark then pIntMark:SetVisible(hasInternalStirrup) end

    -- Выпуски продольной арматуры
    local topOverhang = (values.LongitudinalRebars.TopOverhangEnabled == "yes")
    local pAnchorage = parameters:GetParameter("LongitudinalRebars", "AnchorageFactor")
    if pAnchorage then pAnchorage:SetVisible(topOverhang) end
    local pOverhangDisp = parameters:GetParameter("LongitudinalRebars", "UseOverhangDisplacement")
    if pOverhangDisp then pOverhangDisp:SetVisible(topOverhang) end
    local pDispFactor = parameters:GetParameter("LongitudinalRebars", "DisplacementFactor")
    if pDispFactor then
        pDispFactor:SetVisible(topOverhang and (values.LongitudinalRebars.UseOverhangDisplacement == "yes"))
    end
    local pBend = parameters:GetParameter("LongitudinalRebars", "BendOverhang")
    if pBend then pBend:SetVisible(topOverhang) end
end

-- 2. ОБЩИЕ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ

function getRebarRadius(rebarStyleId)
    if not rebarStyleId or rebarStyleId == 0 then
        return 0
    end
    local style = GetRebarStyle(rebarStyleId)
    if not style then
        return 0
    end
    return GetParameterValue(style, "RebarDiameter") / 2
end

-- 3. ПРОДОЛЬНОЕ АРМИРОВАНИЕ

function createLongitudinalRebars(container, styleParameters, cornerX, cornerY, columnHeight, deltaR)
    local general = styleParameters.General
    local longParams = styleParameters.LongitudinalRebars

    local cornerStyleId = longParams.CornerRebarStyleId
    local addStyleId = longParams.AdditionalRebarStyleId
    if not addStyleId or addStyleId == 0 then
        addStyleId = cornerStyleId
    end

    local cornerR = getRebarRadius(cornerStyleId)
    local addR = getRebarRadius(addStyleId)

    local maxD = math.max(2 * cornerR, 2 * addR)
    local lAnch = maxD * longParams.AnchorageFactor
    local dispFactor = longParams.DisplacementFactor or 1.3
    local lDisp = lAnch * dispFactor

    local bendOverhang = longParams.BendOverhang or "none"
    local useDisplacement = (longParams.UseOverhangDisplacement == "yes")
    local topOverhangEnabled = (longParams.TopOverhangEnabled == "yes")

    local countX = tonumber(longParams.AdditionalRebarsCountX) or 0
    local countY = tonumber(longParams.AdditionalRebarsCountY) or 0

    local rebarPositions = {}

    table.insert(rebarPositions, {x = -cornerX, y = -cornerY, dirX = 1, dirY = 1, styleId = cornerStyleId})
    if countX > 0 then
        local stepX = (2 * cornerX) / (countX + 1)
        for i = 1, countX do
            table.insert(rebarPositions, {x = -cornerX + i * stepX, y = -cornerY - deltaR, dirX = 0, dirY = 1, styleId = addStyleId})
        end
    end
    table.insert(rebarPositions, {x = cornerX, y = -cornerY, dirX = -1, dirY = 1, styleId = cornerStyleId})
    if countY > 0 then
        local stepY = (2 * cornerY) / (countY + 1)
        for i = 1, countY do
            table.insert(rebarPositions, {x = cornerX + deltaR, y = -cornerY + i * stepY, dirX = -1, dirY = 0, styleId = addStyleId})
        end
    end
    table.insert(rebarPositions, {x = cornerX, y = cornerY, dirX = -1, dirY = -1, styleId = cornerStyleId})
    if countX > 0 then
        local stepX = (2 * cornerX) / (countX + 1)
        for i = 1, countX do
            table.insert(rebarPositions, {x = cornerX - i * stepX, y = cornerY + deltaR, dirX = 0, dirY = -1, styleId = addStyleId})
        end
    end
    table.insert(rebarPositions, {x = -cornerX, y = cornerY, dirX = 1, dirY = -1, styleId = cornerStyleId})
    if countY > 0 then
        local stepY = (2 * cornerY) / (countY + 1)
        for i = 1, countY do
            table.insert(rebarPositions, {x = -cornerX - deltaR, y = cornerY - i * stepY, dirX = 1, dirY = 0, styleId = addStyleId})
        end
    end

    local zBottom = general.BottomCover

    for idx, pos in ipairs(rebarPositions) do
        local rStyleId = pos.styleId
        local longR = getRebarRadius(rStyleId)
        local d = 2 * longR

        local isShifted = (idx % 2 == 0)

        local zTop
        if topOverhangEnabled then
            if useDisplacement and isShifted then
                zTop = columnHeight + lAnch + lDisp
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

-- 4. ГЕОМЕТРИЯ ПОПЕРЕЧНОГО АРМИРОВАНИЯ

-- О-образный хомут

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

-- S-образная шпилька

function S_ClampCurve(startPoint2D, endPoint2D, bendLengthD, rebarStyleId, longRebarStyleId)

    local longR = getRebarRadius(longRebarStyleId)
    local r = getRebarRadius(rebarStyleId)

    local dx = endPoint2D:GetX() - startPoint2D:GetX()
    local dy = endPoint2D:GetY() - startPoint2D:GetY()
    local length = math.sqrt(dx ^ 2 + dy ^ 2)

    local rBending = (longR < 2.5 * r) and (3.5 * r) or (longR + r)
    local lBend = bendLengthD * r * 2
    local shiftXCenterLine = 2.5 * r - longR
    local length2 = length - shiftXCenterLine * 2

    local tangentAngle = math.acos(rBending / (length2 * 0.5))
    local shiftX = math.cos(tangentAngle) * rBending
    local shiftY = math.sin(tangentAngle) * rBending
    local shiftBendX = math.sin(tangentAngle) * lBend
    local shiftBendY = math.cos(tangentAngle) * lBend

    local startPoint = Point3D(startPoint2D:GetX(), startPoint2D:GetY(), 0)

    local points = {
        startPoint:Clone():Shift(shiftXCenterLine - shiftX + shiftBendX, shiftY + shiftBendY, 0),
        startPoint:Clone():Shift(shiftXCenterLine - shiftX - shiftY, shiftY - shiftX, 0),
        startPoint:Clone():Shift(shiftXCenterLine + shiftX - shiftY, -shiftY - shiftX, 0),
        startPoint:Clone():Shift(length - shiftXCenterLine - shiftX + shiftY, shiftY + shiftX, 0),
        startPoint:Clone():Shift(length - shiftXCenterLine + shiftX + shiftY, -shiftY + shiftX, 0),
        startPoint:Clone():Shift(length - shiftXCenterLine + shiftX - shiftBendX, -shiftY - shiftBendY, 0)
    }

    local rebarCurve = CreatePolyline3D(points)
    FilletCorners3D(rebarCurve, rBending)

    -- Алгоритм MathLib.DirectionAngle
    local angle

    if dx == 0 then
        angle = dy >= 0 and math.pi / 2 or 3 * math.pi / 2
    else
        local arrayAngle = math.atan(math.abs(dy) / math.abs(dx))

        if dx > 0 then
            angle = dy >= 0 and arrayAngle or 2 * math.pi - arrayAngle
        else
            angle = dy >= 0 and math.pi - arrayAngle or math.pi + arrayAngle
        end
    end

    return rebarCurve:Rotate(Axis3D(startPoint, Vector3D(0, 0, 1)), angle)

end


-- 5. КОМПОНОВКА ЯРУСА

function createStirrupTier(container, styleParameters, cornerX, cornerY, deltaR, z)
    local transParams = styleParameters.TransverseRebars
    local longParams = styleParameters.LongitudinalRebars

    local outerStyleId = transParams.ClosedStirrupStyleId

    local intStyleId = transParams.InternalStirrupStyleId
    if not intStyleId or intStyleId == 0 then
        intStyleId = outerStyleId
    end

    local sStyleId = transParams.SStirrupStyleId
    if not sStyleId or sStyleId == 0 then
        sStyleId = intStyleId
    end

    local cornerLongStyleId = longParams.CornerRebarStyleId

    local addLongStyleId = longParams.AdditionalRebarStyleId
    if not addLongStyleId or addLongStyleId == 0 then
        addLongStyleId = cornerLongStyleId
    end

    local countX = tonumber(longParams.AdditionalRebarsCountX) or 0
    local countY = tonumber(longParams.AdditionalRebarsCountY) or 0

    local bendFactor = transParams.BendLengthFactor
    local bendAngleDeg = tonumber(transParams.BendAngle)

    local rOuter = getRebarRadius(outerStyleId)
    local rInt = getRebarRadius(intStyleId)
    local rS = getRebarRadius(sStyleId)

    -- 1. Наружный О-образный хомут
    local outerAnchor = Point3D(-cornerX, -cornerY, z)

    local outerCurve = createClosedStirrupCurve(
        outerAnchor,
        2 * cornerX,
        2 * cornerY,
        0,
        bendFactor,
        outerStyleId,
        cornerLongStyleId,
        bendAngleDeg
    )

    container:AddRebar(outerStyleId, outerCurve)

    -- Радиусы элементов на уровнях X и Y
    local rX = (countX == 1) and rS or rInt
    local rY = (countY == 1) and rS or rInt

    -- 2. Поперечный элемент X
    local zX = z + 3 * rOuter + rX

    if countX == 2 then
        -- Внутренний О-образный хомут
        local x_c = cornerX / 3
        local y_c = cornerY + deltaR

        local innerCurveX = createClosedStirrupCurve(
            Point3D(x_c, y_c, zX),
            2 * x_c,
            2 * y_c,
            math.pi,
            bendFactor,
            intStyleId,
            addLongStyleId,
            bendAngleDeg
        )

        container:AddRebar(intStyleId, innerCurveX)

    elseif countX == 1 then
        -- S-шпилька между противоположными гранями Y
        local y_c = cornerY + deltaR

        local sCurveX = S_ClampCurve(
            Point2D(0, -y_c),
            Point2D(0, y_c),
            bendFactor,
            sStyleId,
            addLongStyleId
        )

        sCurveX:Shift(0, 0, zX)
        container:AddRebar(sStyleId, sCurveX)
    end

    -- 3. Поперечный элемент Y: учитываем фактическую высоту элемента X
    local zY
    if countX == 2 then
        -- O-образный X занимает два диаметра по Z
        zY = zX + 3 * rInt + rY
    elseif countX == 1 then
        -- S-образный X занимает один диаметр по Z
        zY = zX + rS + rY
    else
        -- X отсутствует: Y прилегает непосредственно к наружному O-образному
        zY = z + 3 * rOuter + rY
    end

    if countY == 2 then
        -- Внутренний О-образный хомут
        local x_c = cornerX + deltaR
        local y_c = cornerY / 3

        local innerCurveY = createClosedStirrupCurve(
            Point3D(x_c, y_c, zY),
            2 * x_c,
            2 * y_c,
            math.pi,
            bendFactor,
            intStyleId,
            addLongStyleId,
            bendAngleDeg
        )

        container:AddRebar(intStyleId, innerCurveY)

    elseif countY == 1 then
        -- S-шпилька между противоположными гранями X
        local x_c = cornerX + deltaR

        local sCurveY = S_ClampCurve(
            Point2D(x_c, 0),
            Point2D(-x_c, 0),
            bendFactor,
            sStyleId,
            addLongStyleId
        )

        sCurveY:Shift(0, 0, zY)
        container:AddRebar(sStyleId, sCurveY)
    end
end

-- 6. РАСКЛАДКА ПОПЕРЕЧНОГО АРМИРОВАНИЯ




-- 7. ОСНОВНАЯ ФУНКЦИЯ RENGA

function CreateObjectReinforcement(object, styleParameters)
    local result = ReinforcementContainer()

    local width = nil
    local depth = nil

    if type(GetSectionProfile) == "function" then
        local ok, profile = pcall(GetSectionProfile, object)
        if ok and profile and profile.Width and profile.Height then
            width = profile.Width
            depth = profile.Height
        end
    end

    if not width or not depth then
        local bbox = GetBoundingBox(object)
        if bbox then
            width = bbox:GetWidth()
            depth = bbox:GetDepth()
        end
    end

    if not width or not depth or width <= 0 or depth <= 0 then
        return result
    end

    local general = styleParameters.General
    local axisDistance = general.AxisDistanceSide
    local cornerX = (width / 2) - axisDistance
    local cornerY = (depth / 2) - axisDistance

    if cornerX <= 0 or cornerY <= 0 then
        return result
    end

    local columnHeight = nil
    local okH, h = pcall(GetParameterValue, object, "ColumnHeight")
    if okH and type(h) == "number" and h > 0 then
        columnHeight = h
    else
        local bbox = GetBoundingBox(object)
        if bbox then
            columnHeight = bbox:GetHeight()
        end
    end

    if not columnHeight or columnHeight <= 0 then
        return result
    end

    -- Разность радиусов углового и дополнительного стержней для смещения к хомуту
    local cornerStyleId = styleParameters.LongitudinalRebars.CornerRebarStyleId
    local addStyleId = styleParameters.LongitudinalRebars.AdditionalRebarStyleId or cornerStyleId
    if not addStyleId or addStyleId == 0 then
        addStyleId = cornerStyleId
    end

    local cornerR = getRebarRadius(cornerStyleId)
    local addR = getRebarRadius(addStyleId)
    local deltaR = cornerR - addR

    -- Построение продольного армирования
    createLongitudinalRebars(result, styleParameters, cornerX, cornerY, columnHeight, deltaR)

        -- Один проверочный ярус поперечного армирования
    local outerStirrupStyleId = styleParameters.TransverseRebars.ClosedStirrupStyleId
    local rOuter = getRebarRadius(outerStirrupStyleId)

    local z = styleParameters.General.BottomCover
        + styleParameters.LongitudinalRebars.FreeEnd
        + rOuter

    createStirrupTier(result, styleParameters, cornerX, cornerY, deltaR, z)

    return result
end