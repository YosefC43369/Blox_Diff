local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- ═══════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════
local State = {
    mode            = "PASSIVE",   -- PASSIVE | ENGAGE | FLANK | RETREAT
    last_kill_time  = 0,
    kill_streak     = 0,
    death_streak    = 0,
    engagement_time = 0,
    target_history  = {},          -- [player] = {last_seen, times_seen}
    threat_map      = {},          -- [player] = threat_score
    frame_kills     = 0,
    detection_risk  = 0.0,         -- 0.0-1.0 risk meter
}

-- ═══════════════════════════════════════
-- PERFORMANCE MONITOR
-- ═══════════════════════════════════════
local Perf = {
    fps_samples  = {},
    avg_fps      = 60,
    last_sample  = tick(),
}

RunService.RenderStepped:Connect(function(dt)
    table.insert(Perf.fps_samples, 1/dt)
    if #Perf.fps_samples > 30 then table.remove(Perf.fps_samples, 1) end
    local sum = 0
    for _, v in ipairs(Perf.fps_samples) do sum = sum + v end
    Perf.avg_fps = sum / #Perf.fps_samples
end)

-- ═══════════════════════════════════════
-- THREAT SCORING
-- ═══════════════════════════════════════
local function ScoreThreats()
    State.threat_map = {}
    local hrp = LocalPlayer.Character
             and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if not p.Character then continue end
        local eHRP = p.Character:FindFirstChild("HumanoidRootPart")
        if not eHRP then continue end

        local dist     = (eHRP.Position - hrp.Position).Magnitude
        local hum      = p.Character:FindFirstChildOfClass("Humanoid")
        local hpPct    = hum and (hum.Health / math.max(hum.MaxHealth,1)) or 1
        local isEnemy  = p.Team ~= LocalPlayer.Team
        local history  = State.target_history[p]
        local seenMult = history and math.min(history.times_seen / 5, 2.0) or 1.0

        -- threat = (inverse distance) * hp_left * enemy_weight * history
        local score = (1000 / math.max(dist, 1)) * hpPct
                    * (isEnemy and 2.0 or 0.5)
                    * seenMult
        State.threat_map[p] = score
    end
end

-- ═══════════════════════════════════════
-- MODE TRANSITION
-- ═══════════════════════════════════════
local function UpdateMode()
    local hrp  = LocalPlayer.Character
              and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local hum  = LocalPlayer.Character
              and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    local hpPct      = hum.Health / math.max(hum.MaxHealth, 1)
    local nearEnemies = 0
    for p, score in pairs(State.threat_map) do
        if p.Team ~= LocalPlayer.Team and score > 50 then
            nearEnemies = nearEnemies + 1
        end
    end

    local prev = State.mode

    if hpPct < 0.25 or State.death_streak >= 3 then
        State.mode = "RETREAT"
    elseif State.kill_streak >= 3 and nearEnemies > 0 then
        State.mode = "ENGAGE"
    elseif nearEnemies == 0 then
        State.mode = "FLANK"
    else
        State.mode = "PASSIVE"
    end

    if State.mode ~= prev then
        print(string.format("[Orchestrator] mode: %s → %s", prev, State.mode))
    end
end

-- ═══════════════════════════════════════
-- ADAPTIVE AIMBOT TUNING
-- ปรับ smoothing + FOV ตาม mode และ detection risk
-- ═══════════════════════════════════════
local function TuneAimbot()
    -- ดึง config จาก pf_cheat ผ่าน _G (ต้อง expose ไว้)
    local cfg = _G.PF_CFG
    if not cfg then return end

    -- risk meter — เพิ่มขึ้นตาม kill streak (ยิ่ง kill เร็ว ยิ่งเสี่ยง detect)
    State.detection_risk = math.clamp(
        State.kill_streak * 0.12 + State.frame_kills * 0.3,
        0, 1.0
    )
    State.frame_kills = 0

    if State.mode == "ENGAGE" then
        -- aggressive — snap เร็ว, FOV กว้าง
        cfg.AIMBOT_SMOOTHING = math.max(0.08, 0.08 + State.detection_risk * 0.12)
        cfg.AIMBOT_FOV       = 160
    elseif State.mode == "PASSIVE" then
        -- conservative — smooth ขึ้น, FOV แคบลง
        cfg.AIMBOT_SMOOTHING = math.min(0.20, 0.14 + State.detection_risk * 0.08)
        cfg.AIMBOT_FOV       = 100
    elseif State.mode == "RETREAT" then
        -- เปิด silent aim แทน aimbot ปกติ
        cfg.AIMBOT_ENABLED = false
        if _G.PF_ADV then _G.PF_ADV.SILENT_AIM = true end
    elseif State.mode == "FLANK" then
        -- ESP สำคัญกว่า aimbot ตอน flank
        cfg.AIMBOT_SMOOTHING = 0.18
        cfg.AIMBOT_FOV       = 80
    end
end

-- ═══════════════════════════════════════
-- TARGET MEMORY
-- ═══════════════════════════════════════
local function UpdateTargetHistory()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local hrp  = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local eHRP = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not eHRP then continue end

        local dist = (eHRP.Position - hrp.Position).Magnitude
        if dist < 300 then
            if not State.target_history[p] then
                State.target_history[p] = {last_seen=0, times_seen=0}
            end
            State.target_history[p].last_seen  = tick()
            State.target_history[p].times_seen = State.target_history[p].times_seen + 1
        end
    end

    -- prune stale entries
    for p, data in pairs(State.target_history) do
        if tick() - data.last_seen > 60 then
            State.target_history[p] = nil
        end
    end
end

-- ═══════════════════════════════════════
-- KILL / DEATH EVENT HOOKS
-- ═══════════════════════════════════════
local function WatchHumanoid()
    local char = LocalPlayer.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    hum.Died:Connect(function()
        State.death_streak = State.death_streak + 1
        State.kill_streak  = 0
        print(string.format("[Orchestrator] death — streak: %d", State.death_streak))
    end)

    -- watch enemy deaths (kills)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local function WatchEnemyChar(eChar)
            local eHum = eChar:FindFirstChildOfClass("Humanoid")
            if not eHum then return end
            eHum.Died:Connect(function()
                if p.Team ~= LocalPlayer.Team then
                    State.kill_streak     = State.kill_streak + 1
                    State.death_streak    = 0
                    State.last_kill_time  = tick()
                    State.frame_kills     = State.frame_kills + 1
                    print(string.format("[Orchestrator] kill +1 — streak: %d", State.kill_streak))
                end
            end)
        end
        if p.Character then WatchEnemyChar(p.Character) end
        p.CharacterAdded:Connect(WatchEnemyChar)
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    WatchHumanoid()
end)
if LocalPlayer.Character then WatchHumanoid() end

-- ═══════════════════════════════════════
-- ORCHESTRATOR HUD
-- ═══════════════════════════════════════
do
    local modeColors = {
        PASSIVE  = Color3.fromRGB(180,180,180),
        ENGAGE   = Color3.fromRGB(255,80,80),
        FLANK    = Color3.fromRGB(80,255,120),
        RETREAT  = Color3.fromRGB(255,200,50),
    }

    local bg = Drawing.new("Square")
    bg.Color        = Color3.fromRGB(0,0,0)
    bg.Transparency = 0.5
    bg.Filled       = true
    bg.Position     = Vector2.new(20, 530)
    bg.Size         = Vector2.new(200, 90)
    bg.Visible      = true

    local function MakeTxt(x, y)
        local t = Drawing.new("Text")
        t.Size    = 12
        t.Position = Vector2.new(x, y)
        t.Outline  = true
        t.Color    = Color3.fromRGB(255,255,255)
        t.Visible  = true
        t.Font     = Drawing.Fonts.Plex
        return t
    end

    local tMode  = MakeTxt(28, 538)
    local tRisk  = MakeTxt(28, 554)
    local tThrt  = MakeTxt(28, 570)
    local tFPS   = MakeTxt(28, 586)
    local tStreak = MakeTxt(28, 602)

    RunService.RenderStepped:Connect(function()
        local topThreat, topScore = "none", 0
        for p, score in pairs(State.threat_map) do
            if score > topScore then
                topScore   = score
                topThreat  = p.Name
            end
        end

        tMode.Text  = "MODE: " .. State.mode
        tMode.Color = modeColors[State.mode] or Color3.fromRGB(255,255,255)
        tRisk.Text  = string.format("RISK: %.0f%%", State.detection_risk * 100)
        tRisk.Color = Color3.fromRGB(
            math.floor(255 * State.detection_risk),
            math.floor(255 * (1-State.detection_risk)), 50)
        tThrt.Text  = string.format("TOP THREAT: %s", topThreat)
        tFPS.Text   = string.format("FPS: %.0f", Perf.avg_fps)
        tStreak.Text = string.format("K-STREAK: %d | D-STREAK: %d",
            State.kill_streak, State.death_streak)
    end)
end

-- ═══════════════════════════════════════
-- MAIN ORCHESTRATOR LOOP
-- ═══════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(0.5)
        ScoreThreats()
        UpdateTargetHistory()
        UpdateMode()
        TuneAimbot()
    end
end)

print("[pf_orchestrator] running — adaptive mode active")