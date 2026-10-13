local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- ═══════════════════════════════════════
-- MODULE 1: KILL AURA
-- auto-damage players ใน radius ผ่าน remote
-- ═══════════════════════════════════════
local KillAura = {}
KillAura.CFG = {
    ENABLED  = false,   -- off by default — server-side detect สูง เปิดเมื่อ test เท่านั้น
    RADIUS   = 20,      -- studs
    DELAY    = 0.15,    -- วินาทีระหว่างแต่ละ hit
    KEY      = Enum.KeyCode.K,
}

do
    local active = false
    UserInputService.InputBegan:Connect(function(i, gp)
        if gp then return end
        if i.KeyCode == KillAura.CFG.KEY then active = not active
            print("[KillAura] " .. (active and "ON" or "OFF"))
        end
    end)

    task.spawn(function()
        while true do
            task.wait(KillAura.CFG.DELAY)
            if not KillAura.CFG.ENABLED or not active then continue end
            local hrp = LocalPlayer.Character
                     and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end

            for _, p in ipairs(Players:GetPlayers()) do
                if p == LocalPlayer then continue end
                if not (p.Character and p.Character:FindFirstChildOfClass("Humanoid")) then continue end
                local eHRP = p.Character:FindFirstChild("HumanoidRootPart")
                if not eHRP then continue end
                if (eHRP.Position - hrp.Position).Magnitude > KillAura.CFG.RADIUS then continue end

                -- scan tool remotes สำหรับ damage event
                local char = LocalPlayer.Character
                for _, tool in ipairs(char:GetChildren()) do
                    if not tool:IsA("Tool") then continue end
                    local dmgRE = tool:FindFirstChild("DamageEvent")
                             or tool:FindFirstChild("HitEvent")
                             or tool:FindFirstChild("Damage")
                    if dmgRE and dmgRE:IsA("RemoteEvent") then
                        pcall(function()
                            dmgRE:FireServer(p.Character, eHRP.Position)
                        end)
                    end
                end
            end
        end
    end)
end

-- ═══════════════════════════════════════
-- MODULE 2: BULLET TRACER VISUALIZER
-- วาดเส้น tracer ทุกกระสุนที่ยิงในเกม (ศัตรู + เพื่อน)
-- ═══════════════════════════════════════
local BulletTracer = {}
BulletTracer.CFG = {
    ENABLED        = true,
    ENEMY_COLOR    = Color3.fromRGB(255, 80, 80),
    FRIENDLY_COLOR = Color3.fromRGB(80, 180, 255),
    SELF_COLOR     = Color3.fromRGB(255, 255, 0),
    FADE_TIME      = 1.2,   -- วินาที
    THICKNESS      = 1.0,
}

do
    local tracers = {}

    local function SpawnTracer(from, to, color)
        local line = Drawing.new("Line")
        line.From        = from
        line.To          = to
        line.Color       = color
        line.Thickness   = BulletTracer.CFG.THICKNESS
        line.Transparency = 1.0
        line.Visible     = true

        local startTime = tick()
        local conn
        conn = RunService.RenderStepped:Connect(function()
            local elapsed = tick() - startTime
            local alpha   = 1 - (elapsed / BulletTracer.CFG.FADE_TIME)
            if alpha <= 0 then
                line:Remove()
                conn:Disconnect()
                return
            end
            line.Transparency = alpha
        end)
    end

    -- hook FastCast bullet creation event ของ PF
    -- PF ใช้ RemoteEvent ชื่อ "ShotEvent" broadcast ไป client ทุกคน
    local function HookShots()
        local RS  = game:GetService("ReplicatedStorage")
        -- scan หา ShotEvent หรือ BulletEvent
        local function TryScanEvents(container)
            for _, v in ipairs(container:GetDescendants()) do
                if v:IsA("RemoteEvent") and
                   (v.Name:lower():find("shot") or v.Name:lower():find("bullet") or v.Name:lower():find("fire")) then
                    v.OnClientEvent:Connect(function(shooter, origin, direction, distance)
                        if not BulletTracer.CFG.ENABLED then return end
                        if type(origin) ~= "userdata" then return end
                        if type(direction) ~= "userdata" then return end

                        local endPos = origin + direction.Unit * (distance or 500)
                        local sp1, on1 = Camera:WorldToViewportPoint(origin)
                        local sp2, on2 = Camera:WorldToViewportPoint(endPos)
                        if not on1 and not on2 then return end

                        local color
                        if shooter == LocalPlayer then
                            color = BulletTracer.CFG.SELF_COLOR
                        elseif shooter and shooter.Team == LocalPlayer.Team then
                            color = BulletTracer.CFG.FRIENDLY_COLOR
                        else
                            color = BulletTracer.CFG.ENEMY_COLOR
                        end

                        SpawnTracer(
                            Vector2.new(sp1.X, sp1.Y),
                            Vector2.new(sp2.X, sp2.Y),
                            color
                        )
                    end)
                end
            end
        end

        TryScanEvents(RS)
        RS.DescendantAdded:Connect(function(v)
            task.wait(0.1)
            TryScanEvents(RS)
        end)
    end

    task.spawn(HookShots)
end

-- ═══════════════════════════════════════
-- MODULE 3: POSITION PREDICTOR + LEAD INDICATOR
-- วาด crosshair ที่ควรชี้เพื่อให้กระสุนไปโดน predicted position
-- ═══════════════════════════════════════
local LeadIndicator = {}
LeadIndicator.CFG = {
    ENABLED      = true,
    COLOR        = Color3.fromRGB(255, 200, 0),
    SIZE         = 8,
    MUZZLE_VEL   = 900,   -- studs/s — PF average
    SHOW_LINE    = true,  -- เส้นจาก crosshair ไป indicator
}

do
    local dot  = Drawing.new("Circle")
    dot.Filled   = true
    dot.Radius   = LeadIndicator.CFG.SIZE / 2
    dot.NumSides = 16
    dot.Color    = LeadIndicator.CFG.COLOR
    dot.Visible  = false

    local line = Drawing.new("Line")
    line.Color     = Color3.fromRGB(200,200,200)
    line.Thickness = 1
    line.Visible   = false

    RunService.RenderStepped:Connect(function()
        if not LeadIndicator.CFG.ENABLED then
            dot.Visible  = false
            line.Visible = false
            return
        end

        -- ใช้ target จาก aimbot ถ้ามี
        local target = _G.AimbotTarget
        if not target or not target.Character then
            dot.Visible  = false
            line.Visible = false
            return
        end

        local root = target.Character:FindFirstChild("HumanoidRootPart")
        if not root then dot.Visible = false; return end

        local dist       = (root.Position - Camera.CFrame.Position).Magnitude
        local ping       = 0.08  -- fallback ping
        local travelTime = dist / LeadIndicator.CFG.MUZZLE_VEL + ping
        local vel        = root.AssemblyLinearVelocity
        local predicted  = root.Position + vel * travelTime
                         - Vector3.new(0, 0.5 * 9.8 * travelTime^2, 0)
                         + Vector3.new(0, 1.5, 0)  -- head offset

        local sp, onScreen = Camera:WorldToViewportPoint(predicted)
        if not onScreen then
            dot.Visible  = false
            line.Visible = false
            return
        end

        local sv = Vector2.new(sp.X, sp.Y)
        dot.Position = sv
        dot.Visible  = true

        if LeadIndicator.CFG.SHOW_LINE then
            local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
            line.From    = center
            line.To      = sv
            line.Visible = true
        else
            line.Visible = false
        end
    end)
end

-- ═══════════════════════════════════════
-- MODULE 4: SOUND ESP
-- เปลี่ยน footstep / reload sound ของศัตรูให้ดังขึ้น 3x
-- ═══════════════════════════════════════
local SoundESP = {}
SoundESP.CFG = {
    ENABLED     = true,
    STEP_VOLUME = 3.0,
    SHOT_VOLUME = 0.4,   -- ลดเสียงปืนศัตรู (ไม่ให้หูหนวก)
    RELOAD_VOL  = 3.0,
}

do
    local function PatchSounds(char, player)
        if not char then return end
        for _, s in ipairs(char:GetDescendants()) do
            if not s:IsA("Sound") then continue end
            local n = s.Name:lower()
            if n:find("step") or n:find("walk") or n:find("run") then
                s.Volume = SoundESP.CFG.STEP_VOLUME
            elseif n:find("reload") then
                s.Volume = SoundESP.CFG.RELOAD_VOL
            elseif n:find("fire") or n:find("shot") then
                s.Volume = SoundESP.CFG.SHOT_VOLUME
            end
        end
    end

    local function WatchPlayer(p)
        if p == LocalPlayer then return end
        if p.Character then PatchSounds(p.Character, p) end
        p.CharacterAdded:Connect(function(char)
            task.wait(0.5)
            PatchSounds(char, p)
        end)
    end

    for _, p in ipairs(Players:GetPlayers()) do WatchPlayer(p) end
    Players.PlayerAdded:Connect(WatchPlayer)
end

-- ═══════════════════════════════════════
-- MODULE 5: MATCH STATS TRACKER
-- track K/D, headshot %, damage dealt ตลอด session
-- ═══════════════════════════════════════
local StatsTracker = {}
StatsTracker.data = {
    kills      = 0,
    deaths     = 0,
    headshots  = 0,
    shots      = 0,
    damage     = 0,
    session_start = tick(),
}

do
    -- UI
    local function MakeText(x, y, size)
        local t = Drawing.new("Text")
        t.Size     = size or 13
        t.Position = Vector2.new(x, y)
        t.Outline  = true
        t.Color    = Color3.fromRGB(255,255,255)
        t.Visible  = true
        t.Font     = Drawing.Fonts.Plex
        return t
    end

    local bg = Drawing.new("Square")
    bg.Color        = Color3.fromRGB(0,0,0)
    bg.Transparency = 0.5
    bg.Filled       = true
    bg.Position     = Vector2.new(20, 420)
    bg.Size         = Vector2.new(180, 100)
    bg.Visible      = true

    local tKD   = MakeText(28, 428, 12)
    local tHS   = MakeText(28, 444, 12)
    local tDMG  = MakeText(28, 460, 12)
    local tTime = MakeText(28, 476, 12)

    -- hook leaderboard stat changes
    local function WatchLeaderboard()
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        if not ls then return end
        local kills  = ls:FindFirstChild("Kills")  or ls:FindFirstChild("KOs")
        local deaths = ls:FindFirstChild("Deaths") or ls:FindFirstChild("Wipeouts")
        if kills then
            kills.Changed:Connect(function(v)
                StatsTracker.data.kills = v
            end)
        end
        if deaths then
            deaths.Changed:Connect(function(v)
                StatsTracker.data.deaths = v
            end)
        end
    end

    task.spawn(function()
        task.wait(2)
        WatchLeaderboard()
        LocalPlayer.ChildAdded:Connect(function(c)
            if c.Name == "leaderstats" then
                task.wait(0.5)
                WatchLeaderboard()
            end
        end)
    end)

    RunService.RenderStepped:Connect(function()
        local d   = StatsTracker.data
        local kd  = d.deaths > 0 and string.format("%.2f", d.kills/d.deaths) or tostring(d.kills)
        local hsp = d.shots > 0 and string.format("%.0f%%", (d.headshots/d.shots)*100) or "0%"
        local elapsed = tick() - d.session_start
        local mins = math.floor(elapsed/60)
        local secs = math.floor(elapsed%60)

        tKD.Text   = string.format("K/D: %d/%d (%s)", d.kills, d.deaths, kd)
        tHS.Text   = string.format("HS: %s (%d shots)", hsp, d.shots)
        tDMG.Text  = string.format("DMG: %d", d.damage)
        tTime.Text = string.format("Session: %02d:%02d", mins, secs)
    end)
end

-- ═══════════════════════════════════════
-- MODULE 6: DYNAMIC CHAMS (ดูทะลุกำแพงแบบ gradient + pulse)
-- ═══════════════════════════════════════
local DynamicChams = {}
DynamicChams.CFG = {
    ENABLED       = true,
    PULSE_SPEED   = 2.0,   -- Hz
    ENEMY_HUE     = 0,     -- red
    FRIENDLY_HUE  = 200,   -- blue
}

do
    local chamInstances = {}  -- [player] = {SelectionBox, ...}

    local function HSVtoRGB(h, s, v)
        local r,g,b
        local i = math.floor(h*6)
        local f = h*6 - i
        local p = v*(1-s); local q = v*(1-f*s); local t2 = v*(1-(1-f)*s)
        i = i % 6
        if i==0 then r,g,b=v,t2,p
        elseif i==1 then r,g,b=q,v,p
        elseif i==2 then r,g,b=p,v,t2
        elseif i==3 then r,g,b=p,q,v
        elseif i==4 then r,g,b=t2,p,v
        else r,g,b=v,p,q end
        return Color3.new(r,g,b)
    end

    local function ApplyDynamicChams(player)
        local char = player.Character
        if not char then return end

        -- cleanup เก่า
        if chamInstances[player] then
            for _, v in ipairs(chamInstances[player]) do pcall(function() v:Destroy() end) end
        end
        chamInstances[player] = {}

        local hue    = IsEnemy(player) and (DynamicChams.CFG.ENEMY_HUE/360)
                                        or (DynamicChams.CFG.FRIENDLY_HUE/360)
        local box    = Instance.new("SelectionBox", char)
        box.Adornee  = char
        box.LineThickness    = 0.05
        box.SurfaceTransparency = 0.55
        box.SurfaceColor3    = HSVtoRGB(hue, 0.9, 0.9)
        box.Color3           = HSVtoRGB(hue, 0.9, 0.9)
        table.insert(chamInstances[player], box)

        -- pulse loop
        task.spawn(function()
            while char and char.Parent and DynamicChams.CFG.ENABLED do
                local t     = tick() * DynamicChams.CFG.PULSE_SPEED
                local pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2)
                local color = HSVtoRGB(hue, 0.7 + 0.3*pulse, 0.8 + 0.2*pulse)
                pcall(function()
                    box.SurfaceColor3 = color
                    box.Color3        = color
                    box.SurfaceTransparency = 0.4 + 0.3 * (1-pulse)
                end)
                task.wait(0.03)
            end
        end)
    end

    local function WatchPlayer(p)
        if p == LocalPlayer then return end
        if p.Character then ApplyDynamicChams(p) end
        p.CharacterAdded:Connect(function()
            task.wait(0.5)
            ApplyDynamicChams(p)
        end)
    end

    for _, p in ipairs(Players:GetPlayers()) do WatchPlayer(p) end
    Players.PlayerAdded:Connect(WatchPlayer)
    Players.PlayerRemoving:Connect(function(p)
        if chamInstances[p] then
            for _, v in ipairs(chamInstances[p]) do pcall(function() v:Destroy() end) end
            chamInstances[p] = nil
        end
    end)
end

print("[pf_modules] 6 modules loaded")