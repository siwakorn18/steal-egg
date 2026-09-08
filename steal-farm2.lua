--[[
  steal-farm2.lua — เขียนใหม่สะอาด (2026-09-08) รองรับกติกาใหม่: ระบบยาม GuardPatrol
  หลักการที่ยืนยันแล้ว:
   • ถือไข่ผ่านได้เมื่อ Speed stat >= เกณฑ์โซน (server "ทำนาย" หนียาม ไม่ดูตำแหน่งจริง) -> กรองไข่ตามโซนที่ Speed ถึง
   • มือเปล่าบินไว 700 ได้ (ยามไม่ยิง) · ตอนถือไข่ใช้ F.carrySpeed (ปรับหลังเทสไอดีหลัก)
   • เข้าโซน gameplay ต้อง "เดินจริง" (Humanoid) ข้ามเส้น — teleport โดน ZoneProbe
   • ลู่วิ่งต้องมี Humanoid ยืนแตะเบลท์ (grounded) + AskWearStill
   • วางไข่ต้อง teleport เข้าคอกก่อน PlantEgg
  ควบคุม: FARM(false) หยุด · getgenv().__f2 = config
]]
if game.PlaceId ~= 107778070777162 then return warn("[f2] ผิดแมพ") end
local Players = game:GetService("Players"); local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService"); local Workspace = game:GetService("Workspace")
local function safe(fn) local ok, r = pcall(fn); if ok then return r end end
if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
local lp = Players.LocalPlayer; while not lp do task.wait(0.2); lp = Players.LocalPlayer end
pcall(function() if not lp.Character then lp.CharacterAdded:Wait() end end)
local Remotes, EggState, AssetEarnings, EggRecords
do local t0 = tick(); repeat
    Remotes = safe(function() return require(RS.Shared.Remotes) end)
    EggState = safe(function() return require(RS.Client.EggState) end)
    AssetEarnings = safe(function() return require(RS.Shared.Util.AssetEarnings) end)
    EggRecords = safe(function() return require(RS.Shared.Util.EggRecords) end)
    if not (Remotes and EggState) then task.wait(1) end
until (Remotes and EggState) or tick() - t0 > 45 end
if not (Remotes and EggState) then return warn("[f2] โหลด module ไม่ได้ เข้าเกมให้ครบก่อน") end
local AEC = safe(function() return require(RS.Shared.Util.AreaEggCycle) end)
local GAG = safe(function() return require(RS.Shared.Util.GuardAreaGeometry) end)
local EscReq = safe(function() return require(RS.Shared.Modules.GuardAreas.GuardEscapeRequirement) end)
local Treadmills = safe(function() return require(RS.Data.Treadmills) end)
local Save = safe(function() return require(RS.Shared.Save) end)

--=========================== config ===========================
local F = getgenv().__f2 or {}; getgenv().__f2 = F
F.on = false
F.flySpeed    = F.flySpeed    or 700     -- บินมือเปล่า
F.carrySpeed  = F.carrySpeed  or 700     -- * บินตอนถือไข่ (ปรับหลังเทสไอดีหลัก; ถ้าโดนยกเลิกลองลด)
F.speedMargin = F.speedMargin or 1.15    -- Speed เราต้อง >= เกณฑ์โซน x margin ถึงจะเก็บโซนนั้น
F.minRate     = F.minRate     or 0       -- เงิน/วิ ขั้นต่ำของไข่ (0=ทุกใบที่โซนถึง)
F.order       = F.order       or "value" -- value=แพงสุด / near=ใกล้สุด
F.maxDist     = F.maxDist     or 4500
F.lift        = F.lift        or 5
F.safe        = F.safe        or Vector3.new(545, 71, -360)
F.useTreadmill = (F.useTreadmill ~= false)
F.autoUpgrade  = (F.autoUpgrade ~= false)
F.baseMax     = F.baseMax     or 11
F.dayDelay    = F.dayDelay    or 3
F.lowGfx      = (F.lowGfx ~= false)
F.skip = F.skip or {}; F.status = "พร้อม"
F.gen = (F.gen or 0) + 1; local myGen = F.gen
F.iconUrl = F.iconUrl or "https://raw.githubusercontent.com/siwakorn18/steal-egg/main/steal-icon.png"

--=========================== helpers ===========================
local function hrp() local c = lp.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function humanoid() local c = lp.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function compact(n) n = tonumber(n) or 0
    if n >= 1e12 then return ("%.2fT"):format(n / 1e12) elseif n >= 1e9 then return ("%.2fB"):format(n / 1e9)
    elseif n >= 1e6 then return ("%.1fM"):format(n / 1e6) elseif n >= 1e3 then return ("%.1fK"):format(n / 1e3)
    else return ("%.0f"):format(n) end
end
local function isNight() if not AEC then return false end; local now = safe(function() return Workspace:GetServerTimeNow() end) or 0; return safe(function() return AEC.IsNightPhase(now) end) == true end
local function speedStat() local ls = lp:FindFirstChild("leaderstats"); return (ls and ls:FindFirstChild("Speed") and ls.Speed.Value) or 0 end
local line = safe(function() return Workspace.__OBJECTS.Areas.SeparationLine end)
local function pastLine(pos) if not (GAG and line) then return true end; return safe(function() return GAG.IsPastLine(line, pos) end) == true end
local function alive() return F.on and F.gen == myGen end

--=========================== Humanoid ถอด/คืน ===========================
local function removeHumanoid()
    local h = humanoid()
    if h and h.Parent then F.hum = h; F.humParent = h.Parent; pcall(function() Workspace.CurrentCamera.CameraSubject = hrp() end); h.Parent = nil end
end
local function restoreHumanoid()
    if humanoid() then return humanoid() end
    if F.hum then pcall(function() F.hum.Parent = F.humParent or lp.Character end) end
    return humanoid()
end

--=========================== anti-AFK ===========================
if not getgenv().__antiAfk2 then
    getgenv().__antiAfk2 = true
    local move = mousemoverel or (Input and Input.mousemove)
    if move then
        task.spawn(function() while getgenv().__antiAfk2 do task.wait(110); pcall(move, 2, 0); task.wait(0.15); pcall(move, -2, 0) end end)
    else
        local VU = safe(function() return game:GetService("VirtualUser") end)
        if VU then pcall(function() lp.Idled:Connect(function() pcall(function() VU:CaptureController(); VU:ClickButton2(Vector2.new()) end) end) end) end
    end
end

--=========================== driver บิน (ถอด Humanoid, CFrame, vel=0) ===========================
F.target = nil; F.arrived = false; F.moveSpeed = F.flySpeed
if F.conn then pcall(function() F.conn:Disconnect() end) end
F.conn = RunService.Heartbeat:Connect(function(dt)
    if not alive() or F.manual then return end   -- manual = โหมดเดิน/ลู่ (ไม่ยุ่ง Humanoid)
    pcall(function()
        if humanoid() then removeHumanoid() end
        local root = hrp(); if not root then return end
        if F.target then
            local cur = root.Position
            if (flat(cur) - flat(F.target)).Magnitude <= (F.radius or 6) then
                F.arrived = true; F.target = nil
            else
                local full = F.target - cur
                local goal = cur + full.Unit * math.min((F.moveSpeed or 700) * dt, full.Magnitude)
                local look = flat(full); look = look.Magnitude > 0 and look.Unit or Vector3.new(0, 0, -1)
                root.CFrame = CFrame.lookAt(goal, goal + look)
            end
        end
        root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
    end)
end)
local function goTo(pos, radius, speed)
    pos = pos + Vector3.new(0, F.lift, 0); F.radius = radius or 6; F.arrived = false; F.moveSpeed = speed or F.flySpeed; F.target = pos
    local t0, lastP, lastMove = tick(), nil, tick()
    while alive() and F.target and tick() - t0 < 25 do
        local r = hrp()
        if r then if lastP and (r.Position - lastP).Magnitude > 2 then lastMove = tick() end; lastP = r.Position; if tick() - lastMove > 3 then break end end
        RunService.Heartbeat:Wait()
    end
    F.target = nil; return F.arrived
end
local function flyVia(dest, radius, label, speed) F.status = label or "→"; goTo(F.safe, 10, speed); return goTo(dest, radius, speed) end

--=========================== เดินจริง (Humanoid) — เข้าโซน gate ===========================
local function walkTo(dest, maxT)
    local h = restoreHumanoid(); local r = hrp(); if not (h and r) then return false end
    local t = tick()
    while alive() and (r.Position - dest).Magnitude > 5 and tick() - t < (maxT or 30) do h:MoveTo(dest); RunService.Heartbeat:Wait() end
    return (r.Position - dest).Magnitude <= 6
end
local function enterZoneByWalking()
    if not (GAG and line) then return true end
    F.manual = true; F.status = "🚶 เดินเข้าโซน (gate)"
    local n = line.CFrame.LookVector; local c = line.Position
    local pastDir = (safe(function() return GAG.IsPastLine(line, c + n * 18) end) == true) and n or -n
    local safePt = Vector3.new((c - pastDir * 30).X, 71, c.Z); local inPt = Vector3.new((c + pastDir * 30).X, 71, c.Z)
    walkTo(safePt, 25); task.wait(0.4); walkTo(inPt, 25); task.wait(0.8)
    local r = hrp(); local ok = pastLine(r and r.Position or safePt)
    F.manual = false; F.gateOpen = ok; return ok
end

--=========================== โซน/ยาม: Speed ที่ต้องมีต่อโซน ===========================
F.areaReq = F.areaReq or {}
-- ★ เกณฑ์ Speed stat ต่อโซน = อ่านจาก "ตัวเลขบนป้าย RequiredSpeedSign" (สเกลเดียวกับ leaderstats.Speed)
local FALLBACK_REQ = { Forest = 11, Lake = 900, Desert = 10e3, Jungle = 40e3, Snow = 170e3, Volcano = 700e3,
    ["Abyss Ocean"] = 2.5e6, Prehistoric = 18e6, Cosmic = 700e6, ["Cherry Blossom"] = 2.5e9, ["Titan Temple"] = 7e9 }
local function parseSpeedText(txt)
    if type(txt) ~= "string" then return nil end
    local num, suf = txt:match("([%d%.]+)%s*([KkMmBbTt]?)")
    num = tonumber(num); if not num then return nil end
    local mult = ({ k = 1e3, m = 1e6, b = 1e9, t = 1e12 })[(suf or ""):lower()] or 1
    return num * mult
end
local function computeAreaRequirements()
    for k, v in pairs(FALLBACK_REQ) do F.areaReq[k] = F.areaReq[k] or v end
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "RequiredSpeedSign" and d:IsA("Model") then
            local a = d.Parent
            while a and a ~= Workspace and not (a:IsA("Model") and a:FindFirstChild("Bounds")) do a = a.Parent end
            local lbl = d:FindFirstChild("Speed", true)
            local v = lbl and lbl:IsA("TextLabel") and parseSpeedText(lbl.Text)
            if a and a ~= Workspace and v then F.areaReq[a.Name] = v end
        end
    end
end
F.zoneFail = F.zoneFail or {}   -- นับ fail ติดกันต่อโซน
local function markZoneFail(z) F.zoneFail[z] = (F.zoneFail[z] or 0) + 1; if F.zoneFail[z] == (F.zoneFailMax or 3) then print("[f2] 🚫 ตัดโซน " .. tostring(z) .. " (ยามจับ/ไข่หาย " .. F.zoneFail[z] .. " ครั้งติด — ยามเร็วเกินหนีไม่พ้น)") end end
local function markZoneOK(z) F.zoneFail[z] = 0 end   -- สำเร็จ = รีเซ็ตตัวนับ
local function areaAllowed(areaId)
    if (F.zoneFail[areaId] or 0) >= (F.zoneFailMax or 3) then return false end   -- โซนที่หนียามไม่พ้นซ้ำ = ตัด
    local req = F.areaReq[areaId]; if not req then return true end
    return speedStat() >= req * (F.speedMargin or 1)
end

--=========================== ไข่ ===========================
local function fieldEggs() local s = safe(function() return Remotes.EggWorld.AskFieldEggSnapshot:InvokeServer() end); return type(s) == "table" and (s.Records or s) or {} end
local function eggPos(rec) if typeof(rec.BottomCFrame) == "CFrame" then return rec.BottomCFrame.Position end; if typeof(rec.BoundsCFrame) == "CFrame" then return rec.BoundsCFrame.Position end end
local function eggRate(rec)
    if not AssetEarnings then return 0 end
    local w = safe(function() return EggRecords.WeightKg(rec) end) or safe(function() return EggRecords.WeightKgForScale(rec.AssetScale) end)
    local r = safe(function() return AssetEarnings.RatePerSecond({ Category = rec.AssetCategory, AssetCategory = rec.AssetCategory, WeightKg = w, Weight = w, Mutations = rec.Mutations, Scale = rec.AssetScale, AssetScale = rec.AssetScale }) end)
    return type(r) == "number" and r or 0
end
local function pickEgg()
    local ref = F.safe; local now = tick(); local best, bp, br, bs
    for _, rec in pairs(fieldEggs()) do
        if type(rec) == "table" and rec.Uid and tostring(rec.State or "") == "Slot" and not (F.skip[rec.Uid] and F.skip[rec.Uid] > now) then
            local p = eggPos(rec)
            if p and pastLine(p) and areaAllowed(rec.AreaId) and (flat(ref) - flat(p)).Magnitude <= F.maxDist then
                local rate = eggRate(rec)
                if rate >= F.minRate then
                    local score = (F.order == "near") and -(flat(ref) - flat(p)).Magnitude or rate
                    if not bs or score > bs then best, bp, br, bs = rec, p, rate, score end
                end
            end
        end
    end
    return best, bp, br
end
-- ฟังสถานะถือไข่จาก server (ยกเลิก = IsCarrying=false)
F.carrying = nil
if F.carryConn then pcall(function() F.carryConn:Disconnect() end) end
F.carryConn = safe(function()
    return RS.Packages.Networking["RE/EggWorld/FieldEggCarry"].OnClientEvent:Connect(function(t)
        if type(t) == "table" and t.IsCarrying ~= nil then F.carrying = t.IsCarrying end
    end)
end)
local function grabEgg(rec, pos)
    local sk = (rec.AreaId and rec.NestId) and (rec.AreaId .. ":" .. rec.NestId) or rec.NestId
    F.target = nil; local tgt = Vector3.new(pos.X, pos.Y + 1, pos.Z); local reason
    for _ = 1, 8 do
        local t0 = tick()
        while tick() - t0 < 0.3 do local r = hrp(); if r then r.CFrame = CFrame.new(tgt); r.AssemblyLinearVelocity = Vector3.zero end; RunService.Heartbeat:Wait() end
        F.carrying = nil
        local ok, s, r2 = pcall(function() return EggState.CarryFieldEgg(rec.Uid, sk) end)
        if ok and s == true then return true end
        reason = r2
        if r2 and tostring(r2):find("gameplay area") then return false, "gate" end
        if r2 and tostring(r2):find("Already carrying") then return true end
        task.wait(0.05)
    end
    return false, reason
end
local function unplacedUids()
    local list, seen = {}, {}
    for _, src in ipairs({ lp.Character, lp:FindFirstChild("Backpack") }) do
        if src then for _, t in ipairs(src:GetChildren()) do
            if t:IsA("Tool") then
                local uid = t:GetAttribute("UID")
                if uid and not seen[uid] and (t:GetAttribute("ItemType") == "AssetEgg" or t.Name:find("Egg")) then seen[uid] = true; list[#list + 1] = uid end
            end
        end end
    end
    return list
end
local function placeCF(x, z) return CFrame.new(x, -0.5, z, 0, 0, 1, 0, 1, 0, -1, 0, 0) end
local function placeAllEggs()
    local r = hrp(); if r and F.home then r.CFrame = CFrame.new(F.home + Vector3.new(0, 5, 0)); r.AssemblyLinearVelocity = Vector3.zero end
    task.wait(1)
    local uids = unplacedUids(); local placed, fails, last = 0, 0, nil
    local function penCount() local k=0; local o=safe(function() return EggState.ReadOwnedEggs() end); if type(o)=="table" then for _,g in pairs(o) do if type(g)=="table" and type(g.Records)=="table" then for _,rc in pairs(g.Records) do if type(rc)=="table" and rc.Placement~=nil then k=k+1 end end end end end return k end
    for _, uid in ipairs(uids) do
        if not alive() then break end
        pcall(function() EggState.WearEggTool(uid) end); task.wait(0.1)
        local ok = false
        for _ = 1, 10 do
            local o, s, rs = pcall(function() return EggState.PlantEgg(uid, placeCF(math.random(-150, 130) / 10, math.random(-60, 210) / 10)) end)
            if o and s == true then ok = true; break end
            last = rs; task.wait(0.08)
        end
        if ok then placed = placed + 1; fails = 0 else fails = fails + 1; if fails >= 3 then break end end
    end
    print(("[f2] วางลงคอก %d/%d%s | คอก=%d"):format(placed, #uids, (placed < #uids and last) and (" | " .. tostring(last)) or "", penCount()))
    return placed, #uids
end

--=========================== บ้าน ===========================
local function findHome()
    for _ = 1, 10 do
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            for _, p in ipairs(plots:GetChildren()) do
                local mine = (p:GetAttribute("OwnerUserId") == lp.UserId)
                if not mine then
                    for _, d in ipairs(p:GetDescendants()) do
                        if (d:IsA("TextLabel") and d.Text == lp.Name) or d:GetAttribute("OwnerUserId") == lp.UserId then mine = true; break end
                    end
                end
                if mine then local pen = p:FindFirstChild("StarterPen", true); if pen then return pen:GetPivot().Position, p end end
            end
        end
        task.wait(1)
    end
end

--=========================== money engine ===========================
local function hatchReady()
    local n = 0; local owned = safe(function() return EggState.ReadOwnedEggs() end)
    if type(owned) == "table" then
        for _, g in pairs(owned) do
            if type(g) == "table" and type(g.Records) == "table" then
                for uid, rec in pairs(g.Records) do
                    if type(rec) == "table" and rec.Placement ~= nil and safe(function() return EggState.IsReadyToHatch(uid) end) == true then
                        pcall(function() EggState.BeginHatch(uid) end); pcall(function() EggState.FinishHatch(uid) end); n = n + 1
                    end
                end
            end
        end
    end
    return n
end
local function equipBestAndSell()
    pcall(function() Remotes.Haul.WearBest:InvokeServer() end); task.wait(0.3)
    pcall(function() Remotes.PetSatchel.SellEveryPet:FireServer() end); pcall(function() Remotes.PenRoster.AskSale:InvokeServer() end)
end
local function upgradeBase()
    local lvl = F.plot and safe(function() return F.plot:GetAttribute("BaseUpgradeLevel") end)
    if lvl and lvl >= F.baseMax then return end
    pcall(function() Remotes.Homestead.AskBaseTierRaise:FireServer() end)
end
local function upgradeTreadmill()
    if not (Treadmills and Treadmills.GetByUpgradeLevel and Save) then return end
    local sv = safe(function() return Save.Get() end); if not sv then return end
    local cfg = safe(function() return Treadmills.GetByUpgradeLevel((sv.TreadmillUpgradeLevel or 0) + 1) end); if not cfg then return end
    if (sv.Money or 0) < (cfg.Price or math.huge) then return end
    local ok, r1 = pcall(function() return Remotes.Treadmill.AskTierRaise:InvokeServer(cfg._id) end)
    if ok and r1 == true then print("[f2] ⬆ อัพลู่ -> " .. tostring(cfg._id)) end
end
local function maintain()
    local h = hatchReady()
    if h > 0 then F.status = ("🐣 ฟัก %d -> equip+ขาย"):format(h); F.penFull = false; equipBestAndSell() end
    if F.autoUpgrade and tick() - (F.lastUp or 0) > 4 then
        F.lastUp = tick(); F.upTurn = (F.upTurn or 0) + 1
        if F.upTurn % 2 == 1 then upgradeBase() else upgradeTreadmill() end
    end
end

--=========================== ลู่วิ่ง (grounded + AskWearStill) ===========================
local TREAD_OFFSETS = {}
do
    local seen = {}
    local function add(x, y, z) local k = x .. "," .. y .. "," .. z; if not seen[k] then seen[k] = true; TREAD_OFFSETS[#TREAD_OFFSETS + 1] = Vector3.new(x, y, z) end end
    add(-3, 3, -9); add(0, 3, -5); add(0, 3, -9); add(3, 3, -9)
    for _, dz in ipairs({ 0, 3, -3, 6, -6, 9, -9 }) do for _, dx in ipairs({ 0, 3, -3, 6, -6, 9, -9 }) do add(dx, 3, dz) end end
end
local function tryMount(spot)
    local r = hrp(); if not r then return false end
    r.CFrame = CFrame.new(spot); r.AssemblyLinearVelocity = Vector3.zero; task.wait(0.45)
    local ok, r1, r2 = pcall(function() return Remotes.Treadmill.AskWearStill:InvokeServer() end)
    return ok and (r1 == true or (r2 ~= nil and tostring(r2):find("Already") ~= nil))
end
local function idleTreadmill(reason)
    local tb = F.plot and F.plot:FindFirstChild("TreadmillBottom", true)
    if not tb then F.status = "ไม่เจอลู่ รอ"; task.wait(3); return end
    flyVia(tb.Position + Vector3.new(0, 5, 0), 6, "→ ลู่วิ่ง")
    F.manual = true; restoreHumanoid(); task.wait(0.2)
    pcall(function() Remotes.Treadmill.AskDoff:InvokeServer() end); task.wait(0.3)
    local base = tb.Position; local spot
    for _ = 1, 2 do
        if not alive() then break end
        if F.treadOffset and tryMount(base + F.treadOffset) then spot = base + F.treadOffset; break end
        for _, o in ipairs(TREAD_OFFSETS) do if not alive() then break end; if tryMount(base + o) then spot = base + o; F.treadOffset = o; break end end
        if spot then break end
        task.wait(0.4)
    end
    if not spot then F.status = "⚠ ขึ้นลู่ไม่ได้ รอ"; print("[f2] " .. F.status); F.manual = false; task.wait(6); return end
    F.status = "🏃 วิ่งบนลู่ (" .. tostring(reason) .. ")"; print("[f2] " .. F.status)
    local sp0, t0, lastMount = speedStat(), tick(), tick()
    while alive() do
        local r = hrp()
        if r and (r.Position - spot).Magnitude > 8 then r.CFrame = CFrame.new(spot); r.AssemblyLinearVelocity = Vector3.zero end
        task.wait(1); pcall(maintain)
        if not isNight() then local rec = pickEgg(); if rec and not F.penFull then break end end
        if tick() - lastMount > 8 then lastMount = tick(); pcall(function() Remotes.Treadmill.AskWearStill:InvokeServer() end) end
        if tick() - t0 > 20 then t0 = tick(); local sp = speedStat(); print(("[f2] 🏃 Speed %s -> %s"):format(compact(sp0), compact(sp))); sp0 = sp end
    end
    F.status = "ลงจากลู่"; pcall(function() Remotes.Treadmill.AskDoff:InvokeServer() end); task.wait(0.3)
    F.manual = false
end

--=========================== ลด lag (ไม่ลบไข่สนาม/ลู่) ===========================
local function lowGfx()
    if not F.lowGfx or F.gfxDone then return end
    F.gfxDone = true
    for _, name in ipairs({ "ClientRenderedAssets", "MonsterParasiteMonsters", "PlacedEggRenders" }) do
        local f = Workspace:FindFirstChild(name)
        if f then
            for _, ch in ipairs(f:GetChildren()) do pcall(function() ch:Destroy() end) end
            f.ChildAdded:Connect(function(ch) task.defer(function() pcall(function() ch:Destroy() end) end) end)
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do if plr ~= lp and plr.Character then pcall(function() plr.Character:Destroy() end) end end
    pcall(function() game:GetService("Lighting").GlobalShadows = false end)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
end

--=========================== loop หลัก ===========================
local function loop()
    while alive() do
        pcall(maintain)
        if isNight() then
            F.status = "🌙 กลางคืน"; F.wasNight = true
            if F.useTreadmill then idleTreadmill("กลางคืน") else goTo(F.safe, 10); task.wait(3) end
        else
            if F.wasNight then F.wasNight = false; F.status = "🌅 รอเริ่มวัน"; goTo(F.safe, 10); task.wait(F.dayDelay) end
            if not F.gateOpen then enterZoneByWalking() end
            local rec, pos, rate = pickEgg()
            if not rec then
                F.status = "ไม่มีไข่ที่โซนถึง/เกณฑ์"
                if F.useTreadmill then idleTreadmill("ไม่มีไข่") else task.wait(3) end
            else
                F.status = ("ขโมย %s [%s] %s/วิ"):format(tostring(rec.AssetCategory), tostring(rec.AreaId), compact(rate))
                local reached = flyVia(Vector3.new(pos.X, pos.Y + 3, pos.Z), 4, "→ ไข่", F.flySpeed)
                local grabbed, why = false, nil
                if reached then grabbed, why = grabEgg(rec, pos) end
                if why == "gate" then
                    F.gateOpen = false; F.skip[rec.Uid] = tick() + 3
                elseif grabbed then
                    -- * ถือไข่กลับ: ใช้ carrySpeed; ถ้า server ยกเลิก (IsCarrying=false) หยุดแล้วข้าม
                    F.status = "🥚 ถือกลับบ้าน"; local cancelled = false
                    F.moveSpeed = F.carrySpeed; F.radius = 8; F.arrived = false; F.target = F.home + Vector3.new(0, F.lift, 0)
                    local t0 = tick()
                    while alive() and F.target and tick() - t0 < 40 do
                        if F.carrying == false then cancelled = true; F.target = nil; break end
                        RunService.Heartbeat:Wait()
                    end
                    F.target = nil
                    if cancelled then
                        F.status = "❌ ยามยกเลิก (หนีไม่พ้น)"; print("[f2] " .. F.status .. " " .. tostring(rec.AreaId)); F.skip[rec.Uid] = tick() + 30; markZoneFail(rec.AreaId)
                    else
                        local n, total = placeAllEggs(); F.status = ("✅ วาง %d/%d [%s]"):format(n, total, tostring(rec.AreaId))
                        if total == 0 then markZoneFail(rec.AreaId); print("[f2] ⚠ ไข่หายก่อนวาง โซน " .. tostring(rec.AreaId)) elseif n > 0 then markZoneOK(rec.AreaId) end
                        if total > 0 and n == 0 then F.penFull = true end
                    end
                else
                    F.status = "เก็บไม่ได้ ข้าม (" .. tostring(why) .. ")"; F.skip[rec.Uid] = tick() + 5
                end
                task.wait(0.1)
            end
        end
    end
    F.status = "หยุดแล้ว"
end

--=========================== ดักข้อความ "Delivery failed" (วินิจฉัย) ===========================
if not F.dlvHook then F.dlvHook = true
    task.spawn(function()
        local pg = lp:FindFirstChildOfClass("PlayerGui"); if not pg then return end
        local function watch(lbl)
            if not (lbl:IsA("TextLabel") or lbl:IsA("TextButton")) then return end
            lbl:GetPropertyChangedSignal("Text"):Connect(function()
                local t = lbl.Text
                if type(t) == "string" and (t:find("Delivery") or t:find("returned to")) then
                    print("[f2] 📩 GUI: " .. t .. " | ตอนนั้นสถานะ=" .. tostring(F.status))
                end
            end)
        end
        for _, d in ipairs(pg:GetDescendants()) do watch(d) end
        pg.DescendantAdded:Connect(watch)
    end)
end

--=========================== control ===========================
getgenv().FARM = function(on)
    F.on = (on ~= false)
    if not F.on then F.target = nil; F.manual = false; restoreHumanoid(); print("[f2] ปิด"); return end
    pcall(lowGfx); pcall(computeAreaRequirements)
    local hp, plot = findHome()
    if not hp then F.on = false; return warn("[f2] หาบ้านไม่เจอ") end
    F.home = hp; F.plot = plot
    local allowed = {}
    for a, _ in pairs(F.areaReq) do if areaAllowed(a) then allowed[#allowed + 1] = a end end
    print(("[f2] ✅ บ้าน %s | Speed %s | โซนที่ถือได้: %s"):format(plot.Name, compact(speedStat()), table.concat(allowed, ", ")))
    task.spawn(function() local last; while alive() do if F.status ~= last then last = F.status; print("[f2] " .. tostring(F.status)) end; task.wait(0.5) end end)
    task.spawn(loop)
end

--=========================== UI ไอคอน + auto-run ===========================
do
    local parent = (gethui and gethui()) or lp:FindFirstChildOfClass("PlayerGui") or game:GetService("CoreGui")
    local old = parent:FindFirstChild("FarmUI2"); if old then old:Destroy() end
    local gui = Instance.new("ScreenGui"); gui.Name = "FarmUI2"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 999; gui.Parent = parent
    local holder = Instance.new("Frame"); holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.Position = UDim2.fromScale(0.5, 0.20); holder.Size = UDim2.fromOffset(130, 130); holder.BackgroundTransparency = 1; holder.Parent = gui
    local icon = Instance.new("ImageLabel"); icon.Size = UDim2.fromScale(1, 1); icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit
    icon.Image = (function()
        local ga = getcustomasset or getsynasset; if not ga then return "" end
        local have = isfile and safe(function() return isfile("steal-icon.png") end)
        if not have and writefile and F.iconUrl then pcall(function() writefile("steal-icon.png", game:HttpGet(F.iconUrl)) end) end
        return safe(function() return ga("steal-icon.png") end) or ""
    end)()
    icon.Parent = holder
    local stx = Instance.new("TextLabel"); stx.AnchorPoint = Vector2.new(0.5, 0); stx.Position = UDim2.new(0.5, 0, 1, 6); stx.Size = UDim2.fromOffset(320, 18)
    stx.BackgroundTransparency = 1; stx.Font = Enum.Font.GothamBold; stx.TextSize = 12; stx.TextColor3 = Color3.new(1, 1, 1); stx.TextStrokeTransparency = 0.4; stx.Parent = holder
    task.spawn(function()
        local t = 0
        while gui.Parent do t = t + 0.05; icon.ImageTransparency = 0.08 + 0.12 * (math.sin(t * 3) * 0.5 + 0.5); holder.Visible = (F.on == true); stx.Text = tostring(F.status); task.wait(0.05) end
    end)
end
print("[f2] 🔖 steal-farm2 v2026-09-08d — auto-ตัดโซนที่ยามเร็วเกินหนีไม่พ้น (เก็บโซนที่วางได้จริง)")
task.spawn(function() pcall(function() getgenv().FARM(true) end) end)
