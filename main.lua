require "MathLib"
require "RebarCurveLib"
require "RebarLib"

-- ============================================================
-- Column Tied Reinforcement With Overhangs, Zones, Ties and Internal Stirrups
-- ============================================================
local MIN_REBAR_CLEARANCE = 25

-- 1. УПРАВЛЕНИЕ ПАРАМЕТРАМИ

function SetStyleParameterStates(parameters)
    local values = parameters:GetParameterValues()
    local zones = values.TransverseRebars.ReinforcementZones

    local grpTop = parameters:GetParameterGroup("TopZone")
    if grpTop then grpTop:SetVisible(zones == "top" or zones == "both") end
    local grpBottom = parameters:GetParameterGroup("BottomZone")
    if grpBottom then grpBottom:SetVisible(zones == "bottom" or zones == "both") end

    local countX = tonumber(values.LongitudinalRebars.AdditionalRebarsCountX) or 0
    local countY = tonumber(values.LongitudinalRebars.AdditionalRebarsCountY) or 0
    local hasAdditional = countX > 0 or countY > 0

    local pAddStyle = parameters:GetParameter("LongitudinalRebars", "AdditionalRebarStyleId")
    if pAddStyle then pAddStyle:SetVisible(hasAdditional) end
    local pAddMark = parameters:GetParameter("LongitudinalRebars", "AdditionalRebarMark")
    if pAddMark then pAddMark:SetVisible(hasAdditional) end

    local pXStyle = parameters:GetParameter("TransverseRebars", "AdditionalStirrupStyleIdX")
    if pXStyle then pXStyle:SetVisible(countX > 0) end
    local pXMark = parameters:GetParameter("TransverseRebars", "AdditionalStirrupMarkX")
    if pXMark then pXMark:SetVisible(countX > 0) end

    local pYStyle = parameters:GetParameter("TransverseRebars", "AdditionalStirrupStyleIdY")
    if pYStyle then pYStyle:SetVisible(countY > 0) end
    local pYMark = parameters:GetParameter("TransverseRebars", "AdditionalStirrupMarkY")
    if pYMark then pYMark:SetVisible(countY > 0) end

    local topOverhang = values.LongitudinalRebars.TopOverhangEnabled == "yes"
    local pAnchorage = parameters:GetParameter("LongitudinalRebars", "AnchorageFactor")
    if pAnchorage then pAnchorage:SetVisible(topOverhang) end
    local pStagger = parameters:GetParameter("LongitudinalRebars", "RebarEndStagger")
    if pStagger then pStagger:SetVisible(topOverhang) end
    local pDispFactor = parameters:GetParameter("LongitudinalRebars", "DisplacementFactor")
    if pDispFactor then
        local staggerMode = values.LongitudinalRebars.RebarEndStagger or "none"
        pDispFactor:SetVisible(topOverhang and staggerMode ~= "none")
    end
    local pBend = parameters:GetParameter("LongitudinalRebars", "BendOverhang")
    if pBend then pBend:SetVisible(topOverhang) end

    local cornerHasBoth, additionalHasBoth = getStaggeredRebarMarkUsage(values.LongitudinalRebars)
    local pCornerStaggerMark = parameters:GetParameter("LongitudinalRebars", "CornerRebarStaggeredMark")
    if pCornerStaggerMark then pCornerStaggerMark:SetVisible(cornerHasBoth) end
    local pAddStaggerMark = parameters:GetParameter("LongitudinalRebars", "AdditionalRebarStaggeredMark")
    if pAddStaggerMark then pAddStaggerMark:SetVisible(additionalHasBoth) end
end

-- 2. ОБЩИЕ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ

-- Возвращает, нужны ли отдельные марки для чередуемых стержней.
-- Учитывает форму изделия и наличие обеих групп внутри каждого типа.
function getStaggeredRebarMarkUsage(longParams)
    if longParams.TopOverhangEnabled ~= "yes" then
        return false, false
    end

    local mode = longParams.RebarEndStagger or "none"
    local bend = longParams.BendOverhang or "none"

    -- При разбежке с обоих концов без верхнего отгиба
    -- изделия одинаковы по форме и длине (различается только отметка).
    if mode == "none" or (mode == "both" and bend ~= "top") then
        return false, false
    end

    local countX = tonumber(longParams.AdditionalRebarsCountX) or 0
    local countY = tonumber(longParams.AdditionalRebarsCountY) or 0

    -- Индексы четырёх угловых стержней при существующем обходе периметра.
    local cornerIndices = {1, 2 + countX, 3 + countX + countY, 4 + 2 * countX + countY}
    local shiftedCorners = 0
    for _, index in ipairs(cornerIndices) do
        if index % 2 == 0 then
            shiftedCorners = shiftedCorners + 1
        end
    end

    -- Каждая вторая позиция смещается. Всего позиций всегда чётное число.
    local totalShifted = (4 + 2 * (countX + countY)) / 2
    local shiftedAdditional = totalShifted - shiftedCorners
    local totalAdditional = 2 * (countX + countY)

    local cornerHasBoth = shiftedCorners > 0 and shiftedCorners < 4
    local additionalHasBoth = shiftedAdditional > 0 and shiftedAdditional < totalAdditional
    return cornerHasBoth, additionalHasBoth
end

-- 3. ПРОДОЛЬНОЕ АРМИРОВАНИЕ

function createLongitudinalRebars(container, styleParameters, cornerX, cornerY, columnHeight, deltaR)
    local general = styleParameters.General
    local longParams = styleParameters.LongitudinalRebars

    local cornerStyleId = longParams.CornerRebarStyleId
    local cornerMark = longParams.CornerRebarMark
    local addMark = longParams.AdditionalRebarMark
    local cornerHasBoth, additionalHasBoth = getStaggeredRebarMarkUsage(longParams)
    local cornerStaggerMark = cornerHasBoth and (longParams.CornerRebarStaggeredMark or cornerMark) or cornerMark
    local addStaggerMark = additionalHasBoth and (longParams.AdditionalRebarStaggeredMark or addMark) or addMark
    local addStyleId = longParams.AdditionalRebarStyleId
    if not addStyleId or addStyleId == 0 then
        addStyleId = cornerStyleId
    end

    local cornerR = MathLib.GetRebarRadius(cornerStyleId)
    local addR = MathLib.GetRebarRadius(addStyleId)

    local maxD = math.max(2 * cornerR, 2 * addR)
    local lAnch = maxD * longParams.AnchorageFactor
    local dispFactor = longParams.DisplacementFactor or 1.3
    local lDisp = lAnch * dispFactor

    local bendOverhang = longParams.BendOverhang or "none"
    local topOverhangEnabled = (longParams.TopOverhangEnabled == "yes")
    local staggerMode = topOverhangEnabled and (longParams.RebarEndStagger or "none") or "none"
    local staggerTop = (staggerMode == "top" or staggerMode == "both")
    local staggerBottom = (staggerMode == "bottom" or staggerMode == "both")

    local countX = tonumber(longParams.AdditionalRebarsCountX) or 0
    local countY = tonumber(longParams.AdditionalRebarsCountY) or 0

    local rebarPositions = {}

    table.insert(rebarPositions, {x = -cornerX, y = -cornerY, dirX = 1, dirY = 1, styleId = cornerStyleId, mark = cornerMark, staggeredMark = cornerStaggerMark})
    if countX > 0 then
        local stepX = (2 * cornerX) / (countX + 1)
        for i = 1, countX do
            table.insert(rebarPositions, {x = -cornerX + i * stepX, y = -cornerY - deltaR, dirX = 0, dirY = 1, styleId = addStyleId, mark = addMark, staggeredMark = addStaggerMark})
        end
    end
    table.insert(rebarPositions, {x = cornerX, y = -cornerY, dirX = -1, dirY = 1, styleId = cornerStyleId, mark = cornerMark, staggeredMark = cornerStaggerMark})
    if countY > 0 then
        local stepY = (2 * cornerY) / (countY + 1)
        for i = 1, countY do
            table.insert(rebarPositions, {x = cornerX + deltaR, y = -cornerY + i * stepY, dirX = -1, dirY = 0, styleId = addStyleId, mark = addMark, staggeredMark = addStaggerMark})
        end
    end
    table.insert(rebarPositions, {x = cornerX, y = cornerY, dirX = -1, dirY = -1, styleId = cornerStyleId, mark = cornerMark, staggeredMark = cornerStaggerMark})
    if countX > 0 then
        local stepX = (2 * cornerX) / (countX + 1)
        for i = 1, countX do
            table.insert(rebarPositions, {x = cornerX - i * stepX, y = cornerY + deltaR, dirX = 0, dirY = -1, styleId = addStyleId, mark = addMark, staggeredMark = addStaggerMark})
        end
    end
    table.insert(rebarPositions, {x = -cornerX, y = cornerY, dirX = 1, dirY = -1, styleId = cornerStyleId, mark = cornerMark, staggeredMark = cornerStaggerMark})
    if countY > 0 then
        local stepY = (2 * cornerY) / (countY + 1)
        for i = 1, countY do
            table.insert(rebarPositions, {x = -cornerX - deltaR, y = cornerY - i * stepY, dirX = 1, dirY = 0, styleId = addStyleId, mark = addMark, staggeredMark = addStaggerMark})
        end
    end

    for idx, pos in ipairs(rebarPositions) do
        local rStyleId = pos.styleId
        local longR = MathLib.GetRebarRadius(rStyleId)
        local d = 2 * longR

        local isShifted = (idx % 2 == 0)

        local zBottom = general.BottomCover
        if isShifted and staggerBottom then
            zBottom = zBottom + lDisp
        end

        local zTop
        if topOverhangEnabled then
            zTop = columnHeight + lAnch
            if isShifted and staggerTop then
                zTop = zTop + lDisp
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

            local mark = isShifted and pos.staggeredMark or pos.mark
            RebarLib.AddRebar(container, rStyleId, curve, ReinforcementRole.Structural, mark)
        end
    end
end

-- 4. ГЕОМЕТРИЯ ПОПЕРЕЧНОГО АРМИРОВАНИЯ

-- Геометрия поперечных элементов создаётся в RebarCurveLib.

-- 5. КОМПОНОВКА ЯРУСА

function createStirrupTier(container, styleParameters, cornerX, cornerY, deltaR, z, step, count)
    local transParams = styleParameters.TransverseRebars
    local longParams = styleParameters.LongitudinalRebars

    local outerStyleId = transParams.ClosedStirrupStyleId
    local outerMark = transParams.ClosedStirrupMark
    local xMark = transParams.AdditionalStirrupMarkX
    local yMark = transParams.AdditionalStirrupMarkY

    -- По X и Y используется отдельный стиль независимо от формы элемента:
    -- 1 промежуточный стержень = S-шпилька; 2 = O-образный хомут.
    local xStyleId = transParams.AdditionalStirrupStyleIdX
    if not xStyleId or xStyleId == 0 then
        xStyleId = outerStyleId
    end
    local yStyleId = transParams.AdditionalStirrupStyleIdY
    if not yStyleId or yStyleId == 0 then
        yStyleId = outerStyleId
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

    local rOuter = MathLib.GetRebarRadius(outerStyleId)
    local rX = MathLib.GetRebarRadius(xStyleId)
    local rY = MathLib.GetRebarRadius(yStyleId)

    -- 1. Наружный О-образный хомут
    local outerAnchor = Point3D(-cornerX, -cornerY, z)

    local outerCurve = RebarCurveLib.O_ClampCurveWithHookAngle(
        outerAnchor,
        2 * cornerX,
        2 * cornerY,
        0,
        bendFactor,
        outerStyleId,
        cornerLongStyleId,
        bendAngleDeg
    )

    RebarLib.AddRebarOrSet(container, outerStyleId, outerCurve,
            Vector3D(0, 0, 1), step, count, ReinforcementRole.Auxiliary, outerMark)

    -- 2. Поперечный элемент X
    local zX = z + 3 * rOuter + rX

    if countX == 2 then
        -- Внутренний О-образный хомут
        local x_c = cornerX / 3
        local y_c = cornerY + deltaR

        local innerCurveX = RebarCurveLib.O_ClampCurveWithHookAngle(
            Point3D(x_c, y_c, zX),
            2 * x_c,
            2 * y_c,
            math.pi,
            bendFactor,
            xStyleId,
            addLongStyleId,
            bendAngleDeg
        )

        RebarLib.AddRebarOrSet(container, xStyleId, innerCurveX,
            Vector3D(0, 0, 1), step, count, ReinforcementRole.Auxiliary, xMark)

    elseif countX == 1 then
        -- S-шпилька между противоположными гранями Y
        local y_c = cornerY + deltaR

        local sCurveX = RebarCurveLib.S_ClampCurve(
            Point2D(0, -y_c),
            Point2D(0, y_c),
            bendFactor,
            xStyleId,
            addLongStyleId
        )

        sCurveX:Shift(0, 0, zX)
        RebarLib.AddRebarOrSet(container, xStyleId, sCurveX,
            Vector3D(0, 0, 1), step, count, ReinforcementRole.Auxiliary, xMark)
    end

    -- 3. Поперечный элемент Y: учитываем фактическую высоту элемента X
    local zY
    if countX == 2 then
        -- O-образный X занимает два диаметра по Z
        zY = zX + 3 * rX + rY
    elseif countX == 1 then
        -- S-образный X занимает один диаметр по Z
        zY = zX + rX + rY
    else
        -- X отсутствует: Y прилегает непосредственно к наружному O-образному
        zY = z + 3 * rOuter + rY
    end

    if countY == 2 then
        -- Внутренний О-образный хомут
        local x_c = cornerX + deltaR
        local y_c = cornerY / 3

        local innerCurveY = RebarCurveLib.O_ClampCurveWithHookAngle(
            Point3D(x_c, y_c, zY),
            2 * x_c,
            2 * y_c,
            math.pi,
            bendFactor,
            yStyleId,
            addLongStyleId,
            bendAngleDeg
        )

        RebarLib.AddRebarOrSet(container, yStyleId, innerCurveY,
            Vector3D(0, 0, 1), step, count, ReinforcementRole.Auxiliary, yMark)

    elseif countY == 1 then
        -- S-шпилька между противоположными гранями X
        local x_c = cornerX + deltaR

        local sCurveY = RebarCurveLib.S_ClampCurve(
            Point2D(x_c, 0),
            Point2D(-x_c, 0),
            bendFactor,
            yStyleId,
            addLongStyleId
        )

        sCurveY:Shift(0, 0, zY)
        RebarLib.AddRebarOrSet(container, yStyleId, sCurveY,
            Vector3D(0, 0, 1), step, count, ReinforcementRole.Auxiliary, yMark)
    end
end

-- 6. РАСКЛАДКА ПОПЕРЕЧНОГО АРМИРОВАНИЯ

-- Высота яруса от оси наружного хомута до верхней грани
-- последнего существующего поперечного элемента.
function getStirrupTierHeight(styleParameters)
    local transParams = styleParameters.TransverseRebars
    local longParams = styleParameters.LongitudinalRebars

    local outerStyleId = transParams.ClosedStirrupStyleId
    local xStyleId = transParams.AdditionalStirrupStyleIdX
    if not xStyleId or xStyleId == 0 then
        xStyleId = outerStyleId
    end
    local yStyleId = transParams.AdditionalStirrupStyleIdY
    if not yStyleId or yStyleId == 0 then
        yStyleId = outerStyleId
    end

    local rOuter = MathLib.GetRebarRadius(outerStyleId)
    local rX = MathLib.GetRebarRadius(xStyleId)
    local rY = MathLib.GetRebarRadius(yStyleId)
    local countX = tonumber(longParams.AdditionalRebarsCountX) or 0
    local countY = tonumber(longParams.AdditionalRebarsCountY) or 0

    -- Наружный O-образный хомут: от базовой оси до верхней поверхности.
    local tierHeight = 2 * rOuter

    local zX = 3 * rOuter + rX

    if countX == 2 then
        tierHeight = zX + 2 * rX
    elseif countX == 1 then
        tierHeight = zX + rX
    end

    if countY > 0 then
        local zY
        if countX == 2 then
            zY = zX + 3 * rX + rY
        elseif countX == 1 then
            zY = zX + rX + rY
        else
            zY = 3 * rOuter + rY
        end

        if countY == 2 then
            tierHeight = zY + 2 * rY
        else
            tierHeight = zY + rY
        end
    end

    return tierHeight
end

-- Формирует список базовых отметок в пределах одного участка.
-- Каждый участок начинает раскладку строго от своей нижней границы.
-- При недостаточном зазоре приоритет имеет граничный ярус новой зоны.
-- minAxisDistance = stepMinClearance + tierHeight + rOuter.

-- Выбор зон, расчёт отметок и построение готовых ярусов.
function createTransverseStirrups(container, styleParameters, cornerX, cornerY, columnHeight, deltaR)
    local general = styleParameters.General
    local longParams = styleParameters.LongitudinalRebars
    local transParams = styleParameters.TransverseRebars

    local rOuter = MathLib.GetRebarRadius(transParams.ClosedStirrupStyleId)
    local tierHeight = getStirrupTierHeight(styleParameters)
    local stepMinClearance = MIN_REBAR_CLEARANCE
    local minAxisDistance = stepMinClearance + tierHeight + rOuter

    local zBottom = general.BottomCover + longParams.FreeEnd + rOuter
    local topOffset = longParams.FreeEnd
    if longParams.TopOverhangEnabled == "no" then
        topOffset = topOffset + general.TopCover
    end
    local zTop = columnHeight - topOffset - tierHeight
    if zTop < zBottom then
        return
    end

    local zones = transParams.ReinforcementZones
    local bottomSize = 0
    local topSize = 0
    if zones == "bottom" or zones == "both" then
        bottomSize = styleParameters.BottomZone.ZoneSize
    end
    if zones == "top" or zones == "both" then
        topSize = styleParameters.TopZone.ZoneSize
    end
    if bottomSize + topSize >= columnHeight then
        zones = "none"
    end

    local positions = {}
    local mainStep = transParams.MiddleZoneFirstStep
    local borderBottom = math.max(zBottom, math.min(zTop, bottomSize))
    local borderTop = math.max(zBottom, math.min(zTop, columnHeight - topSize))

    if zones == "none" then
        RebarLib.AppendTierPositions(positions, zBottom, zTop, mainStep, true, minAxisDistance)
    elseif zones == "top" then
        RebarLib.AppendTierPositions(positions, zBottom, borderTop, mainStep, false, minAxisDistance)
        RebarLib.AppendTierPositions(positions, borderTop, zTop, styleParameters.TopZone.Step, true, minAxisDistance)
    elseif zones == "bottom" then
        RebarLib.AppendTierPositions(positions, zBottom, borderBottom, styleParameters.BottomZone.Step, false, minAxisDistance)
        RebarLib.AppendTierPositions(positions, borderBottom, zTop, mainStep, true, minAxisDistance)
    elseif zones == "both" then
        RebarLib.AppendTierPositions(positions, zBottom, borderBottom, styleParameters.BottomZone.Step, false, minAxisDistance)
        RebarLib.AppendTierPositions(positions, borderBottom, borderTop, mainStep, false, minAxisDistance)
        RebarLib.AppendTierPositions(positions, borderTop, zTop, styleParameters.TopZone.Step, true, minAxisDistance)
    end

    -- Последняя отметка — доборный ярус; не включаем его в регулярные наборы.
    local regularEnd = #positions - 1
    local i = 1
    local epsilon = 0.000001

    while i <= regularEnd do
        local count = 1
        local step = nil

        if i < regularEnd then
            step = positions[i + 1] - positions[i]
            count = 2

            -- Объединяем только последовательные ярусы с одинаковым шагом.
            while i + count <= regularEnd and
                math.abs((positions[i + count] - positions[i + count - 1]) - step) < epsilon do
                count = count + 1
            end
        end

        createStirrupTier(container, styleParameters, cornerX, cornerY, deltaR,
            positions[i], step, count)
        i = i + count
    end

    if #positions > 0 then
        createStirrupTier(container, styleParameters, cornerX, cornerY, deltaR,
            positions[#positions])
    end
end


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

    local cornerR = MathLib.GetRebarRadius(cornerStyleId)
    local addR = MathLib.GetRebarRadius(addStyleId)
    local deltaR = cornerR - addR

    -- Построение продольного армирования
    createLongitudinalRebars(result, styleParameters, cornerX, cornerY, columnHeight, deltaR)

    -- Раскладка поперечного армирования по зонам
    createTransverseStirrups(result, styleParameters, cornerX, cornerY, columnHeight, deltaR)

    return result
end