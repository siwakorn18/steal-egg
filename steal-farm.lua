--[[
    steal-farm.lua — auto บินขโมยไข่ -> วางที่บ้าน (เขียนใหม่สะอาด)
    ยืนยันแล้ว: ถอด Humanoid + CFrame + vel=0 = บินไม่เด้ง / WearEggTool+PlantEgg = วางได้

    กดเปิด UI ได้เลย (หาบ้านเอง + เซฟโซน default)
    ปรับ: getgenv().__farm.speed / .minRate / .order  |  SETHOME() / SETSAFE()  |  หยุด: FARM(false)
]]

if game.PlaceId ~= 107778070777162 then return warn("[farm] ผิดแมพ") end

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")
local lp          = Players.LocalPlayer
local function safe(fn) local ok, r = pcall(fn); if ok then return r end end

-- ★ รอเกมโหลดครบก่อน (กันรันเร็วไปตอนเพิ่งเข้าเกม -> module ยังไม่มา -> require คืน nil)
if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
pcall(function() if not lp.Character then lp.CharacterAdded:Wait() end end)
local Remotes, EggState, AssetEarnings, EggRecords
do
    local t0 = tick()
    repeat
        Remotes       = safe(function() return require(RS.Shared.Remotes) end)
        EggState      = safe(function() return require(RS.Client.EggState) end)
        AssetEarnings = safe(function() return require(RS.Shared.Util.AssetEarnings) end)
        EggRecords    = safe(function() return require(RS.Shared.Util.EggRecords) end)
        if not (Remotes and EggState) then task.wait(1) end
    until (Remotes and EggState) or tick() - t0 > 45   -- retry ได้ถึง 45 วิ
end
if not Remotes or not EggState then warn("[farm] โหลด module เกมไม่ได้ — เข้าเกมให้ครบก่อนแล้วรันใหม่"); return end
-- module ตามชื่อ (สำหรับอัพเกรดบ้าน)
local function reqByName(n)
    local m = RS:FindFirstChild(n, true)
    return (m and m:IsA("ModuleScript")) and safe(function() return require(m) end) or nil
end
local BaseUpgrade = reqByName("BaseUpgrade")
local AreaEggCycle = safe(function() return require(RS.Shared.Util.AreaEggCycle) end) or (function()
    for _, m in ipairs((getloadedmodules and getloadedmodules()) or {}) do
        if typeof(m) == "Instance" and m.Name == "AreaEggCycle" then return safe(function() return require(m) end) end
    end
end)()

--=========================== config ===========================
local F = getgenv().__farm or {}
getgenv().__farm = F
F.on      = false
F.speed   = F.speed   or 700
-- ★ auto ปรับ fly speed ตาม Speed stat (ลู่วิ่ง): ≤1M = 700 / เกิน 1M = 800 (server ยอมให้ไวขึ้น)
F.autoSpeed = (F.autoSpeed ~= false)
F.speedLow  = F.speedLow  or 700
F.speedHigh = F.speedHigh or 800
F.speedStatThresh = F.speedStatThresh or 1e6
F.dayDelay = F.dayDelay or 3                                 -- ★ รอต้นวันกี่วิ (countdown ไข่พร้อม) ก่อนเริ่มวิ่งเก็บ
F.minRate = F.minRate or 10e6                                -- ใช้ตอน dynamic=false
F.dynamic  = (F.dynamic ~= false)                            -- true=สลับเฟสตาม Money/s อัตโนมัติ
F.growUntil = F.growUntil or 10e6                            -- Money/s < นี้ = เก็บทุกใบไกลสุดก่อน (ปั้น)
F.bigRate  = F.bigRate or 10e6                               -- Money/s ถึงแล้ว = เก็บเฉพาะไข่ >= นี้
F.order   = F.order   or "far"                               -- far=ไกลสุดก่อน (เทส) | value=แพงสุดก่อน (spec)
F.autoUpgrade = (F.autoUpgrade ~= false)                     -- อัพบ้าน+ลู่วิ่งอัตโนมัติ
F.safe    = F.safe    or Vector3.new(545, 71, -360)          -- เซฟโซนกลาง (default)
F.lift    = F.lift    or 5                                   -- ยกตัวลอยเหนือพื้น (กันตัวจม)
F.trapR   = F.trapR   or 9                                   -- ใกล้กับดักกว่านี้ (studs) = บินข้ามสูง
F.trapLift = F.trapLift or 12                                -- ความสูงที่บินข้ามกับดัก
F.home    = F.home                                           -- คอกบ้าน (หาเอง/SETHOME)
-- ★ URL ไอคอน (raw GitHub) — ให้เครื่องอื่นโหลดรูปเองถ้าไม่มีไฟล์ในเครื่อง | แก้ USER/REPO เป็นของคุณ
F.iconUrl = F.iconUrl or "https://raw.githubusercontent.com/siwakorn18/steal-egg/main/steal-icon.png"
F.skip    = F.skip    or {}
F.status  = "พร้อม"
F.gen     = (F.gen or 0) + 1
local myGen = F.gen

--=========================== anti-AFK (กันโดนเตะเพราะ idle 20 นาที) ===========================
if not getgenv().__antiAfk then
    getgenv().__antiAfk = true
    -- ★ วิธีปลอดภัยสุด: ขยับเมาส์ "จริง" เล็กน้อยทุก ~110 วิ (client input จริง เกม/anti-cheat ตรวจไม่ได้)
    --   ไม่รอถึง 20 นาที + ไม่ใช้ VirtualUser (ที่บางเกมตรวจจับแล้วเตะ) ถ้ามี mousemoverel
    local move = mousemoverel or (Input and Input.mousemove)
    if move then
        task.spawn(function()
            while getgenv().__antiAfk do
                task.wait(110)
                pcall(move, 2, 0); task.wait(0.15); pcall(move, -2, 0)   -- ขยับ 2px แล้วกลับ (แทบไม่เห็น)
            end
        end)
        print("[farm] ✅ anti-AFK เปิด (ขยับเมาส์จริง — ปลอดภัย)")
    else
        -- fallback: VirtualUser ตอน Idled (ถ้า executor ไม่มี mousemoverel)
        local VirtualUser = safe(function() return game:GetService("VirtualUser") end)
        if VirtualUser then
            pcall(function()
                lp.Idled:Connect(function()
                    pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0, 0)) end)
                end)
            end)
            print("[farm] ✅ anti-AFK เปิด (VirtualUser fallback)")
        end
    end
end

--=========================== auto speed ตาม Speed stat ===========================
task.spawn(function()
    local last
    while F.gen == myGen do
        if F.autoSpeed then
            local ls = lp:FindFirstChild("leaderstats")
            local sp = ls and ls:FindFirstChild("Speed") and ls.Speed.Value
            if sp then
                local want = (sp > (F.speedStatThresh or 1e6)) and (F.speedHigh or 800) or (F.speedLow or 700)
                if F.speed ~= want then
                    F.speed = want
                    if want ~= last then last = want; print(("[farm] ⚡ Speed stat %.2fM -> fly speed %d"):format(sp / 1e6, want)) end
                end
            end
        end
        task.wait(3)
    end
end)

--=========================== helpers ===========================
local function hrp() local c = lp.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function humanoid() local c = lp.Character; return c and c:FindFirstChildOfClass("Humanoid") end
-- กลางคืน = ห้ามอยู่ในโซน gameplay (ขโมยไม่ได้ โดนโยนกลับเซฟโซน)
local function isNight()
    if not AreaEggCycle then return false end
    local now = safe(function() return Workspace:GetServerTimeNow() end) or 0
    return safe(function() return AreaEggCycle.IsNightPhase(now) end) == true
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function compact(n)
    if n >= 1e12 then return ("%.2fT"):format(n / 1e12)
    elseif n >= 1e9 then return ("%.2fB"):format(n / 1e9)
    elseif n >= 1e6 then return ("%.1fM"):format(n / 1e6)
    elseif n >= 1e3 then return ("%.1fK"):format(n / 1e3)
    else return ("%.0f"):format(n) end
end

--=========================== humanoid ถอด/คืน ===========================
local function removeHumanoid()
    local c = lp.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if h and h.Parent then
        F.hum, F.humParent = h, h.Parent
        pcall(function()
            Workspace.CurrentCamera.CameraSubject = hrp()
            Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        end)
        h.Parent = nil
    end
end
local function restoreHumanoid()
    if F.hum and F.humParent then pcall(function() F.hum.Parent = F.humParent end) end
    F.hum, F.humParent = nil, nil
end

--=========================== กับดัก (PlayerTrap ใน Workspace.__DEBRIS) ===========================
F.traps = F.traps or {}
local function scanTraps()
    local list = {}
    local deb = Workspace:FindFirstChild("__DEBRIS")
    if deb then
        for _, d in ipairs(deb:GetDescendants()) do
            if d:IsA("BasePart") and (d.Name == "PlayerTrap" or d.Name == "ClosedTrap") then
                local owner = safe(function() return d:GetAttribute("Owner") end)
                if owner ~= lp.Name then table.insert(list, d.Position) end   -- ข้ามกับดักของเราเอง
            end
        end
    end
    F.traps = list
end
-- กับดักที่ใกล้จุด pos (แนวราบ) ภายใน r -> คืน (ตำแหน่งกับดัก, ระยะ)
local function nearTrap(pos, r)
    local best, bd = nil, r or F.trapR
    for _, tp in ipairs(F.traps) do
        local d = (flat(tp) - flat(pos)).Magnitude
        if d < bd then best, bd = tp, d end
    end
    return best, bd
end
task.spawn(function()
    while F.gen == myGen do
        if F.on then pcall(scanTraps) end
        task.wait(1)
    end
end)

--=========================== driver (บินต่อเนื่อง vel=0) ===========================
F.target = nil
F.arrived = false
if F.conn then pcall(function() F.conn:Disconnect() end) end
F.conn = RunService.Heartbeat:Connect(function(dt)
    if F.gen ~= myGen or not F.on then return end
    if F.onTreadmill then return end   -- ★ อยู่บนลู่วิ่ง: ปล่อยให้ Humanoid วิ่งเอง (ไม่ถอด/ไม่ขยับ/ไม่ zero vel)
    pcall(function()
        -- respawn: ถ้า Humanoid โผล่กลับมา ถอดใหม่ (กันเด้ง)
        local c = lp.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        if h and h.Parent then removeHumanoid() end

        local root = hrp(); if not root then return end
        if F.target then
            local cur = root.Position
            if (flat(cur) - flat(F.target)).Magnitude <= (F.radius or 8) then
                F.arrived = true; F.target = nil
            else
                local full = F.target - cur
                local goal = cur + full.Unit * math.min(F.speed * dt, full.Magnitude)
                -- ★ หลบกับดัก: ใกล้กับดักในระยะ trapR -> บินข้ามสูง (กับดักอยู่ที่พื้น)
                local tp = nearTrap(goal, F.trapR)
                if tp and goal.Y < tp.Y + F.trapLift then goal = Vector3.new(goal.X, tp.Y + F.trapLift, goal.Z) end
                local look = flat(full); look = look.Magnitude > 0 and look.Unit or Vector3.new(0, 0, -1)
                root.CFrame = CFrame.lookAt(goal, goal + look)
            end
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end)

-- บินไป pos (stuck 2.5วิ = เลิก, timeout 15วิ)
local function goTo(pos, radius)
    pos = pos + Vector3.new(0, F.lift or 5, 0)   -- ยกลอยเหนือพื้น กันตัวจม (เวอร์ชันที่ยืนยันว่าดี)
    F.radius = radius or 8
    F.arrived = false
    F.target = pos
    local t0, lastP, lastMove = tick(), nil, tick()
    while F.on and F.gen == myGen and F.target and tick() - t0 < 15 do
        local r = hrp()
        if r then
            if lastP and (r.Position - lastP).Magnitude > 2 then lastMove = tick() end
            lastP = r.Position
            if tick() - lastMove > 2.5 then break end
        end
        RunService.Heartbeat:Wait()
    end
    F.target = nil
    return F.arrived
end

-- แวะเซฟโซนก่อนเสมอ (กันบินทะลุกำแพง)
local function flyVia(dest, radius, label)
    if F.safe then F.status = "→ เซฟโซน"; goTo(F.safe, 10) end
    F.status = label or "→ ปลายทาง"
    return goTo(dest, radius)
end

--=========================== หาบ้าน (คอก) ===========================
local function findHome()
    for _ = 1, 10 do
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                local mine = false
                for _, d in ipairs(plot:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text == lp.Name then mine = true; break end
                    local ov = safe(function() return d:GetAttribute("OwnerUserId") end)
                    if ov ~= nil and tostring(ov) == tostring(lp.UserId) then mine = true; break end
                end
                if mine then
                    local pen = plot:FindFirstChild("StarterPen", true)
                    return (pen and safe(function() return pen:GetPivot().Position end))
                        or safe(function() return plot:GetPivot().Position end), plot
                end
            end
        end
        task.wait(0.3)
    end
end

--=========================== ไข่ ===========================
local function fieldEggs()
    local snap = safe(function() return Remotes.EggWorld.AskFieldEggSnapshot:InvokeServer() end)
    if type(snap) ~= "table" then return {} end
    return snap.Records or snap
end
local function eggPos(rec)
    if typeof(rec.BottomCFrame) == "CFrame" then return rec.BottomCFrame.Position end
    if typeof(rec.BoundsCFrame) == "CFrame" then return rec.BoundsCFrame.Position end
end
local function eggRate(rec)
    if not AssetEarnings then return 0 end
    local w = safe(function() return EggRecords.WeightKg(rec) end)
        or safe(function() return EggRecords.WeightKgForScale(rec.AssetScale) end)
    local item = { Category = rec.AssetCategory, AssetCategory = rec.AssetCategory,
        WeightKg = w, Weight = w, Mutations = rec.Mutations, Scale = rec.AssetScale, AssetScale = rec.AssetScale }
    local r = safe(function() return AssetEarnings.RatePerSecond(item) end)
    return type(r) == "number" and r or 0
end
-- เลือกไข่: วัดระยะจากเซฟโซน (คงที่), กรอง minRate, far/near, ข้าม skip
local function pickEgg()
    local ref = F.safe or (hrp() and hrp().Position); if not ref then return end
    local now = tick()
    -- ★ dynamic 2 เฟสตาม Money/s: ยังไม่ถึง growUntil = เก็บทุกใบไกลสุดก่อน / ถึงแล้ว = เฉพาะไข่ >= bigRate
    local mode, minRate = F.order, F.minRate
    if F.dynamic then
        local ls = lp:FindFirstChild("leaderstats")
        local mps = (ls and ls:FindFirstChild("Money/s") and ls["Money/s"].Value) or 0
        if mps < (F.growUntil or 10e6) then mode, minRate = "far", 0            -- เฟสปั้น
        else mode, minRate = "value", (F.bigRate or 10e6) end                  -- เฟสเลือกของแพง
        F.phase = (mps < (F.growUntil or 10e6)) and "ปั้น(ทุกใบ)" or ("เลือก≥" .. compact(F.bigRate or 10e6))
    end
    local best, bestPos, bestRate, bestScore = nil, nil, 0, nil
    for _, rec in pairs(fieldEggs()) do
        if type(rec) == "table" and rec.Uid then
            local st = tostring(rec.State or "")
            if st == "Slot" and not (F.skip[rec.Uid] and F.skip[rec.Uid] > now) then
                local rate = eggRate(rec)
                if rate >= minRate then
                    local p = eggPos(rec)
                    if p then
                        local score
                        if mode == "value" then score = rate                         -- มาก = ดี
                        elseif mode == "far" then score = (flat(ref) - flat(p)).Magnitude
                        else score = -(flat(ref) - flat(p)).Magnitude end            -- near
                        if bestScore == nil or score > bestScore then
                            best, bestPos, bestRate, bestScore = rec, p, rate, score
                        end
                    end
                end
            end
        end
    end
    return best, bestPos, bestRate
end

--=========================== ถือ / เก็บ / วาง ===========================
-- uid ไข่ที่ถือ (Tool ItemType=AssetEgg)
local function carriedEggUid()
    for _, src in ipairs({ lp.Character, lp:FindFirstChild("Backpack") }) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if t:IsA("Tool") then
                    local uid = t:GetAttribute("UID")
                    if uid and (t:GetAttribute("ItemType") == "AssetEgg" or t.Name:find("Egg")) then
                        return uid
                    end
                end
            end
        end
    end
    return nil
end

-- prompt "Steal" ใกล้ตัวสุด
local function stealPrompt()
    local r = hrp(); if not r then return end
    local best, bd = nil, math.huge
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and tostring(d.ActionText) == "Steal" then
            local par = d.Parent
            local pp = par and (par:IsA("BasePart") and par.Position
                or par:IsA("Model") and safe(function() return par:GetPivot().Position end))
            if pp then local dd = (pp - r.Position).Magnitude; if dd < bd then best, bd = d, dd end end
        end
    end
    return best, bd
end

-- เก็บไข่: ยิง remote CarryFieldEgg(uid, "AreaId:NestId") = instant ไม่ต้องกดค้าง
-- success=true ของ remote = ได้ไข่ (ยังไม่เป็น Tool จน WearEggTool) -> จำ uid ไว้ใช้ตอนวาง
local function grabEgg(rec, eggPos)
    local uid = rec.Uid
    local sk = (rec.AreaId and rec.NestId) and (rec.AreaId .. ":" .. rec.NestId) or rec.NestId
    for attempt = 1, 8 do
        local ok, success = pcall(function() return EggState.CarryFieldEgg(uid, sk) end)
        if ok and success == true then return true end   -- carry สำเร็จ = ไข่เป็นของเรา (ไปวางที่บ้าน)
        -- ยังไม่ได้ (มัก "Get closer") -> ขยับเข้าใกล้ไข่ตรง ๆ แล้วลองใหม่
        if eggPos then
            F.radius = 2; F.arrived = false
            F.target = Vector3.new(eggPos.X, eggPos.Y + (F.lift or 5), eggPos.Z)
        end
        task.wait(0.15)
    end
    F.target = nil
    return false
end

-- วางไข่ทั้งหมดที่ยังไม่ได้วาง (Placement=nil) ลงคอก — เรียกตอนถึงบ้าน
local function placeCF(x, z) return CFrame.new(x, -0.5, z, 0, 0, 1, 0, 1, 0, -1, 0, 0) end
-- ไข่ที่ยังไม่วาง (owned Placement=nil + hotbar) พร้อมเงิน/วิ -> เรียงแพงสุดก่อน
local function unplacedUids()
    local seen, list = {}, {}
    local function add(uid, rec)
        if uid and not seen[uid] then
            seen[uid] = true
            table.insert(list, { uid = uid, rate = rec and eggRate(rec) or 0 })
        end
    end
    -- ★ ไข่ที่วางได้จริง = ที่อยู่ในมือ/hotbar เท่านั้น (Tool ItemType=AssetEgg)
    -- (ReadOwnedEggs จัดกลุ่มตาม "เจ้าของเดิม" รวมไข่คนอื่นทั้ง server -> PlantEgg คืน "Egg not found" ใช้ไม่ได้)
    -- hotbar/กระเป๋า/มือ — สร้าง rec จาก attribute เพื่อคำนวณเงิน
    for _, src in ipairs({ lp.Character, lp:FindFirstChild("Backpack") }) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if t:IsA("Tool") then
                    local uid = t:GetAttribute("UID")
                    if uid and (t:GetAttribute("ItemType") == "AssetEgg" or t.Name:find("Egg")) then
                        add(uid, { AssetCategory = t:GetAttribute("AssetCategory") or t:GetAttribute("Category"),
                            AssetScale = t:GetAttribute("AssetScale") or t:GetAttribute("Scale"),
                            Mutations = t:GetAttribute("Mutations") })
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.rate > b.rate end)   -- ★ แพงสุดก่อน
    local uids = {}
    for _, e in ipairs(list) do table.insert(uids, e.uid) end
    return uids, list
end
local function placeAllEggs()
    task.wait(1)                       -- หยุด 1 วิ ให้ของเข้ากระเป๋าครบ
    local uids = unplacedUids()
    local placed, fails, lastReason = 0, 0, nil
    for _, uid in ipairs(uids) do
        if not F.on then break end
        pcall(function() return EggState.WearEggTool(uid) end)
        task.wait(0.1)
        local ok = false
        for _ = 1, 10 do
            local o, s, reason = pcall(function()
                return EggState.PlantEgg(uid, placeCF(math.random(-150, 130) / 10, math.random(-60, 210) / 10))
            end)
            if o and s == true then ok = true; break end
            lastReason = reason or (o and "success=false" or tostring(s))
            task.wait(0.08)
        end
        if ok then placed = placed + 1; fails = 0; F.count = (F.count or 0) + 1
        else fails = fails + 1; if fails >= 3 then break end end   -- วางไม่ได้ 3 ใบติด = คอกเต็ม/ติด
    end
    print(("[farm] วางลงคอก %d/%d ใบ%s"):format(placed, #uids,
        (placed < #uids and lastReason) and (" | ติด: " .. tostring(lastReason)) or ""))
    return placed, #uids
end

--=========================== money engine: ฟัก -> Equip Best -> ขาย -> อัพเกรด ===========================
-- เปิดไข่ที่ฟักครบ (IsReadyToHatch -> FinishHatch)
local function hatchReady()
    local hatched = 0
    local owned = safe(function() return EggState.ReadOwnedEggs() end)
    if type(owned) == "table" then
        for _, g in pairs(owned) do
            if type(g) == "table" and type(g.Records) == "table" then
                for uid, rec in pairs(g.Records) do
                    if type(rec) == "table" and rec.Placement ~= nil then
                        local ready = safe(function() return EggState.IsReadyToHatch(uid) end)
                        if ready == true then
                            pcall(function() return EggState.BeginHatch(uid) end)
                            pcall(function() return EggState.FinishHatch(uid) end)
                            hatched = hatched + 1
                        end
                    end
                end
            end
        end
    end
    return hatched
end

local function equipBestAndSell()
    pcall(function() return Remotes.Haul.WearBest:InvokeServer() end)   -- Equip Best
    task.wait(0.3)
    -- ขายที่เหลือทิ้ง
    pcall(function() return Remotes.PetSatchel.SellEveryPet:FireServer() end)
    pcall(function() return Remotes.PenRoster.AskSale:InvokeServer() end)
end

F.useTreadmill = (F.useTreadmill ~= false)  -- true=ตอนว่างไปวิ่งลู่ (default) / false=hover
F.lowGfx   = (F.lowGfx ~= false)           -- ลด lag อัตโนมัติตอนเปิด
F.autoEnter = (F.autoEnter ~= false)       -- เดินเข้าโซน gameplay เองตอนเปิด (ถ้ายังไม่เข้า)
F.baseMax = F.baseMax or 11     -- บ้านตันที่ Lv.11 (ผู้ใช้ยืนยัน)
-- ★ ผลัดกันอัพ บ้าน <-> ลู่วิ่ง (ทีละอย่างต่อรอบ)
local function upgradeBase()
    local lvl = F.plot and safe(function() return F.plot:GetAttribute("BaseUpgradeLevel") end)
    if lvl and lvl >= F.baseMax then return end   -- ตันแล้ว
    pcall(function() Remotes.Homestead.AskBaseTierRaise:FireServer() end)
    task.wait(0.3)
    local after = F.plot and safe(function() return F.plot:GetAttribute("BaseUpgradeLevel") end)
    if lvl and after and after > lvl then print(("[farm] ⬆ อัพบ้าน Lv.%d → %d"):format(lvl, after)) end
end
local Treadmills = safe(function() return require(RS.Data.Treadmills) end)
local Save = safe(function() return require(RS.Shared.Save) end)
-- ★ กลไกจริง (จาก decompile TreadmillUpgrade.Client):
--   next = Treadmills.GetByUpgradeLevel(save.TreadmillUpgradeLevel + 1)
--   ถ้า save.Money >= next.Price -> AskTierRaise:InvokeServer(next._id)  [ส่ง _id ของ tier ถัดไป ไม่ใช่ชื่อ]
local function upgradeTreadmill()
    if not (Treadmills and Treadmills.GetByUpgradeLevel and Save) then return end
    local save = safe(function() return Save.Get() end)
    if not save then return end
    local nextLvl = (save.TreadmillUpgradeLevel or 0) + 1
    local cfg = safe(function() return Treadmills.GetByUpgradeLevel(nextLvl) end)
    if not cfg then return end                      -- ลู่ตันแล้ว
    if (save.Money or 0) < (cfg.Price or math.huge) then return end   -- เงินยังไม่พอ = รอ (ไม่ยิงมั่ว)
    local ok, r1, r2 = pcall(function() return Remotes.Treadmill.AskTierRaise:InvokeServer(cfg._id) end)
    if ok and r1 == true then
        print(("[farm] ⬆ อัพลู่วิ่ง Lv.%d → %s (x%s)"):format(nextLvl - 1, tostring(cfg._id), tostring(cfg.SpeedMultiplier)))
        return true
    elseif ok and r2 then
        if tostring(r2) ~= tostring(F.lastTierRes) then F.lastTierRes = r2; print(("[farm] ลู่วิ่ง(%s): %s"):format(tostring(cfg._id), tostring(r2))) end
    end
    return false
end
local function tryUpgrades()
    if not F.autoUpgrade then return end
    F.upTurn = (F.upTurn or 0) + 1
    local baseMaxed = F.plot and (safe(function() return F.plot:GetAttribute("BaseUpgradeLevel") end) or 0) >= F.baseMax
    if baseMaxed then upgradeTreadmill()                       -- บ้านตัน = อัพลู่อย่างเดียว
    elseif F.upTurn % 2 == 1 then upgradeBase()                -- รอบคี่ = บ้าน
    else upgradeTreadmill() end                                -- รอบคู่ = ลู่วิ่ง
end

-- เรียกดูแลระบบ (ฟัก/equip/ขาย/อัพ) — throttle
local function maintain()
    local h = hatchReady()
    if h > 0 then
        F.status = ("🐣 ฟัก %d ใบ -> Equip Best + ขาย"):format(h)
        F.penFull = false          -- ฟักแล้วช่องว่าง วางไข่ค้างต่อได้
        equipBestAndSell()
    end
    if tick() - (F.lastUp or 0) > 4 then F.lastUp = tick(); tryUpgrades() end   -- ผลัดอัพทุก 4 วิ
end

--=========================== Step 2: ลู่วิ่ง (รอไข่/รอฟัก) ===========================
-- ขึ้นลู่เมื่อ: คอกเต็ม หรือ ไม่มีไข่ >= minRate ในแมพ · ลงเมื่อ: มีไข่ให้เก็บ และ คอกมีที่
local function findTreadmill()
    return F.plot and F.plot:FindFirstChild("TreadmillBottom", true)
end
local function idleTreadmill(reason)
    -- จุดยืนลู่: ใช้ที่ตั้งด้วย SETTREADMILL ก่อน, ไม่มีก็หา TreadmillBottom ของ plot เรา
    local spot = F.treadmill
    if not spot then
        local tb = findTreadmill()
        if tb then spot = tb.Position + Vector3.new(0, tb.Size.Y / 2 + 3, 0) end
    end
    if not spot then F.status = "ไม่เจอลู่วิ่ง — hover รอ"; task.wait(3); return end
    flyVia(spot, 4, "→ ลู่วิ่ง")
    F.onTreadmill = true
    restoreHumanoid()
    local r = hrp()
    if r then r.AssemblyLinearVelocity = Vector3.zero; r.CFrame = CFrame.new(spot) end
    F.status = "🏃 วิ่งบนลู่ (" .. tostring(reason) .. ")"
    print("[farm] " .. F.status)
    local ls = lp:FindFirstChild("leaderstats")
    local function speedNow() return ls and ls:FindFirstChild("Speed") and ls.Speed.Value end
    local sp0, t0 = speedNow(), tick()
    while F.on and F.gen == myGen do
        pcall(maintain)                         -- ฟัก/equip/ขาย/อัพ ระหว่างรอ
        local rec = pickEgg()
        if rec and not F.penFull then break end -- ★ ลงจากลู่: มีไข่ให้เก็บ + คอกมีที่
        local rr = hrp(); if rr and (rr.Position - spot).Magnitude > 4 then rr.CFrame = CFrame.new(spot) end  -- ยืนจุดเดิม
        if tick() - t0 > 15 then
            t0 = tick()
            local sp = speedNow()
            if sp0 and sp then print(("[farm] 🏃 Speed %s -> %s (%s)"):format(compact(sp0), compact(sp), sp > sp0 and "▲เพิ่ม!" or "นิ่ง?")); sp0 = sp end
        end
        task.wait(2)
    end
    -- ★ ลงจากลู่แบบเรียบง่าย: AskDoff (ให้ server ปลดเอง) + ถอด Humanoid บิน (ไม่ไปลบ weld/tool เอง)
    F.status = "ลงจากลู่..."
    pcall(function() Remotes.Treadmill.AskDoff:InvokeServer() end)
    task.wait(0.3)
    removeHumanoid()
    F.onTreadmill = false
    F.status = "ลงจากลู่ ไปเก็บไข่"
    print("[farm] ลงจากลู่แล้ว")
end

-- hover รอเฉย ๆ ที่บ้าน (ยังฟัก/ขาย/อัพต่อผ่าน maintain) — ใช้แทนลู่ถ้า useTreadmill=false
local function idleWait(reason)
    if F.useTreadmill then return idleTreadmill(reason) end
    F.status = "⏳ รอ (" .. tostring(reason) .. ") — ฟัก/ขาย/อัพต่อ"
    task.wait(3)
end

--=========================== loop ===========================
local function loop()
    F.placeFails = 0
    while F.on and F.gen == myGen do
        -- ดูแลระบบ: ฟักไข่ที่ครบ -> Equip Best -> ขาย -> อัพบ้าน/ลู่ (ทุกวน)
        pcall(maintain)
        -- ★ กลางคืน: ออกจากโซนไม่ได้ -> รอในเซฟโซน (ยังฟัก/ขาย/อัพต่อผ่าน maintain)
        if isNight() then
            F.status = "🌙 กลางคืน — รอในเซฟโซน"
            if F.safe then goTo(F.safe, 10) end
            F.wasNight = true
            task.wait(3)
        else
        -- ★ เพิ่งเปลี่ยนกลางคืน -> กลางวัน: มี countdown ~3วิ ก่อนไข่พร้อม -> รอก่อนค่อยวิ่งเก็บ
        if F.wasNight then
            F.wasNight = false
            F.status = "🌅 รอเริ่มวัน (countdown)..."
            if F.safe then goTo(F.safe, 10) end
            task.wait(F.dayDelay or 3)
        end
        -- ★ คอกเต็ม -> ขึ้นลู่วิ่งรอฟัก (ลงเมื่อฟักแล้วว่าง + มีไข่)
        if F.penFull then idleWait("คอกเต็ม รอฟัก") end
        local rec, pos, rate = pickEgg()
        if not rec then
            -- ไม่มีไข่ ≥ minRate ในสนาม: ถ้ามีไข่ค้างในกระเป๋า + คอกยังไม่เต็ม -> เอาลงคอก (แพงสุดก่อน)
            if not F.penFull and tick() - (F.lastIdlePlace or 0) > 45 then
                F.lastIdlePlace = tick()
                local pend = unplacedUids()
                if #pend > 0 then
                    F.status = ("ว่าง: เอาไข่ค้าง %d ใบลงคอก"):format(#pend)
                    if flyVia(F.home, 8, "→ บ้าน") then
                        local n, total = placeAllEggs()
                        if total > 0 and n == 0 then F.penFull = true; print("[farm] คอกเต็ม — รอฟักให้ว่างก่อน") end
                    end
                end
            end
            -- ★ เก็บไข่ตามเกณฑ์หมดแมพแล้ว -> ขึ้นลู่วิ่งรอ (ลงเองเมื่อมีไข่ใหม่)
            idleWait("ไม่มีไข่ [" .. tostring(F.phase or compact(F.minRate)) .. "]")
        else
            F.status = ("[%s] ขโมย %s (%s/วิ)"):format(tostring(F.phase or "-"), tostring(rec.AssetCategory), compact(rate or 0))
            -- จอดข้างไข่ (เยื้องมาทางเซฟโซน 3 + ลอยเหนือพื้น 3)
            local from = F.safe or pos
            local dir = flat(from) - flat(pos)
            -- ★ ถ้ามีกับดักติดไข่ -> จอดฝั่งตรงข้ามกับดัก
            local tp = nearTrap(pos, 7)
            if tp then dir = flat(pos) - flat(tp) end
            local approach = dir.Magnitude > 0.1 and (pos + dir.Unit * 3) or pos
            approach = Vector3.new(approach.X, pos.Y + 3, approach.Z)

            if flyVia(approach, 4, "→ ไข่") and grabEgg(rec, pos) then
                if flyVia(F.home, 8, "→ บ้าน") then
                    F.status = "เช็คของ + วางไข่..."
                    local n, total = placeAllEggs()
                    F.status = ("✅ วาง %d/%d ใบ"):format(n, total)
                    if total > 0 and n == 0 then
                        F.placeFails = (F.placeFails or 0) + 1
                        if F.placeFails >= 3 then warn("[farm] วางไม่ลงเลย 3 รอบ = คอกเต็ม/ติด — หยุด"); F.on = false end
                    else F.placeFails = 0 end
                else
                    F.status = "ถึงบ้านไม่ได้ ข้าม"; F.skip[rec.Uid] = tick() + 5
                end
            else
                F.status = "เก็บไม่ได้ ข้าม"; F.skip[rec.Uid] = tick() + 5
            end
            task.wait(0.1)
        end
        end   -- ปิด else ของ isNight
    end
    F.status = "หยุดแล้ว"
end

--=========================== control ===========================
getgenv().SETSAFE = function()
    local r = hrp(); if r then F.safe = r.Position
        print(("[farm] ✅ เซฟโซน (%.0f,%.0f,%.0f)"):format(r.Position.X, r.Position.Y, r.Position.Z)) end
end
getgenv().SETHOME = function()
    local r = hrp(); if r then F.home = r.Position; F.homeManual = true
        print(("[farm] ✅ บ้าน (%.0f,%.0f,%.0f)"):format(r.Position.X, r.Position.Y, r.Position.Z)) end
end
-- ยืนบนลู่วิ่งจริง (ที่ Speed เพิ่ม) แล้วเรียก = จำจุดยืนลู่
getgenv().SETTREADMILL = function()
    local r = hrp(); if r then F.treadmill = r.Position; F.useTreadmill = true
        print(("[farm] ✅ จุดลู่วิ่ง (%.1f,%.1f,%.1f) + เปิด useTreadmill"):format(r.Position.X, r.Position.Y, r.Position.Z)) end
end

--=========================== ลด lag (merge จาก lowgfx) ===========================
local function lowGfx()
    if not F.lowGfx or F.gfxDone then return end
    F.gfxDone = true
    local KILL_F = { "ClientRenderedAssets", "MonsterParasiteMonsters", "PlacedEggRenders",
        "AreaEggSlotsClient", "__ClientTreadmillRenders", "Stands" }
    local KILL_C = { ParticleEmitter = true, Beam = true, Trail = true, Smoke = true, Fire = true, Sparkles = true, Explosion = true }
    local LIGHT_C = { PointLight = true, SpotLight = true, SurfaceLight = true }
    local PLASTIC = Enum.Material.SmoothPlastic
    local function strip(d)
        local c = d.ClassName
        if KILL_C[c] then d:Destroy()
        elseif LIGHT_C[c] then d.Enabled = false
        elseif c == "Sound" then d.Volume = 0
        elseif c == "Decal" or c == "Texture" then d.Transparency = 1
        elseif c == "SpecialMesh" then pcall(function() d.TextureId = "" end)
        elseif d:IsA("BasePart") then d.Material = PLASTIC; d.Reflectance = 0
            if c == "MeshPart" then pcall(function() d.TextureID = "" end) end
        end
    end
    for _, name in ipairs(KILL_F) do
        local f = Workspace:FindFirstChild(name)
        if f then
            for _, ch in ipairs(f:GetChildren()) do pcall(function() ch:Destroy() end) end
            local c = f.ChildAdded:Connect(function(ch) task.defer(function() pcall(function() ch:Destroy() end) end) end)
            table.insert(F.gfxConns or (function() F.gfxConns = {}; return F.gfxConns end)(), c)
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character then pcall(function() plr.Character:Destroy() end) end
    end
    Players.PlayerAdded:Connect(function(plr) if plr ~= lp then plr.CharacterAdded:Connect(function(ch) task.defer(function() pcall(function() ch:Destroy() end) end) end) end end)
    for _, root in ipairs({ Workspace, game:GetService("Lighting") }) do
        for _, d in ipairs(root:GetDescendants()) do pcall(strip, d) end
    end
    Workspace.DescendantAdded:Connect(function(d) task.defer(function() pcall(strip, d) end) end)
    pcall(function() game:GetService("Lighting").GlobalShadows = false end)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function() Workspace.Terrain.Decoration = false end)
    -- sweep เคลียร์ไข่/สัตว์ render เป็นระยะ
    task.spawn(function()
        while F.lowGfx and F.gen == myGen do
            for _, name in ipairs(KILL_F) do
                local f = Workspace:FindFirstChild(name)
                if f then for _, ch in ipairs(f:GetChildren()) do pcall(function() ch:Destroy() end) end end
            end
            task.wait(4)
        end
    end)
    print("[farm] ⚡ ลด lag แล้ว (ลบ render/effect + ลุคดินน้ำมัน)")
end

--=========================== auto เข้าโซน gameplay ===========================
local function inGameplay()
    local GAG = safe(function() return require(RS.Shared.Util.GuardAreaGeometry) end)
    local line = safe(function() return Workspace.__OBJECTS.Areas.SeparationLine end)
    local r = hrp()
    if not (GAG and line and r) then return true end   -- ไม่รู้ = ถือว่าเข้าแล้ว
    return safe(function() return GAG.IsPastLine(line, r.Position) end) == true
end
local function autoEnter()
    if not F.autoEnter or inGameplay() then return end   -- ไอดีหลักเข้าอยู่แล้ว = ข้าม
    F.status = "เดินเข้าโซน gameplay..."
    print("[farm] ยังไม่เข้าโซน — เดินเข้าให้")
    restoreHumanoid()
    local hum = humanoid()
    -- เดินเข้าหาไข่ที่อยู่ฝั่ง gameplay (past line) จนกว่าจะ IsPastLine=true
    for _ = 1, 3 do
        local rec, pos = pickEgg()
        if not pos then pos = hrp() and (hrp().Position + Vector3.new(0, 0, -60)) end
        if hum and pos then
            hum.WalkSpeed = 50
            local t0 = tick()
            while tick() - t0 < 8 and not inGameplay() do hum:MoveTo(pos); RunService.Heartbeat:Wait() end
        end
        if inGameplay() then break end
    end
    print("[farm] " .. (inGameplay() and "✅ เข้าโซนแล้ว" or "⚠ เข้าโซนอัตโนมัติไม่ได้ — เดินเข้าเองด้วยมือ 1 ครั้ง"))
end

getgenv().FARM = function(on)
    F.on = (on ~= false)
    if not F.on then F.target = nil; restoreHumanoid(); print("[farm] ปิด (คืน Humanoid)"); return end
    F.carriedUid = nil
    pcall(lowGfx)
    pcall(autoEnter)
    -- หาบ้าน: auto ก่อน, ไม่ได้ค่อยใช้ manual
    local hp, plot = findHome()
    if hp then F.home = hp; F.plot = plot
        print(("[farm] ✅ บ้าน: %s (%.0f,%.0f,%.0f) Lv.%s"):format(plot.Name, hp.X, hp.Y, hp.Z,
            tostring(safe(function() return plot:GetAttribute("BaseUpgradeLevel") end))))
    elseif F.home then print(("[farm] ใช้บ้านเดิม (%.0f,%.0f,%.0f)"):format(F.home.X, F.home.Y, F.home.Z))
    else F.on = false; warn("[farm] หาบ้านไม่เจอ — ยืนคอกแล้ว SETHOME() ครั้งเดียว"); return end
    print(("[farm] บิน %d | กรอง >= %s/วิ | เรียง: %s"):format(F.speed, compact(F.minRate),
        F.order == "value" and "แพงสุดก่อน" or (F.order == "far" and "ไกลก่อน" or "ใกล้ก่อน")))
    -- print สถานะทุกครั้งที่เปลี่ยน (ให้ตามใน console.txt ได้)
    task.spawn(function()
        local last
        while F.on and F.gen == myGen do
            if F.status ~= last then last = F.status; print("[farm] " .. tostring(F.status)) end
            task.wait(0.5)
        end
    end)
    removeHumanoid()
    task.spawn(loop)
end

--=========================== UI: ไอคอนวงกลมกลางจอ = สคริปกำลังทำงาน ===========================
local parent = (gethui and gethui()) or lp:FindFirstChildOfClass("PlayerGui") or game:GetService("CoreGui")
local old = parent:FindFirstChild("FarmUI"); if old then old:Destroy() end
local gui = Instance.new("ScreenGui"); gui.Name = "FarmUI"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.DisplayOrder = 999; gui.Parent = parent

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.Position = UDim2.fromScale(0.5, 0.20)
holder.Size = UDim2.fromOffset(130, 130); holder.BackgroundTransparency = 1; holder.Parent = gui

local icon = Instance.new("ImageLabel")
icon.Size = UDim2.fromScale(1, 1); icon.BackgroundTransparency = 1
icon.ScaleType = Enum.ScaleType.Fit
-- โหลดไอคอน: ถ้าไม่มีไฟล์ในเครื่อง (เครื่องอื่น) ดึงจาก F.iconUrl มาเซฟก่อน แล้วค่อย getcustomasset
icon.Image = (function()
    local getasset = getcustomasset or getsynasset
    if not getasset then return "" end
    local have = isfile and safe(function() return isfile("steal-icon.png") end)
    if not have and writefile and F.iconUrl and not F.iconUrl:find("USER/REPO") then
        pcall(function() writefile("steal-icon.png", game:HttpGet(F.iconUrl)) end)
    end
    return safe(function() return getasset("steal-icon.png") end) or ""
end)()
icon.Parent = holder

local stx = Instance.new("TextLabel")
stx.AnchorPoint = Vector2.new(0.5, 0); stx.Position = UDim2.new(0.5, 0, 1, 6)
stx.Size = UDim2.fromOffset(300, 18); stx.BackgroundTransparency = 1
stx.Font = Enum.Font.GothamBold; stx.TextSize = 12; stx.TextColor3 = Color3.fromRGB(255, 255, 255)
stx.TextStrokeTransparency = 0.4; stx.Text = "กำลังทำงาน"; stx.Parent = holder

-- pulse ไอคอน = บอกว่ายังทำงาน
task.spawn(function()
    local t = 0
    while gui.Parent do
        t = t + 0.05
        icon.ImageTransparency = 0.08 + 0.12 * (math.sin(t * 3) * 0.5 + 0.5)  -- ไล่ 0.08..0.20
        task.wait(0.05)
    end
end)
task.spawn(function()
    while gui.Parent do
        holder.Visible = (F.on == true)          -- ทำงาน = โชว์ / หยุด = ซ่อน
        stx.Text = tostring(F.status or "กำลังทำงาน")
        task.wait(0.3)
    end
end)

print("[farm] ✅ เริ่มทำงานอัตโนมัติ — ไอคอนกลางจอ = กำลังทำงาน (ไม่มีปุ่มติ๊กแล้ว)")
print("[farm] ปรับ: getgenv().__farm.speed/.minRate | SETHOME()/SETSAFE() | หยุด: FARM(false)")

-- ★ รันทันที ไม่ต้องกดปุ่ม
task.spawn(function() pcall(function() getgenv().FARM(true) end) end)
