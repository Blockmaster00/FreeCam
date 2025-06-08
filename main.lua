local playerDataTable = {}

local angle = math.rad(270)
local correctionQuat = tm.quaternion.Create(math.cos(angle / 2), 0, math.sin(angle / 2), 0) -- to correct the rotation of the cursor block

tm.physics.AddTexture("blueprints/cameraTracker.png", "rotationStructure")


function onPlayerJoined(player)
    tm.os.Log("Player joined: " .. player.playerId)

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

    -- Initialize Structure Plattform
    local plattformPos = tm.vector3.Create(0, -101, 10 * playerId)
    playerData.plattform = tm.physics.SpawnObject(plattformPos, "PFB_MagneticCube")
    playerData.plattform.GetTransform().SetScale(tm.vector3.Create(5, 1, 5))
    playerData.plattform.SetIsStatic(true)

    -- Store the player data in a global table
    playerDataTable[playerId] = playerData
    tm.os.Log("|-> Player data initialized for playerId: " .. playerId)

    -- Initialize Camera
    tm.players.AddCamera(playerId, tm.vector3.Create(0, 0, 0), tm.vector3.Create(0, 0, 0))
    Init_Cursor(playerId)
    -- Initialize player input
    Init_playerInput(playerId)
    tm.os.Log("")
end

tm.players.OnPlayerJoined.add(onPlayerJoined)

function onPlayerLeft(player)
    local playerId = player.playerId
    local playerData = playerDataTable[playerId]

    tm.os.Log("Player left: " .. playerId)

    -- Clean up player data
    if playerDataTable[playerId] then
        tm.os.Log("|-> Cleaning up player data")
        -- Remove Structure Plattform
        if playerData.plattform then
            playerData.plattform.Despawn()
            tm.os.Log("|-> Plattform disposed")
        end

        -- Despawn Rotation Structure
        if playerData.rotationStructure and playerData.rotationStructure.structure then
            Despawn_RotationStructure(playerId)
        end
        playerDataTable[playerId] = nil
        tm.os.Log("Player data cleared for playerId: " .. playerId)
    end
end

tm.players.OnPlayerLeft.add(onPlayerLeft)


function update()
    local players = tm.players.CurrentPlayers()

    for _, player in ipairs(players) do
        PlayerUpdate(player)
    end
end

function PlayerUpdate(player)
    local playerId = player.playerId
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        if not tm.players.IsPlayerInSeat(playerId) then
            tm.playerUI.AddSubtleMessageForPlayer(playerId, "FreeCam", "Deactivate FreeCam first!", 3)
            tm.players.PlacePlayerInSeat(playerId, playerData.rotationStructure.structureId)
        end

        local playerSeat = tm.players.GetPlayerSeatBlock(playerId)

        local targetRotation = tm.quaternion.Create(TargetRot(tm.vector3.Create(0, 0, 0), playerSeat.Forward()))
        local smoothedRotation = tm.quaternion.Slerp(
            playerData.camera.rotation,
            targetRotation,
            0.1 -- smoothing factor
        )

        playerData.camera.rotation = smoothedRotation
        tm.players.SetCameraRotation(playerId, PPointing(playerData.camera.rotation.GetEuler()))

        -- Update camera position and direction based on player rotationStructure
        --CURSOR POSITIONING


        local cursorBlock = playerData.rotationStructure.cursorBlock

        local cursorBlockRot = tm.quaternion.Create(TargetRot(tm.vector3.Create(0, 0, 0), cursorBlock.Forward())) -- Get the rotation of the cursor block in quaternion form
        cursorBlockRot = cursorBlockRot.Multiply(correctionQuat)                                                  -- Apply correction quaternion

        local combinedRotation = playerData.camera.rotation.Multiply(cursorBlockRot)
        local cursorDirection = GetForward(combinedRotation)
        cursorDirection = Normalize(cursorDirection)
        local cursorRaycast = tm.physics.RaycastData(
            playerData.camera.position,
            cursorDirection,
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
        else
            -- If no hit, just set the cursor to a default position
            playerData.cursor.GetTransform().SetPosition(playerData.camera.position + cursorDirection * 7)
            playerData.cursor.GetTransform().SetScale(tm.vector3.Create(0.005, 0.005, 0.005) * 7)
        end

        -- Update camera position based on input
        if playerData.input.forward then
            playerData.camera.position = playerData.camera.position +
                PPointing(playerData.camera.rotation.GetEuler()) * playerData.camera.speed
        end

        if playerData.input.backward then
            playerData.camera.position = playerData.camera.position -
                PPointing(playerData.camera.rotation.GetEuler()) * playerData.camera.speed
        end

        if playerData.input.left then
            -- Move left relative to camera's rotation (strafe left)
            local forward = PPointing(playerData.camera.rotation.GetEuler())
            local up = tm.vector3.Create(0, 1, 0)
            local left = Normalize(forward.Cross(up))
            playerData.camera.position = playerData.camera.position + left * playerData.camera.speed
        end

        if playerData.input.right then
            -- Move right relative to camera's rotation (strafe right)
            local forward = PPointing(playerData.camera.rotation.GetEuler())
            local up = tm.vector3.Create(0, 1, 0)
            local right = Normalize(up.Cross(forward))
            playerData.camera.position = playerData.camera.position + right * playerData.camera.speed
        end

        if playerData.input.up then
            playerData.camera.position = playerData.camera.position +
                tm.vector3.Create(0, 1, 0) * playerData.camera.speed
        end
        if playerData.input.down then
            playerData.camera.position = playerData.camera.position -
                tm.vector3.Create(0, 1, 0) * playerData.camera.speed
        end

        tm.players.SetCameraPosition(playerId, playerData.camera.position)
    end
end

function Init_Cursor(playerId)
    local playerData = playerDataTable[playerId]
    playerData.cursor = tm.physics.SpawnObject(
        tm.vector3.Create(0, 0, 0),
        "PFB_Whale"
    )
    playerData.cursor.GetTransform().SetScale(tm.vector3.Create(0.05, 0.05, 0.05))
end

function Spawn_RotationStructure(playerId)
    tm.os.Log("Spawn_RotationStructure called for playerId: " .. playerId)

    local playerData = playerDataTable[playerId]
    local structurePos = tm.vector3.Create(0, -100, 10 * playerId)
    local structureId = "rStructure_" .. playerId .. "_" .. tm.os.GetTime()
    tm.os.Log("Structure ID: " .. structureId)
    --
    -- Create Rotation Structure

    tm.players.SpawnStructure(
        playerId,
        "rotationStructure",
        structureId,
        structurePos,
        tm.vector3.Create(1, 0, 0)
    )
    local structure = tm.players.GetSpawnedStructureById(structureId)[1]

    --
    -- locate and save the cursor block
    local cursorBlock
    local blockList = structure.GetBlocks()
    for i, block in ipairs(blockList) do
        if block.GetName() == "PFB_MixelEye_Sphere [Server]" then
            cursorBlock = block
            tm.os.Log("Cursor block found")
            break
        end
    end

    playerData.rotationStructure = {
        structure = structure,
        structureId = structureId,
        cursorBlock = cursorBlock
    }
end

function Despawn_RotationStructure(playerId)
    tm.os.Log("Despawn_RotationStructure called for playerId: " .. playerId)
    local playerData = playerDataTable[playerId]

    if playerData.rotationStructure.structure then
        local structure = playerData.rotationStructure.structure
        structure.Dispose()
        playerData.rotationStructure = nil
        tm.os.Log("Rotation structure despawned for playerId: " .. playerId)
    else
        tm.os.Log("No rotation structure to despawn for playerId: " .. playerId)
    end
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
    local angleradY = math.atan2(relativeX, relativeZ)
    local relativeangY = math.deg(angleradY)
    local relativehori = math.sqrt(relativeX * relativeX + relativeZ * relativeZ)
    local angleradX = math.atan2(relativeY, relativehori)
    local relativeangX = math.deg(angleradX)
    local relativetot = tm.vector3.Create(relativeangX, relativeangY, 0)
    return relativetot
end

function Normalize(v)
    local length = v.Magnitude()
    if length == 0 then
        return tm.vector3.Create(0, 0, 0)
    else
        return tm.vector3.Create(v.x / length, v.y / length, v.z / length)
    end
end

function GetForward(quat)
    -- Extract the quaternion components
    local w = quat.w
    local x = quat.x
    local y = quat.y
    local z = quat.z

    -- Calculate the forward vector using the rotation matrix row corresponding to the forward axis.
    local forwardX = 2 * (x * z + w * y)
    local forwardY = 2 * (y * z - w * x)
    local forwardZ = 1 - 2 * (x * x + y * y)

    return tm.vector3.Create(forwardX, forwardY, forwardZ)
end

--#endregion


--#region PLAYER INPUT

function Init_playerInput(playerId)
    local playerData = playerDataTable[playerId]

    tm.playerUI.AddSubtleMessageForPlayer(playerId, "FreeCam", "<sprite index=145> to toggle", 10)

    tm.input.RegisterFunctionToKeyDownCallback(playerId,
        "ToggleFreeCam", "left alt")
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

    tm.os.Log("|-> Player input initialized for playerId: " .. playerId)
end

function ToggleFreeCam(playerId)
    local playerData = playerDataTable[playerId]

    if playerData.freeCam then
        tm.os.Log("FreeCam deactivated for playerId: " .. playerId)

        playerData.freeCam = false

        Despawn_RotationStructure(playerId)
        tm.players.GetPlayerTransform(playerId).SetPosition(playerData.lastPosition)

        --deactivate Camera
        tm.players.DeactivateCamera(playerId, 0)
        tm.playerUI.AddSubtleMessageForPlayer(playerId, "FreeCam", "Free Camera Deactivated!", 3)
        tm.os.Log("")
    else
        tm.os.Log("FreeCam activated for playerId: " .. playerId)

        playerData.freeCam = true

        playerData.lastPosition = tm.players.GetPlayerTransform(playerId).GetPosition()
        Spawn_RotationStructure(playerId)
        tm.players.PlacePlayerInSeat(playerId, playerData.rotationStructure.structureId)

        -- activate Camera
        if playerData.camera.position == nil or playerData.camera.rotation == nil then
            playerData.camera.position = playerData.lastPosition + tm.vector3.Create(0, 2, 0)
            playerData.camera.rotation = tm.quaternion.Create(0, 0, 1)
        end
        tm.players.SetCameraPosition(playerId, playerData.camera.position)
        tm.players.SetCameraRotation(playerId, PPointing(playerData.camera.rotation.GetEuler()))
        tm.players.ActivateCamera(playerId, 0)


        tm.playerUI.AddSubtleMessageForPlayer(playerId, "FreeCam", "Free Camera Activated!", 3)
        tm.os.Log("")
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

tm.os.Log([[

    ______                  ______        v0.0.1
   / ____/_______  ___     / ____/___ _____ ___
  / /_  / ___/ _ \/ _ \   / /   / __ `/ __ `__ \
 / __/ / /  /  __/  __/  / /___/ /_/ / / / / / /
/_/   /_/   \___/\___/   \____/\__,_/_/ /_/ /_/
by Blockhampter]])
