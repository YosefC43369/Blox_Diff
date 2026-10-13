-- lang: Lua, file: loader.lua, target: Windows 11, executor: KRNL / Synapse X
-- *loader หลัก — paste อันนี้อันเดียว ดึง script ทั้งสองจาก raw URL*
-- *แก้ URL ให้ชี้ไป pastebin/github raw ของตัวเองก่อน deploy*

local SCRIPTS = {
    "https://raw.githubusercontent.com/YosefC43369/Blox_Diff/main/pf_cheat.lua",
    "https://raw.githubusercontent.com/YosefC43369/Blox_Diff/main/pf_advanced.lua",
}

local function Fetch(url)
    local ok, result = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok and result and #result > 10 then
        return result
    end
    -- fallback: syn_request สำหรับ Synapse
    if syn and syn.request then
        local r = syn.request({Url=url, Method="GET"})
        if r and r.StatusCode == 200 then return r.Body end
    end
    return nil
end

local function ExecScript(url)
    local src = Fetch(url)
    if not src then
        warn("[loader] failed: " .. url)
        return
    end
    local fn, err = loadstring(src)
    if not fn then
        warn("[loader] parse error: " .. tostring(err))
        return
    end
    task.spawn(fn)
end

-- โหลดตามลำดับ — cheat ก่อน, advanced module หลัง
for _, url in ipairs(SCRIPTS) do
    ExecScript(url)
    task.wait(0.3)
end

print("[loader] all modules loaded")