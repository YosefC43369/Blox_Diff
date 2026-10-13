local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")
local Camera        = workspace.CurrentCamera
local LocalPlayer   = Players.LocalPlayer
local HttpService   = game:GetService("HttpService")

-- ═══════════════════════════════════════
-- ADVANCED CONFIG
-- ═══════════════════════════════════════
local ADV = {
    -- Silent Aim (ยิงไม่ต้องชี้ — redirect bullet server-side via CFrame hook)
    SILENT_AIM        = true,
    SILENT_FOV        = 120,
    SILENT_PART       = "Head",

    -- Triggerbot
    TRIGGER_ENABLED   = true,
    TRIGGER_DELAY     = 0.05,   -- วินาที delay ก่อนยิง (human-like)
    TRIGGER_KEY       = Enum.KeyCode.T,  -- hold = active

    -- Recoil Suppression
    NO_RECOIL         = true,
    RECOIL_STRENGTH   = 0.0,    -- 0.0 = ไม่มี recoil เลย

    -- Anti-AFK
    ANTI_AFK          = true,

    -- Radar
    RADAR_ENABLED     = true,
    RADAR_SIZE        = 200,
    RADAR_RANGE       = 500,
    RADAR_X           = 20,
    RADAR_Y           = 200,

    -- Speed / BHop
    BHOP_ENABLED      = false,
    SPEED_MULT        = 1.0,    -- 1.0 = default, เพิ่มแล้ว server kick ง่าย

    -- Infinite Ammo
    INF_AMMO          = true,

    -- FOV Circle
    FOV_CIRCLE        = true,
    FOV_RADIUS        = 120,
    FOV_COLOR         = Color3.fromRGB(255,255,255),

    -- Auto-Reload
    AUTO_RELOAD       = true,

    -- Prediction Enhancement
    ADV_PREDICTION    = true,
    GRAVITY_COMP      = true,   -- ชดเชย drop กระสุนตาม velocity
    PING_COMP         = true,   -- ชดเชยปิง server
}

-- ═══════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════
local function GetChar()  return LocalPlayer.Character end
local function GetHRP()
    local c = GetChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function GetHum()
    local c = GetChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function IsEnemy(p)  return p.Team ~= LocalPlayer.Team end
local function IsAlive(p)
    local c = p.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function GetPing()
    -- ดึงปิงจาก Stats service
    local ok, ping = pcall(function()
        return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
    end)
    return ok and ping or 80
end

-- ═══════════════════════════════════════
-- FOV CIRCLE
-- ═══════════════════════════════════════
local FovCircle = Drawing.new("Circle")
FovCircle.Visible     = ADV.FOV_CIRCLE
FovCircle.Thickness   = 1.2
FovCircle.Color       = ADV.FOV_COLOR
FovCircle.Filled      = false
FovCircle.Transparency = 0.8
FovCircle.NumSides    = 64

RunService.RenderStepped:Connect(function()
    if ADV.FOV_CIRCLE then
        FovCircle.Visible  = true
        FovCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        FovCircle.Radius   = ADV.FOV_RADIUS
    else
        FovCircle.Visible = false
    end
end)

-- ═══════════════════════════════════════
-- MINI RADAR
-- ═══════════════════════════════════════
local RadarFrame = Drawing.new("Square")
RadarFrame.Visible   = ADV.RADAR_ENABLED
RadarFrame.Color     = Color3.fromRGB(0,0,0)
RadarFrame.Transparency = 0.45
RadarFrame.Filled    = true
RadarFrame.Position  = Vector2.new(ADV.RADAR_X, ADV.RADAR_Y)
RadarFrame.Size      = Vector2.new(ADV.RADAR_SIZE, ADV.RADAR_SIZE)

local RadarBorder = Drawing.new("Square")
RadarBorder.Visible  = ADV.RADAR_ENABLED
RadarBorder.Color    = Color3.fromRGB(80,80,80)
RadarBorder.Filled   = false
RadarBorder.Thickness = 1.5
RadarBorder.Position = Vector2.new(ADV.RADAR_X, ADV.RADAR_Y)
RadarBorder.Size     = Vector2.new(ADV.RADAR_SIZE, ADV.RADAR_SIZE)

-- cross lines
local RadarH = Drawing.new("Line")
RadarH.Color = Color3.fromRGB(60,60,60)
RadarH.Thickness = 1
local RadarV = Drawing.new("Line")
RadarV.Color = Color3.fromRGB(60,60,60)
RadarV.Thickness = 1

-- self dot
local SelfDot = Drawing.new("Circle")
SelfDot.Color    = Color3.fromRGB(0,255,0)
SelfDot.Filled   = true
SelfDot.Radius   = 4
SelfDot.NumSides = 12

local RadarDots = {}

local function UpdateRadar()
    if not ADV.RADAR_ENABLED then return end
    local cx   = ADV.RADAR_X + ADV.RADAR_SIZE/2
    local cy   = ADV.RADAR_Y + ADV.RADAR_SIZE/2
    local hrp  = GetHRP()

    RadarH.From = Vector2.new(ADV.RADAR_X, cy)
    RadarH.To   = Vector2.new(ADV.RADAR_X + ADV.RADAR_SIZE, cy)
    RadarH.Visible = true
    RadarV.From = Vector2.new(cx, ADV.RADAR_Y)
    RadarV.To   = Vector2.new(cx, ADV.RADAR_Y + ADV.RADAR_SIZE)
    RadarV.Visible = true
    SelfDot.Position = Vector2.new(cx, cy)
    SelfDot.Visible  = true

    -- cleanup old dots
    for _, d in pairs(RadarDots) do d:Remove() end
    RadarDots = {}

    if not hrp then return end
    local camY = math.rad(-Camera.CFrame:ToEulerAnglesYXZ())

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not IsAlive(player) then continue end
        local eHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not eHRP then continue end

        local diff  = eHRP.Position - hrp.Position
        local dist  = diff.Magnitude
        if dist > ADV.RADAR_RANGE then continue end

        -- rotate diff บน radar plane
        local angle = math.atan2(diff.X, diff.Z) + camY
        local scale = (dist / ADV.RADAR_RANGE) * (ADV.RADAR_SIZE/2 - 8)
        local rx    = cx + math.sin(angle) * scale
        local ry    = cy - math.cos(angle) * scale

        local dot = Drawing.new("Circle")
        dot.Color    = IsEnemy(player) and Color3.fromRGB(255,60,60) or Color3.fromRGB(60,180,255)
        dot.Filled   = true
        dot.Radius   = 4
        dot.NumSides = 10
        dot.Position = Vector2.new(rx, ry)
        dot.Visible  = true
        table.insert(RadarDots, dot)
    end
end

-- ═══════════════════════════════════════
-- SILENT AIM
-- ═══════════════════════════════════════
-- hook Camera CFrame ตอน ray cast — redirect bullet origin ไป head target
local OriginalIndex = nil

local function GetSilentTarget()
    local best, bestDist = nil, math.huge
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local fovPx  = Camera.ViewportSize.X * math.tan(math.rad(ADV.SILENT_FOV/2))

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if not IsEnemy(p) then continue end
        if not IsAlive(p) then continue end
        local c    = p.Character
        local part = c and c:FindFirstChild(ADV.SILENT_PART)
        if not part then continue end
        local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then continue end
        local sv   = Vector2.new(sp.X, sp.Y)
        local d    = (sv - center).Magnitude
        if d < fovPx and d < bestDist then
            bestDist = d
            best     = part
        end
    end
    return best
end

if ADV.SILENT_AIM then
    local mt = getrawmetatable(game)
    local old_index = mt.__index
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args   = {...}

        -- intercept Camera:WorldToScreenPoint during shooting phase
        if method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRay" then
            local target = GetSilentTarget()
            if target then
                local ray    = args[1]
                local origin = ray.Origin
                local dir    = (target.Position - origin).Unit * ray.Direction.Magnitude
                args[1]      = Ray.new(origin, dir)
            end
        end
        return old_index(self, unpack(args))
    end)

    setreadonly(mt, true)
end

-- ═══════════════════════════════════════
-- TRIGGERBOT
-- ═══════════════════════════════════════
local TriggerActive = false
UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == ADV.TRIGGER_KEY then TriggerActive = true end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.KeyCode == ADV.TRIGGER_KEY then TriggerActive = false end
end)

local function RunTriggerbot()
    while true do
        task.wait(0.01)
        if not ADV.TRIGGER_ENABLED or not TriggerActive then continue end

        -- raycast จาก camera ตรงไป crosshair
        local unitRay = Camera:ScreenPointToRay(
            Camera.ViewportSize.X/2,
            Camera.ViewportSize.Y/2
        )
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {GetChar()}
        params.FilterType = Enum.RaycastFilterType.Exclude

        local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)
        if result and result.Instance then
            local hit = result.Instance
            local char = hit:FindFirstAncestorOfClass("Model")
            if char then
                local player = Players:GetPlayerFromCharacter(char)
                if player and player ~= LocalPlayer and IsEnemy(player) and IsAlive(player) then
                    task.wait(ADV.TRIGGER_DELAY)
                    -- simulate mouse click
                    mouse1press()
                    task.wait(0.07)
                    mouse1release()
                end
            end
        end
    end
end
task.spawn(RunTriggerbot)

-- ═══════════════════════════════════════
-- NO RECOIL
-- ═══════════════════════════════════════
if ADV.NO_RECOIL then
    local mt     = getrawmetatable(game)
    local oldNc  = mt.__newindex
    setreadonly(mt, false)

    mt.__newindex = newcclosure(function(self, key, value)
        -- block CFrame write ที่ทำให้กล้องกระตุกจาก recoil pattern
        if self == Camera and key == "CFrame" then
            local hrp = GetHRP()
            if hrp then
                local lv  = Camera.CFrame.LookVector
                local pos = Camera.CFrame.Position
                -- clamp vertical CFrame shift ที่ game inject เข้ามา
                local newLv = value.LookVector
                local diff  = newLv - lv
                if diff.Y > 0.015 then
                    value = CFrame.new(pos) * CFrame.fromMatrix(
                        Vector3.zero, value.RightVector,
                        Vector3.new(0,1,0), -lv
                    )
                end
            end
        end
        return oldNc(self, key, value)
    end)

    setreadonly(mt, true)
end

-- ═══════════════════════════════════════
-- INFINITE AMMO
-- ═══════════════════════════════════════
if ADV.INF_AMMO then
    -- hook ReplicatedStorage gun module — path อิง PF build ปัจจุบัน
    task.spawn(function()
        while true do
            task.wait(0.5)
            local char = GetChar()
            if not char then continue end
            -- scan tool > gun module > ammo value
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") then
                    local ammoVal = tool:FindFirstChild("AmmoInClip")
                            or tool:FindFirstChild("Ammo")
                    if ammoVal and ammoVal:IsA("IntValue") then
                        if ammoVal.Value < 5 then
                            ammoVal.Value = ammoVal.MaxValue or 30
                        end
                    end
                end
            end
        end
    end)
end

-- ═══════════════════════════════════════
-- AUTO RELOAD
-- ═══════════════════════════════════════
if ADV.AUTO_RELOAD then
    task.spawn(function()
        while true do
            task.wait(0.1)
            local char = GetChar()
            if not char then continue end
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") then
                    local ammo = tool:FindFirstChild("AmmoInClip") or tool:FindFirstChild("Ammo")
                    if ammo and ammo:IsA("IntValue") and ammo.Value == 0 then
                        -- fire reload remote
                        local reloadRE = tool:FindFirstChild("ReloadEvent")
                                      or tool:FindFirstChild("Reload")
                        if reloadRE and reloadRE:IsA("RemoteEvent") then
                            reloadRE:FireServer()
                        end
                    end
                end
            end
        end
    end)
end

-- ═══════════════════════════════════════
-- ANTI-AFK
-- ═══════════════════════════════════════
if ADV.ANTI_AFK then
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end

-- ═══════════════════════════════════════
-- ADVANCED PREDICTION (Gravity + Ping)
-- ═══════════════════════════════════════
local function GetAdvancedAimPos(root)
    if not ADV.ADV_PREDICTION then return root.Position end
    local vel   = root.AssemblyLinearVelocity
    local ping  = ADV.PING_COMP and (GetPing() / 1000) or 0
    local dist  = (root.Position - Camera.CFrame.Position).Magnitude
    -- bullet travel time estimate — PF muzzle velocity ~900 studs/s average
    local travelTime = dist / 900 + ping
    local predicted  = root.Position + vel * travelTime
    -- gravity compensation — 9.8 stud/s² Roblox default
    if ADV.GRAVITY_COMP then
        predicted = predicted - Vector3.new(0, 0.5 * 9.8 * travelTime^2, 0)
    end
    return predicted
end

-- export สำหรับใช้จาก pf_cheat.lua
_G.AdvPrediction  = GetAdvancedAimPos
_G.GetSilentTarget = GetSilentTarget

-- ═══════════════════════════════════════
-- MAIN LOOP (Radar)
-- ═══════════════════════════════════════
RunService.RenderStepped:Connect(function()
    UpdateRadar()
end)

print("[pf_advanced] loaded — T=triggerbot | modules: silent_aim, no_recoil, radar, inf_ammo")