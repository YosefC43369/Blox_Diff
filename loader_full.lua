local MODULES = {
    ["pf_cheat"]       = "https://raw.githubusercontent.com/YosefC43369/Blox_Diff/main/pf_cheat.lua",
    ["pf_advanced"]    = "https://raw.githubusercontent.com/YosefC43369/Blox_Diff/main/pf_advanced.lua",
    ["pf_modules"]     = "https://raw.githubusercontent.com/YosefC43369/Blox_Diff/main/pf_modules.lua",
    ["pf_orchestrator"]= "https://raw.githubusercontent.com/YosefC43369/Blox_Diff/main/pf_orchestrator.lua",
}

local ORDER = {"pf_cheat", "pf_advanced", "pf_modules", "pf_orchestrator"}

local function Fetch(url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if ok and res and #res > 10 then return res end
    if syn and syn.request then
        local r = syn.request({Url=url, Method="GET"})
        if r and r.StatusCode == 200 then return r.Body end
    end
    return nil
end

for _, name in ipairs(ORDER) do
    local url = MODULES[name]
    local src = Fetch(url)
    if src then
        local fn, err = loadstring(src)
        if fn then
            task.spawn(fn)
            print("[loader] loaded: " .. name)
        else
            warn("[loader] parse error in " .. name .. ": " .. tostring(err))
        end
    else
        warn("[loader] fetch failed: " .. name)
    end
    task.wait(0.4)
end

print("[loader_full] all modules online")