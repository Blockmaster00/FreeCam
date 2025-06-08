tm.physics.AddTexture("textures/cable.png", "cable_texture")

local playerList = tm.players.CurrentPlayers()

local mesh_save_path = "cableTool/catenary_meshes/"
local settings_save_path = "cableTool/settings.json"


local success, settings = pcall(function() return json.parse(tm.os.ReadAllText_Dynamic(settings_save_path)) end)
if not success then
    settings = {}
    tm.os.Log("settings.json not found -> Creating new file")
end

for i, player in ipairs(playerList) do
    local playerName = tm.players.GetPlayerName(player.playerId)
    if settings[playerName] == nil then
        tm.os.Log("Creating settings for player: " .. playerName)
        settings[playerName] = {
            a = 1,
            thickness = 0.2,
            uv_scale = 1,
            resolution = 100,
            previewObjects = {},
        }
    end
end



-- Helper: Solve for c using bisection.
-- f(c) = a*(cosh((x2-c)/a) - cosh((x1-c)/a)) - (y2 - y1)
local function solve_for_c(x1, x2, y1, y2, a)
    local f = function(c)
        return a *
            ((math.exp((x2 - c) / a) + math.exp(-(x2 - c) / a)) / 2 - (math.exp((x1 - c) / a) + math.exp(-(x1 - c) / a)) / 2) -
            (y2 - y1)
    end

    -- Use bounds around the symmetric guess.
    local lower = (x1 + x2) / 2 - a * 10
    local upper = (x1 + x2) / 2 + a * 10
    local mid
    for i = 1, 100 do
        mid = (lower + upper) / 2
        local fmid = f(mid)
        if math.abs(fmid) < 1e-6 then
            tm.os.Log("solved for c: " .. mid)
            return mid
        end
        if f(lower) * fmid < 0 then
            upper = mid
        else
            lower = mid
        end
    end
    tm.os.Log("solved for c: " .. mid)
    return mid -- or return nil if not found properly
end

--------------------------------------------------------------------------------
-- Function: generate_catenary_vertical
--
-- Description:
--   Generates a 3D catenary curve such that the sag is vertical (i.e. the
--   cable hangs under gravity).
--
-- Parameters:
--   P1  : tm.vector3 -- starting endpoint.
--   P2  : tm.vector3 -- ending endpoint.
--   a   : number     -- initial sag parameter.
--
-- Returns:
--   Array of tm.vector3 representing the 3D catenary points.
--------------------------------------------------------------------------------
local function generate_catenary_vertical(P1, P2, a, resolution)
    tm.os.Log("####-- Generating Catenary --####")
    local pivot = P1
    if P2.y < P1.y then
        pivot = P2
    end
    -- Compute the horizontal vector between P1 and P2 (ignoring Y).
    local horizontalVec = tm.vector3.Create(P2.x - P1.x, 0, P2.z - P1.z)
    local horizontalDistance = horizontalVec:Magnitude()
    if horizontalDistance < 1e-6 then
        horizontalVec = tm.vector3.Create(1, 0, 0)
        horizontalDistance = 1e-6
    else
        horizontalVec = horizontalVec / horizontalDistance
    end
    a = a * horizontalDistance -- Scale sag parameter by horizontal distance.

    local up = tm.vector3.Up() -- (0,1,0)

    -- Define 2D coordinates: x along horizontal, y from the actual altitude
    local x1, y1 = 0, P1.y
    local x2, y2 = horizontalDistance, P2.y

    -- Solve for horizontal offset c so that boundary conditions are met.
    local c_val = solve_for_c(x1, x2, y1, y2, a)
    if not c_val then
        tm.os.Log("Failed to solve for c; using symmetric assumption")
        c_val = (x1 + x2) / 2
    end

    -- Compute vertical offset d from first endpoint.
    local d = y1 - a * ((math.exp((x1 - c_val) / a) + math.exp(-(x1 - c_val) / a)) / 2)

    -- Generate 2D catenary points using the non-symmetric equation.
    local numPoints = resolution or 100 -- Default resolution if not provided.
    local x_vals, y_vals = {}, {}
    for i = 0, numPoints do
        local t = i / numPoints
        local x_val = x1 * (1 - t) + x2 * t
        local y_val = a * ((math.exp((x_val - c_val) / a) + math.exp(-(x_val - c_val) / a)) / 2) + d
        table.insert(x_vals, x_val)
        table.insert(y_vals, y_val)
    end

    -- Map the 2D curve back to 3D:
    -- x coordinate moves along horizontalVec and y coordinate is the computed vertical.
    local catenary3D = {}
    for i = 1, #x_vals do
        local horizontalDisp = horizontalVec * x_vals[i]
        local verticalDisp = up * (y_vals[i] - P1.y)
        catenary3D[i] = P1 + horizontalDisp + verticalDisp - pivot
    end

    return catenary3D
end

--------------------------------------------------------------------------------
-- Function: generate_catenary_obj
--
-- (this function thickens the centerline to a ribbon mesh
-- and then exports an OBJ string.)
--------------------------------------------------------------------------------
local function generate_catenary_obj(catenary3D, thickness, uv_scale)
    tm.os.Log("####-- Generating OBJ --####")
    local vertices   = {} -- "v x y z" lines
    local normals    = {} -- "vn x y z" lines
    local uvs        = {} -- "vt u v" lines
    local faces      = {} -- "f ..." lines

    local numSamples = #catenary3D

    for i, point in ipairs(catenary3D) do
        if math.abs(point.x) > 1e6 or math.abs(point.y) > 1e6 or math.abs(point.z) > 1e6 then
            tm.os.Log("Invalid catenary point detected; check sag parameter 'a'.")
            return {}
        end
    end

    for i = 1, numSamples do
        local tangent
        if i == 1 then
            tangent = catenary3D[2] - catenary3D[1]
        elseif i == numSamples then
            tangent = catenary3D[numSamples] - catenary3D[numSamples - 1]
        else
            tangent = catenary3D[i + 1] - catenary3D[i - 1]
        end
        local tMag = tangent.Magnitude()
        if tMag ~= 0 then
            tangent = tangent / tMag
        end

        local up = tm.vector3.Create(0, 1, 0)
        local side = tangent:Cross(up)
        if side:Magnitude() < 1e-6 then
            up = tm.vector3.Create(0, 0, 1)
            side = tangent:Cross(up)
        end
        local sideMag = side:Magnitude()
        if sideMag ~= 0 then
            side = side / sideMag
        end

        -- Rotate the computed side vector 90 degrees around the tangent:
        local rotatedSide = tangent:Cross(side)
        local rSideMag = rotatedSide:Magnitude()
        if rSideMag ~= 0 then
            rotatedSide = rotatedSide / rSideMag
        end

        -- Use the rotated side for the offset.
        local offset      = rotatedSide * (thickness / 2)
        local leftVertex  = catenary3D[i] + offset
        local rightVertex = catenary3D[i] - offset

        table.insert(vertices, string.format("v %f %f %f", leftVertex.x, leftVertex.y, leftVertex.z))
        table.insert(vertices, string.format("v %f %f %f", rightVertex.x, rightVertex.y, rightVertex.z))

        local normal = side:Cross(tangent)
        local nMag = normal:Magnitude()
        if nMag ~= 0 then
            normal = normal / nMag
        end
        table.insert(normals, string.format("vn %f %f %f", normal.x, normal.y, normal.z))
        table.insert(normals, string.format("vn %f %f %f", normal.x, normal.y, normal.z))

        local u = ((i - 1) / (numSamples - 1)) * uv_scale
        table.insert(uvs, string.format("vt %f %f", u, 1))
        table.insert(uvs, string.format("vt %f %f", u, 0))
    end

    for i = 1, numSamples - 1 do
        local i1 = (2 * i) - 1
        local i2 = (2 * i)
        local i3 = (2 * i) + 1
        local i4 = (2 * i) + 2

        table.insert(faces, string.format("f %d/%d/%d %d/%d/%d %d/%d/%d",
            i1, i1, i1,
            i3, i3, i3,
            i4, i4, i4))
        table.insert(faces, string.format("f %d/%d/%d %d/%d/%d %d/%d/%d",
            i1, i1, i1,
            i4, i4, i4,
            i2, i2, i2))

        -- Duplicate faces with reversed winding order for the backside:
        table.insert(faces, string.format("f %d/%d/%d %d/%d/%d %d/%d/%d",
            i4, i4, i4,
            i3, i3, i3,
            i1, i1, i1))
        table.insert(faces, string.format("f %d/%d/%d %d/%d/%d %d/%d/%d",
            i2, i2, i2,
            i4, i4, i4,
            i1, i1, i1))
    end

    local obj = table.concat(vertices, "\n") .. "\n" ..
        table.concat(uvs, "\n") .. "\n" ..
        table.concat(normals, "\n") .. "\n" ..
        table.concat(faces, "\n")
    return obj
end

--------------------------------------------------------------------------------

local M = {}

function M.DeletePreview(playerId)
    local playerName = tm.players.GetPlayerName(playerId)
    tm.os.Log("Deleting preview for player: " .. playerName)
    if settings[playerName].previewObjects then
        for _, obj in ipairs(settings[playerName].previewObjects) do
            obj.Despawn()
        end
        settings[playerName].previewObjects = {}
        tm.os.WriteAllText_Dynamic(settings_save_path, json.serialize(settings))
        tm.os.Log("Preview objects cleared for player: " .. playerName)
    end
end

function M.DrawPreview(playerId, pos1, pos2)
    local playerName = tm.players.GetPlayerName(playerId)

    local a = settings[playerName].a
    local thickness = settings[playerName].thickness
    local resolution = settings[playerName].resolution

    local pivot = pos1
    if pos2.y < pos1.y then
        pivot = pos2
    end


    local catenary_3d = generate_catenary_vertical(pos1, pos2, a, resolution)
    M.DeletePreview(playerId) -- Clear previous preview objects
    for i, point in ipairs(catenary_3d) do
        tm.os.Log("Preview point " .. i .. ": " .. point.toString())
        settings[playerName].previewObjects[i] = tm.physics.SpawnObject(point + pivot, "PFB_MovePuzzleBall")
        settings[playerName].previewObjects[i].GetTransform().SetScale(tm.vector3.Create(1, 1, 1) * thickness)
        settings[playerName].previewObjects[i].SetIsStatic(true)
    end
    tm.os.WriteAllText_Dynamic(settings_save_path, json.serialize(settings))
    tm.os.Log("Preview drawn for player: " .. playerName)
end

--[[ local function updateResolution(callbackData)
     local playerId = callbackData.playerId
     local newValue = tonumber(callbackData.value)
     if newValue and newValue > 0 then
          playerData[playerId].uv_scale = newValue
          tm.playerUI.SetUIValue(playerId, "txtResolution", newValue)
          if playerData[playerId].showPreview then
               drawPreview(playerId)
          end
     else
          tm.playerUI.AddSubtleMessageForPlayer(playerId, "Cable Tool", "Invalid resolution value.", 5)
     end
end ]]

--[[ local function updatePos1(callbackData)
     playerData[callbackData.playerId].pos1 = tm.players.GetPlayerTransform(callbackData.playerId).GetPosition()
     playerData[callbackData.playerId].objectPos1.GetTransform().SetPosition(playerData[callbackData.playerId].pos1)
     if playerData[callbackData.playerId].showPreview then
          drawPreview(callbackData.playerId)
     end
end

local function updatePos2(callbackData)
     playerData[callbackData.playerId].pos2 = tm.players.GetPlayerTransform(callbackData.playerId).GetPosition()
     playerData[callbackData.playerId].objectPos2.GetTransform().SetPosition(playerData[callbackData.playerId].pos2)
     if playerData[callbackData.playerId].showPreview then
          drawPreview(callbackData.playerId)
     end
end

local function updateA(callbackData)
     if tonumber(callbackData.value) ~= nil then
          if tonumber(callbackData.value) < 1e-2 then
               playerData[callbackData.playerId].a = 1e-2 -- Minimum sag to prevent steepness.
               tm.playerUI.AddSubtleMessageForPlayer(callbackData.playerId, "Cable Tool", "A has been clamped at: 0.01",
                    5)
          elseif tonumber(callbackData.value) > 1e3 then
               playerData[callbackData.playerId].a = 1e3 -- Maximum sag to avoid flatness.
               tm.playerUI.AddSubtleMessageForPlayer(callbackData.playerId, "Cable Tool", "A has been clamped at: 1000",
                    5)
          else
               playerData[callbackData.playerId].a = tonumber(callbackData.value)
          end
          if playerData[callbackData.playerId].showPreview then
               drawPreview(callbackData.playerId)
          end
     end
end ]]
--[[
local function updateThickness(callbackData)
     if tonumber(callbackData.value) ~= nil then
          if tonumber(callbackData.value) < 1e-2 then
               playerData[callbackData.playerId].thickness = 1e-2 -- Minimum thickness.
               tm.playerUI.AddSubtleMessageForPlayer(callbackData.playerId, "Cable Tool",
                    "width has been clamped at: 0.01",
                    5)
          elseif tonumber(callbackData.value) > 1e3 then
               playerData[callbackData.playerId].thickness = 1e3 -- Maximum thickness to avoid flatness.
               tm.playerUI.AddSubtleMessageForPlayer(callbackData.playerId, "Cable Tool",
                    "width has been clamped at: 1000",
                    5)
          else
               playerData[callbackData.playerId].thickness = tonumber(callbackData.value)
          end
          if playerData[callbackData.playerId].showPreview then
               drawPreview(callbackData.playerId)
          end
     end
end ]]



--[[ function save_obj(playerId)
    local pos1 = playerData[playerId].pos1
    local pos2 = playerData[playerId].pos2
    local a = playerData[playerId].a
    local thickness = playerData[playerId].thickness
    local uv_scale = playerData[playerId].uv_scale

    local catenary_3d = generate_catenary_vertical(pos1, pos2, a)

    local obj_data = generate_catenary_obj(catenary_3d, thickness, uv_scale)
    tm.os.Log(obj_data)
    tm.os.WriteAllText_Dynamic("catenary" .. #objects .. ".obj", obj_data)
    tm.physics.AddMesh("data_dynamic_willNotBeUploadedToWorkshop/catenary" .. #objects .. ".obj",
        "catenary" .. #objects)
    table.insert(objects, "catenary" .. #objects)
    local spawnPos = pos1
    if pos2.y < pos1.y then
        spawnPos = pos2
    end
    tm.physics.SpawnCustomObjectConcave(spawnPos, "catenary" .. #objects - 1, "cable_texture")
end ]]


return M