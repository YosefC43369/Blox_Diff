-- lang: Lua, file: pf_cheat.lua, target: Phantom Forces (Roblox), executor: Synapse X / KRNL / Fluxus
-- *offset และ service path อิง Phantom Forces build ปัจจุบัน — re-derive หลัง game update*

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════
local CFG = {
    -- ESP
    ESP_ENABLED       = true,
    ESP_BOX           = true,
    ESP_NAME          = true,
    ESP_DISTANCE      = true,
    ESP_HEALTHBAR     = true,
    ESP_TRACER        = true,
    ESP_SKELETON      = true,
    ESP_MAX_DIST      = 1000,
    COLOR_ENEMY       = Color3.fromRGB(255, 60, 60),
    COLOR_TEAM        = Color3.fromRGB(60, 200, 255),
    COLOR_TRACER      = Color3.fromRGB(255, 255, 0),

    -- AIMBOT
    AIMBOT_ENABLED    = true,
    AIMBOT_KEY        = Enum.KeyCode.Q,       -- hold to aim
    AIMBOT_FOV        = 180,                  -- degrees, set lower for tighter lock
    AIMBOT_SMOOTHING  = 0.12,                 -- 0.0 = instant snap, 1.0 = no movement
    AIMBOT_TARGET     = "Head",               -- "Head" | "HumanoidRootPart" | "Torso"
    AIMBOT_PREDICTION = true,                 -- lead moving targets
    PRED_FACTOR       = 0.07,                 -- velocity scale for prediction

    -- WALLHACK
    WALLHACK_ENABLED  = true,
    CHAMS_ENABLED     = true,
    CHAMS_ENEMY_COLOR = Color3.fromRGB(255, 40, 40),
    CHAMS_TEAM_COLOR  = Color3.fromRGB(40, 140, 255),
}

-- ═══════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════
local function IsAlive(player)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function IsEnemy(player)
    -- Phantom Forces ใช้ Team จาก Teams service
    return player.Team ~= LocalPlayer.Team
end

local function GetRootPart(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function WorldToViewport(pos)
    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen, screenPos.Z
end

local function GetBoundingBox(char)
    -- สร้าง bounding box จาก character parts
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local onScreenAny = false
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local corners = {
                part.Position + Vector3.new( part.Size.X/2,  part.Size.Y/2,  part.Size.Z/2),
                part.Position + Vector3.new(-part.Size.X/2,  part.Size.Y/2,  part.Size.Z/2),
                part.Position + Vector3.new( part.Size.X/2, -part.Size.Y/2,  part.Size.Z/2),
                part.Position + Vector3.new(-part.Size.X/2, -part.Size.Y/2,  part.Size.Z/2),
            }
            for _, corner in ipairs(corners) do
                local sp, onScreen = WorldToViewport(corner)
                if onScreen then
                    onScreenAny = true
                    minX = math.min(minX, sp.X)
                    minY = math.min(minY, sp.Y)
                    maxX = math.max(maxX, sp.X)
                    maxY = math.max(maxY, sp.Y)
                end
            end
        end
    end
    return onScreenAny, minX, minY, maxX, maxY
end

-- ═══════════════════════════════════════
-- DRAWING LAYER — ESP
-- ═══════════════════════════════════════
local ESPObjects = {}

local SKELETON_JOINTS = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
}

local function NewDraw(type_, props)
    local d = Drawing.new(type_)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function CreateESPForPlayer(player)
    local obj = {
        Box      = NewDraw("Square",  {Visible=false, Thickness=1.5, Filled=false}),
        Name     = NewDraw("Text",    {Visible=false, Size=13, Center=true, Outline=true, Font=Drawing.Fonts.Plex}),
        Distance = NewDraw("Text",    {Visible=false, Size=11, Center=true, Outline=true, Font=Drawing.Fonts.Plex}),
        HealthBG = NewDraw("Square",  {Visible=false, Thickness=1, Filled=true, Color=Color3.fromRGB(0,0,0)}),
        HealthFG = NewDraw("Square",  {Visible=false, Thickness=1, Filled=true}),
        Tracer   = NewDraw("Line",    {Visible=false, Thickness=1}),
        Skeleton = {},
    }
    for i = 1, #SKELETON_JOINTS do
        obj.Skeleton[i] = NewDraw("Line", {Visible=false, Thickness=1, Transparency=0.7})
    end
    ESPObjects[player] = obj
end

local function RemoveESPForPlayer(player)
    local obj = ESPObjects[player]
    if not obj then return end
    for _, v in pairs(obj) do
        if type(v) == "table" then
            for _, line in ipairs(v) do line:Remove() end
        else
            v:Remove()
        end
    end
    ESPObjects[player] = nil
end

local function UpdateESP(player, obj)
    local char = player.Character
    if not char or not IsAlive(player) then
        for _, v in pairs(obj) do
            if type(v) == "table" then for _, l in ipairs(v) do l.Visible = false end
            else v.Visible = false end
        end
        return
    end

    local root = GetRootPart(player)
    if not root then return end

    local dist = (root.Position - Camera.CFrame.Position).Magnitude
    if dist > CFG.ESP_MAX_DIST then
        for _, v in pairs(obj) do
            if type(v) == "table" then for _, l in ipairs(v) do l.Visible = false end
            else v.Visible = false end
        end
        return
    end

    local color = IsEnemy(player) and CFG.COLOR_ENEMY or CFG.COLOR_TEAM
    local onScreen, minX, minY, maxX, maxY = GetBoundingBox(char)

    -- BOX
    if CFG.ESP_BOX and onScreen then
        obj.Box.Visible   = true
        obj.Box.Color     = color
        obj.Box.Position  = Vector2.new(minX, minY)
        obj.Box.Size      = Vector2.new(maxX - minX, maxY - minY)
    else obj.Box.Visible = false end

    -- NAME
    local headPos, headOnScreen = WorldToViewport(root.Position + Vector3.new(0, 3.2, 0))
    if CFG.ESP_NAME and headOnScreen then
        obj.Name.Visible  = true
        obj.Name.Color    = color
        obj.Name.Position = Vector2.new(headPos.X, headPos.Y - 18)
        obj.Name.Text     = player.Name
    else obj.Name.Visible = false end

    -- DISTANCE
    if CFG.ESP_DISTANCE and headOnScreen then
        obj.Distance.Visible  = true
        obj.Distance.Color    = Color3.fromRGB(220,220,220)
        obj.Distance.Position = Vector2.new(headPos.X, headPos.Y - 5)
        obj.Distance.Text     = string.format("[%.0fm]", dist)
    else obj.Distance.Visible = false end

    -- HEALTH BAR
    local hum = GetHumanoid(player)
    if CFG.ESP_HEALTHBAR and hum and onScreen then
        local hpPct  = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        local barH   = maxY - minY
        local barX   = minX - 6
        obj.HealthBG.Visible  = true
        obj.HealthBG.Position = Vector2.new(barX, minY)
        obj.HealthBG.Size     = Vector2.new(4, barH)
        obj.HealthFG.Visible  = true
        obj.HealthFG.Position = Vector2.new(barX, minY + barH * (1 - hpPct))
        obj.HealthFG.Size     = Vector2.new(4, barH * hpPct)
        obj.HealthFG.Color    = Color3.fromRGB(
            math.floor(255 * (1 - hpPct)),
            math.floor(255 * hpPct), 0)
    else
        obj.HealthBG.Visible = false
        obj.HealthFG.Visible = false
    end

    -- TRACER
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
    local rootSP, rootOnScreen = WorldToViewport(root.Position)
    if CFG.ESP_TRACER and rootOnScreen then
        obj.Tracer.Visible = true
        obj.Tracer.Color   = CFG.COLOR_TRACER
        obj.Tracer.From    = screenCenter
        obj.Tracer.To      = Vector2.new(rootSP.X, rootSP.Y)
    else obj.Tracer.Visible = false end

    -- SKELETON
    if CFG.ESP_SKELETON then
        for i, joint in ipairs(SKELETON_JOINTS) do
            local p1 = char:FindFirstChild(joint[1])
            local p2 = char:FindFirstChild(joint[2])
            if p1 and p2 then
                local sp1, on1 = WorldToViewport(p1.Position)
                local sp2, on2 = WorldToViewport(p2.Position)
                if on1 and on2 then
                    obj.Skeleton[i].Visible = true
                    obj.Skeleton[i].Color   = color
                    obj.Skeleton[i].From    = sp1
                    obj.Skeleton[i].To      = sp2
                else obj.Skeleton[i].Visible = false end
            else obj.Skeleton[i].Visible = false end
        end
    end
end

-- ═══════════════════════════════════════
-- WALLHACK / CHAMS
-- ═══════════════════════════════════════
local function ApplyChams(player)
    local char = player.Character
    if not char then return end
    local color = IsEnemy(player) and CFG.CHAMS_ENEMY_COLOR or CFG.CHAMS_TEAM_COLOR
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            -- ทำให้ part ลอดผ่านกำแพงได้ด้วย DepthMode
            local box = DrawingBox or nil
            -- ใช้ highlight instance — รองรับทุก executor
            local hl = char:FindFirstChildOfClass("SelectionBox")
            if not hl then
                hl = Instance.new("SelectionBox", char)
                hl.LineThickness = 0.04
                hl.SurfaceTransparency = 0.6
            end
            hl.Color3    = color
            hl.Adornee   = char
        end
    end
end

local function RemoveChams(player)
    local char = player.Character
    if not char then return end
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("SelectionBox") then v:Destroy() end
    end
end

-- ═══════════════════════════════════════
-- AIMBOT
-- ═══════════════════════════════════════
local AimbotTarget = nil

local function GetFOVDistance(screenPos)
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    return (screenPos - center).Magnitude
end

local function FindBestTarget()
    local bestDist = math.huge
    local bestPlayer = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not IsEnemy(player) then continue end
        if not IsAlive(player) then continue end

        local char  = player.Character
        local tpart = char and char:FindFirstChild(CFG.AIMBOT_TARGET)
        if not tpart then continue end

        local root = GetRootPart(player)
        if not root then continue end

        local dist3d = (root.Position - Camera.CFrame.Position).Magnitude
        if dist3d > CFG.ESP_MAX_DIST then continue end

        local sp, onScreen = WorldToViewport(tpart.Position)
        if not onScreen then continue end

        local fovDist = GetFOVDistance(sp)
        local fovRad  = Camera.ViewportSize.X * math.tan(math.rad(CFG.AIMBOT_FOV / 2))
        if fovDist < fovRad and fovDist < bestDist then
            bestDist   = fovDist
            bestPlayer = player
        end
    end
    return bestPlayer
end

local function PredictPosition(root)
    -- linear velocity prediction — FastCast ใน PF ทำให้ต้องชดเชย bullet travel
    if not CFG.AIMBOT_PREDICTION then return root.Position end
    local vel = root.AssemblyLinearVelocity
    return root.Position + vel * CFG.PRED_FACTOR
end

local AimActive = false
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.AIMBOT_KEY then AimActive = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == CFG.AIMBOT_KEY then AimActive = false; AimbotTarget = nil end
end)

-- ═══════════════════════════════════════
-- PLAYER LIFECYCLE
-- ═══════════════════════════════════════
local function OnPlayerAdded(player)
    if player == LocalPlayer then return end
    CreateESPForPlayer(player)

    player.CharacterAdded:Connect(function(char)
        wait(0.5)
        if CFG.WALLHACK_ENABLED and CFG.CHAMS_ENABLED then ApplyChams(player) end
    end)

    if player.Character then
        if CFG.WALLHACK_ENABLED and CFG.CHAMS_ENABLED then ApplyChams(player) end
    end
end

local function OnPlayerRemoving(player)
    RemoveESPForPlayer(player)
    RemoveChams(player)
end

for _, p in ipairs(Players:GetPlayers()) do OnPlayerAdded(p) end
Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

-- ═══════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════
RunService.RenderStepped:Connect(function()
    -- ESP update
    if CFG.ESP_ENABLED then
        for player, obj in pairs(ESPObjects) do
            UpdateESP(player, obj)
        end
    end

    -- Aimbot
    if CFG.AIMBOT_ENABLED and AimActive then
        AimbotTarget = FindBestTarget()
        if AimbotTarget and IsAlive(AimbotTarget) then
            local char  = AimbotTarget.Character
            local tpart = char and char:FindFirstChild(CFG.AIMBOT_TARGET)
            if tpart then
                local root    = GetRootPart(AimbotTarget)
                local aimPos  = root and PredictPosition(root) or tpart.Position
                -- Head offset ขึ้นเล็กน้อยจาก predicted root
                if CFG.AIMBOT_TARGET == "Head" then
                    aimPos = aimPos + Vector3.new(0, 1.5, 0)
                end
                local targetCF = CFrame.new(Camera.CFrame.Position, aimPos)
                Camera.CFrame  = Camera.CFrame:Lerp(targetCF, CFG.AIMBOT_SMOOTHING)
            end
        end
    end
end)

print("[pf_cheat] loaded — Q=aimbot toggle")