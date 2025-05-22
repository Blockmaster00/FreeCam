local playerDataTable = {}

tm.physics.AddTexture("blueprints/cameraTracker.png", "rotationStructure")

--#region IDEAS / TODO
--[[
    - replace 'InitRotationStructure' with 'spawnRotationStructure'

    - add a function to spawn the cursor Game object

    -
    ]]

function onPlayerJoined(player)
    local playerId = player.playerId
    local playerData = {
        freeCam = false,
        lastPosition = nil,

        camera = {
            position = nil,
            rotation = nil,
            speed = 1,
        },

        rotationStructure = {
            structure = nil,
            structureId = nil,
            cursorBlock = nil
        },

        cursor = nil,

        input = {
            forward = false,  --w
            backward = false, --s
            left = false,     --a
            right = false,    --d
            up = false,       --space
            down = false,     --shift
        }
    }

    -- Store the player data in a global table
    playerDataTable[playerId] = playerData

    -- Initialize player input
    Init_playerInput(playerId)
end

tm.players.OnPlayerJoined.add(onPlayerJoined)

--[[
function update()
    local players = tm.players.CurrentPlayers()

    for _, player in ipairs(players) do
        PlayerUpdate(player)
    end
end
]]

function PlayerUpdate(player)
    local playerId = player.playerId
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        if not tm.players.IsPlayerInSeat(playerId) then
            tm.playerUI.AddSubtleMessageForPlayer(playerId, "BirdsCam", "Deactivate BirdsCam first!", 3)
            tm.players.PlacePlayerInSeat(playerId, playerData.rotationStructure.structureId)
        end

        local playerSeat = tm.players.GetPlayerSeatBlock(playerId)

        local smoothedRotation = tm.quaternion.Slerp(
            playerData.cameraDirection,
            tm.quaternion.Create(playerSeat:Forward()),
            0.004
        )
        tm.os.Log("Smoothed Rotation: " .. PPointing(playerData.cameraDirection.GetEuler()).ToString())
        tm.players.SetCameraRotation(playerId, PPointing(playerData.cameraDirection.GetEuler()))

        playerData.cameraDirection = smoothedRotation

        -- Update camera position and direction based on player rotationStructure
        --CURSOR POSITIONING

        local cursorBlock = playerData.rotationStructure.cursorBlock
        local cursorRotation = cursorBlock.forward() + PPointing(playerData.cameraDirection.GetEuler())
        cursorRotation = Normalize(cursorRotation)
        local cursorRaycast = tm.physics.RaycastData(
            playerData.cameraPosition,
            cursorRotation,
            10000,
            true
        )
        if cursorRaycast.DidHit() then
            local hitPosition = cursorRaycast.GetHitPosition()
            local hitNormal = cursorRaycast.GetHitNormal()
            local hitDistance = cursorRaycast.GetHitDistance()

            local newCursorPosition = hitPosition + hitNormal * 2 -- Offset the cursor slightly above the surface

            playerData.cursor.GetTransform().SetPosition(newCursorPosition)
            playerData.cursor.GetTransform().SetScale(tm.vector3.Create(0.005, 0.005, 0.005) * hitDistance)
        end
    end
end

function Init_Cursor(playerId)
end

function Spawn_RotationStructure(playerId)
    tm.os.Log("Spawn_RotationStructure called for playerId: " .. playerId)
    local playerData = playerDataTable[playerId]
    local structureId = "rStructure_" .. playerId ..

    -- Create a new structure for the player
    tm.players.SpawnStructure(
        playerId,
        "rotationStructure",
        structureId,
        tm.vector3.Create(0, 0, 0),
        tm.vector3.Create(1, 0, 0)
    )

    -- locate and save the cursor block
    local cursorBlock
    local blockList = tm.players.GetSpawnedStructureById(structureId)[1].GetBlocks()
    for i, block in ipairs(blockList) do
        if block.GetName() == "PFB_MixelEye_Sphere [Server]" then
            cursorBlock = block
            break
        end
    end

    -- Store the structure in the player data
    playerData.rotationStructure = {
        structure = tm.players.GetSpawnedStructureById(structureId)[1],
        structureId = structureId,
        cursorBlock = cursorBlock
    }
end

--#region MATH FUNCTIONS

function PPointing(Rotation)
    local RotXRad = math.rad(Rotation.x)
    local RotYRad = math.rad(Rotation.y)
    local VectorX = math.sin(RotYRad) * math.cos(RotXRad)
    local VectorY = math.sin(RotXRad) * -1
    local VectorZ = math.cos(RotYRad) * math.cos(RotXRad)
    local VectorTot = tm.vector3.Create(VectorX, VectorY, VectorZ)
    return VectorTot
end

function TargetRot(PosHun, PosTar)
    local relativeX = PosTar.x - PosHun.x
    local relativeY = -PosTar.y + PosHun.y
    local relativeZ = PosTar.z - PosHun.z
    local angleradY = math.atan(relativeX, relativeZ)
    local relativeangY = math.deg(angleradY)
    local relativehori = math.sqrt(relativeX * relativeX + relativeZ * relativeZ)
    local angleradX = math.atan(relativeY, relativehori)
    local relativeangX = math.deg(angleradX)
    local relativetot = tm.vector3.Create(relativeangX, relativeangY, 0)
    return relativetot
end

function Normalize(v)
    local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if length == 0 then
        return tm.vector3.Create(0, 0, 0)
    else
        return tm.vector3.Create(v.x / length, v.y / length, v.z / length)
    end
end

--#endregion


--#region PLAYER INPUT

function Init_playerInput(playerId)
    local playerData = playerDataTable[playerId]

    tm.playerUI.AddSubtleMessageForPlayer(playerId, "FreeCam", "Press <sprite index=155> to toggle Free Camera!", 10)

    tm.input.RegisterFunctionToKeyDownCallback(playerId,
        "ToggleFreeCam", "v")
    tm.input.RegisterFunctionToKeyUpCallback(playerId, "W_up", "w")
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "W_down", "w")
    tm.input.RegisterFunctionToKeyUpCallback(playerId, "S_up", "s")
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "S_down", "s")
    tm.input.RegisterFunctionToKeyUpCallback(playerId, "A_up", "a")
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "A_down", "a")
    tm.input.RegisterFunctionToKeyUpCallback(playerId, "D_up", "d")
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "D_down", "d")
    tm.input.RegisterFunctionToKeyUpCallback(playerId, "Space_up", "space")
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "Space_down", "space")
    tm.input.RegisterFunctionToKeyUpCallback(playerId, "Shift_up", "left shift")
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "Shift_down", "left shift")
end

function ToggleFreeCam(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        tm.os.Log("FreeCam deactivated for playerId: " .. playerId)
        playerData.freeCam = false
        playerData.rotationStructure.structure.Dispose()
        playerData.rotationStructure = nil
        tm.players.GetPlayerTransform(playerId).SetPosition(playerData.lastPosition)
        tm.playerUI.AddSubtleMessageForPlayer(playerId, "FreeCam", "Free Camera Deactivated!", 3)
    else
        tm.os.Log("FreeCam activated for playerId: " .. playerId)
        playerData.freeCam = true
        playerData.lastPosition = tm.players.GetPlayerTransform(playerId).GetPosition()
        Spawn_RotationStructure(playerId)
        tm.players.PlacePlayerInSeat(playerId, playerData.rotationStructure.structureId)
        tm.playerUI.AddSubtleMessageForPlayer(playerId, "FreeCam", "Free Camera Activated!", 3)
    end
end

function W_up(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.forward = false
    end
end

function W_down(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.forward = true
    end
end

function S_up(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.backward = false
    end
end

function S_down(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.backward = true
    end
end

function A_up(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.left = false
    end
end

function A_down(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.left = true
    end
end

function D_up(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.right = false
    end
end

function D_down(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.right = true
    end
end

function Space_up(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.up = false
    end
end

function Space_down(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.up = true
    end
end

function Shift_up(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.down = false
    end
end

function Shift_down(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        playerData.input.down = true
    end
end

--#endregion
