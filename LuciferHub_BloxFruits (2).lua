--[[
    LUCIFER HUB  •  Blox Fruits (Sea 1 / 2 / 3)  •  Delta X
    ─────────────────────────────────────────────────────────
    1) Auto Farm Level  : check level → chọn quest/đảo → nhận quest → bay tới quái
                          → gom quái → tự đánh (Võ / Kiếm / Súng / Trái)
    2) Fruit            : ESP • Auto Random (Lv50, mỗi 2 giờ) • Auto cất trái • Bay nhặt trái
    3) Auto Code        : nhập danh sách code
    4) Anti AFK
    5) Auto Stats       : tự cộng điểm kỹ năng
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ════════════════════════════ SERVICES ════════════════════════════
local cloneref = cloneref or function(o) return o end
local function Svc(name) return cloneref(game:GetService(name)) end

local Players = Svc("Players")
local Workspace = Svc("Workspace")
local ReplicatedStorage = Svc("ReplicatedStorage")
local RunService = Svc("RunService")
local UserInputService = Svc("UserInputService")
local TweenService = Svc("TweenService")
local VirtualUser = Svc("VirtualUser")
local CoreGui = Svc("CoreGui")
local GuiService = Svc("GuiService")
local VIM
pcall(function() VIM = Svc("VirtualInputManager") end)

local LocalPlayer = Players.LocalPlayer
local function Cam() return Workspace.CurrentCamera end

-- ════════════════════════════ GAME / REMOTES ════════════════════════════
local PID = game.PlaceId
local WORLD = 0
if PID == 2753915549 or PID == 85211729168715 then
    WORLD = 1
elseif PID == 4442272183 or PID == 79091703265657 then
    WORLD = 2
elseif PID == 7449423635 or PID == 100117331123089 then
    WORLD = 3
end
if WORLD == 0 then
    warn("[Lucifer] Script chỉ chạy trong Blox Fruits.")
    return
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
local CommF = Remotes and Remotes:WaitForChild("CommF_", 20)
if not CommF then
    warn("[Lucifer] Không tìm thấy CommF_, script dừng.")
    return
end
local RedeemRemote = Remotes:FindFirstChild("Redeem")

-- [CẬP NHẬT] Rà nhánh ReplicatedStorage.Modules.Net an toàn (pcall + timeout ngắn), tìm cả tên cũ lẫn tên mới
local RegisterAttack, RegisterHit
local NetNames = {}
pcall(function()
    local modules = ReplicatedStorage:WaitForChild("Modules", 4)
    local net = modules and modules:WaitForChild("Net", 4)
    if not net then return end
    for _, c in ipairs(net:GetChildren()) do
        if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then NetNames[#NetNames + 1] = c.Name end
    end
    RegisterAttack = net:FindFirstChild("RE/RegisterAttack") or net:FindFirstChild("RegisterAttack")
    RegisterHit = net:FindFirstChild("RE/RegisterHit") or net:FindFirstChild("RegisterHit")
    if not (RegisterAttack and RegisterHit) then
        for _, c in ipairs(net:GetChildren()) do
            local n = string.lower(c.Name)
            if not RegisterAttack and string.find(n, "registerattack", 1, true) then RegisterAttack = c end
            if not RegisterHit and string.find(n, "registerhit", 1, true) then RegisterHit = c end
        end
    end
end)

-- ════════════════════════════ STATE / CONFIG ════════════════════════════
local S = {
    Running = true,
    Paused = false,          -- true khi đang bay nhặt trái (tạm dừng mọi chức năng khác)
    Status = "Sẵn sàng",
    QuestInfo = "Chưa bật Auto Farm",
    Attacking = false,
    Target = nil,
    Anchor = nil,
    FarmOn = false,
    WeaponMissing = false,
    QuestFail = 0, QuestFailAt = 0,
    LastQuest = 0, LastAbandon = 0, LastEntrance = 0, LastTravel = 0,
    LastEquip = 0, LastHaki = 0, LastSkill = 0, SkillIdx = 1,
    FruitCount = 0,
    LastRandom = 0, RandomRetryAt = 0, ForceRandom = false,
    CodesBusy = false,
    StatPending = nil, StatFails = 0, StatSingle = false,
    -- chẩn đoán đánh / gom quái
    QuestMob = nil,
    AtkNote = "", EquipNote = "",
    LastDamageAt = 0, ProfileIdx = 1, ProfileSince = 0, WasAttacking = false,
    BringCount = 0, BringOwned = 0,
    InSafeZone = false,
    SkillNext = {},
    QuestKey = nil,
    -- hit engine v3
    GeoStep = 1, ProfName = "Click", ProfStat = {},
    AtkDetail = "", LastDist = 0,
    LastCapSeen = 0, CapPrinted = false,
    SessionAt = nil, SessionCache = nil,
    ToolReadyAt = 0, LastToolInst = nil,
}

local Move = { Active = false, Pos = nil, Face = nil }

local Cfg = {
    -- Auto Farm Level
    AutoFarm = false,
    Weapon = "Melee",        -- Melee | Sword | Gun | Blox Fruit
    Speed = 300,
    Height = 5,
    Bring = true,
    BigHitbox = false,
    CaptureHook = true,
    FastAttack = true,
    Haki = true,
    NoClip = true,
    UseSkills = true,
    AutoSea = false,
    -- Fruit
    FruitESP = false,
    RandomFruit = false,
    StoreFruit = false,
    FlyFruit = false,
    -- Code / Misc
    AutoCode = false,
    CodeReset = false,
    AntiAFK = true,
    -- Stats
    AutoStats = false,
    Stats = { Melee = true },
}

local Conns, Insts, ESP = {}, {}, {}
local Prepared = setmetatable({}, { __mode = "k" })  -- [mob] = { parts, root, hum, size0 }
local BringSet = {}                                  -- [mob] = info  (quái đang được ghim về S.Anchor)
local RestoreHitboxes = function() end               -- gán lại ở phần MOB / COMBAT

local function Track(c) Conns[#Conns + 1] = c return c end

local function Cleanup()
    S.Running = false
    S.Paused = false
    Move.Active = false
    for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
    for _, i in ipairs(Insts) do pcall(function() i:Destroy() end) end
    for h, bb in pairs(ESP) do
        pcall(function() bb:Destroy() end)
        ESP[h] = nil
    end
    table.clear(BringSet)
    pcall(RestoreHitboxes)
    local ge = (getgenv and getgenv()) or _G
    if ge.LuciferBFCap then ge.LuciferBFCap.on = false end -- hook (nếu đã cài) chuyển sang chế độ chỉ chuyển tiếp
    local char = LocalPlayer.Character
    if char then
        local hr = char:FindFirstChild("HumanoidRootPart")
        local hold = hr and hr:FindFirstChild("LuciferHold")
        if hold then pcall(function() hold:Destroy() end) end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.CanCollide = true end
        end
    end
end

local env = (getgenv and getgenv()) or _G
if env.LuciferBFCleanup then pcall(env.LuciferBFCleanup) end
env.LuciferBFCleanup = Cleanup

-- placeholder (gán lại khi UI dựng xong)
local Toast = function(_) end
local UIMain = nil   -- gán khi dựng xong cửa sổ chính (để click không rơi vào menu)

-- ════════════════════════════ HELPERS ════════════════════════════
local function GetRoot(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end
local function GetHum(char) return char and char:FindFirstChildOfClass("Humanoid") end
local function Alive(m) local h = GetHum(m) return h ~= nil and h.Health > 0 end

local function DataValue(name, default)
    local d = LocalPlayer:FindFirstChild("Data")
    local v = d and d:FindFirstChild(name)
    if v and v.Value ~= nil then return v.Value end
    return default
end
local function GetLevel() return tonumber(DataValue("Level", 1)) or 1 end

local function Invoke(...)
    local args = table.pack(...)
    task.spawn(function()
        pcall(function() CommF:InvokeServer(table.unpack(args, 1, args.n)) end)
    end)
end
local function InvokeSync(...)
    return pcall(CommF.InvokeServer, CommF, ...)
end

local function SetStatus(t) S.Status = t end

local function FmtTime(sec)
    if sec < 0 then sec = 0 end
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), math.floor(sec % 60))
end

local function Loop(interval, fn)
    task.spawn(function()
        while S.Running do
            local ok, err = pcall(fn)
            if not ok then
                warn("[Lucifer] " .. tostring(err))
                task.wait(1)
            end
            task.wait(interval)
        end
    end)
end

local function ForEachTool(fn)
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then fn(t) end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then fn(t) end
        end
    end
end

local function IsPhysicalFruit(t)
    return t.ToolTip == "Blox Fruit" and string.find(t.Name, "Fruit") ~= nil
end

local function CountFruits()
    local n = 0
    ForEachTool(function(t) if IsPhysicalFruit(t) then n = n + 1 end end)
    return n
end

-- ════════════════════════════ QUEST DATABASE (Sea 1 / 2 / 3) ════════════════════════════
local QuestDB = {
    {W=1,Min=1,Max=9,Mob="Bandit",Quest="BanditQuest1",Lv=1,CQ=Vector3.new(1059.37,15.45,1550.42),CM=Vector3.new(1045.96,27,1560.82)},
    {W=1,Min=10,Max=14,Mob="Monkey",Quest="JungleQuest",Lv=1,CQ=Vector3.new(-1598.09,35.55,153.38),CM=Vector3.new(-1448.52,67.85,11.47)},
    {W=1,Min=15,Max=29,Mob="Gorilla",Quest="JungleQuest",Lv=2,CQ=Vector3.new(-1598.09,35.55,153.38),CM=Vector3.new(-1129.88,40.46,-525.42)},
    {W=1,Min=30,Max=39,Mob="Pirate",Quest="BuggyQuest1",Lv=1,CQ=Vector3.new(-1141.07,4.1,3831.55),CM=Vector3.new(-1103.51,13.75,3896.09)},
    {W=1,Min=40,Max=59,Mob="Brute",Quest="BuggyQuest1",Lv=2,CQ=Vector3.new(-1141.07,4.1,3831.55),CM=Vector3.new(-1140.08,14.81,4322.92)},
    {W=1,Min=60,Max=74,Mob="Desert Bandit",Quest="DesertQuest",Lv=1,CQ=Vector3.new(894.49,5.14,4392.43),CM=Vector3.new(924.8,6.45,4481.59)},
    {W=1,Min=75,Max=89,Mob="Desert Officer",Quest="DesertQuest",Lv=2,CQ=Vector3.new(894.49,5.14,4392.43),CM=Vector3.new(1608.28,8.61,4371.01)},
    {W=1,Min=90,Max=99,Mob="Snow Bandit",Quest="SnowQuest",Lv=1,CQ=Vector3.new(1389.74,88.15,-1298.91),CM=Vector3.new(1354.35,87.27,-1393.95)},
    {W=1,Min=100,Max=119,Mob="Snowman",Quest="SnowQuest",Lv=2,CQ=Vector3.new(1389.74,88.15,-1298.91),CM=Vector3.new(1201.64,144.58,-1550.07)},
    {W=1,Min=120,Max=149,Mob="Chief Petty Officer",Quest="MarineQuest2",Lv=1,CQ=Vector3.new(-5039.59,27.35,4324.68),CM=Vector3.new(-4881.23,22.65,4273.75)},
    {W=1,Min=150,Max=174,Mob="Sky Bandit",Quest="SkyQuest",Lv=1,CQ=Vector3.new(-4839.53,716.37,-2619.44),CM=Vector3.new(-4953.21,295.74,-2899.23)},
    {W=1,Min=175,Max=189,Mob="Dark Master",Quest="SkyQuest",Lv=2,CQ=Vector3.new(-4839.53,716.37,-2619.44),CM=Vector3.new(-5259.84,391.4,-2229.04)},
    {W=1,Min=190,Max=209,Mob="Prisoner",Quest="PrisonerQuest",Lv=1,CQ=Vector3.new(5308.93,1.66,475.12),CM=Vector3.new(5098.97,-0.32,474.24)},
    {W=1,Min=210,Max=249,Mob="Dangerous Prisoner",Quest="PrisonerQuest",Lv=2,CQ=Vector3.new(5308.93,1.66,475.12),CM=Vector3.new(5654.56,15.63,866.3)},
    {W=1,Min=250,Max=274,Mob="Toga Warrior",Quest="ColosseumQuest",Lv=1,CQ=Vector3.new(-1580.05,6.35,-2986.48),CM=Vector3.new(-1820.21,51.68,-2740.67)},
    {W=1,Min=275,Max=299,Mob="Gladiator",Quest="ColosseumQuest",Lv=2,CQ=Vector3.new(-1580.05,6.35,-2986.48),CM=Vector3.new(-1292.84,56.38,-3339.03)},
    {W=1,Min=300,Max=324,Mob="Military Soldier",Quest="MagmaQuest",Lv=1,CQ=Vector3.new(-5313.37,10.95,8515.29),CM=Vector3.new(-5411.16,11.08,8454.29)},
    {W=1,Min=325,Max=374,Mob="Military Spy",Quest="MagmaQuest",Lv=2,CQ=Vector3.new(-5313.37,10.95,8515.29),CM=Vector3.new(-5802.87,86.26,8828.86)},
    {W=1,Min=375,Max=399,Mob="Fishman Warrior",Quest="FishmanQuest",Lv=1,CQ=Vector3.new(61122.65,18.5,1569.4),CM=Vector3.new(60878.3,18.48,1543.76),E=Vector3.new(61163.85,11.68,1819.78)},
    {W=1,Min=400,Max=449,Mob="Fishman Commando",Quest="FishmanQuest",Lv=2,CQ=Vector3.new(61122.65,18.5,1569.4),CM=Vector3.new(61922.63,18.48,1493.93),E=Vector3.new(61163.85,11.68,1819.78)},
    {W=1,Min=450,Max=474,Mob="God's Guard",Quest="SkyExp1Quest",Lv=1,CQ=Vector3.new(-4721.89,843.87,-1949.97),CM=Vector3.new(-4710.04,845.28,-1927.31),E=Vector3.new(-4607.82,872.54,-1667.56)},
    {W=1,Min=475,Max=524,Mob="Shanda",Quest="SkyExp1Quest",Lv=2,CQ=Vector3.new(-7859.1,5544.19,-381.48),CM=Vector3.new(-7678.49,5566.4,-497.22),E=Vector3.new(-7894.62,5547.14,-380.29)},
    {W=1,Min=525,Max=549,Mob="Royal Squad",Quest="SkyExp2Quest",Lv=1,CQ=Vector3.new(-7906.82,5634.66,-1411.99),CM=Vector3.new(-7624.25,5658.13,-1467.35)},
    {W=1,Min=550,Max=624,Mob="Royal Soldier",Quest="SkyExp2Quest",Lv=2,CQ=Vector3.new(-7906.82,5634.66,-1411.99),CM=Vector3.new(-7836.75,5645.66,-1790.62)},
    {W=1,Min=625,Max=649,Mob="Galley Pirate",Quest="FountainQuest",Lv=1,CQ=Vector3.new(5259.82,37.35,4050.03),CM=Vector3.new(5551.02,78.9,3930.41)},
    {W=1,Min=650,Max=99999,Mob="Galley Captain",Quest="FountainQuest",Lv=2,CQ=Vector3.new(5259.82,37.35,4050.03),CM=Vector3.new(5441.95,42.5,4950.09)},
    {W=2,Min=700,Max=724,Mob="Raider",Quest="Area1Quest",Lv=1,CQ=Vector3.new(-429.54,71.77,1836.18),CM=Vector3.new(-728.33,52.78,2345.77)},
    {W=2,Min=725,Max=774,Mob="Mercenary",Quest="Area1Quest",Lv=2,CQ=Vector3.new(-429.54,71.77,1836.18),CM=Vector3.new(-1004.32,80.16,1424.62)},
    {W=2,Min=775,Max=799,Mob="Swan Pirate",Quest="Area2Quest",Lv=1,CQ=Vector3.new(638.44,71.77,918.28),CM=Vector3.new(1068.66,137.61,1322.11)},
    {W=2,Min=800,Max=874,Mob="Factory Staff",Quest="Area2Quest",Lv=2,CQ=Vector3.new(632.7,73.11,918.67),CM=Vector3.new(73.08,81.86,-27.47)},
    {W=2,Min=875,Max=899,Mob="Marine Lieutenant",Quest="MarineQuest3",Lv=1,CQ=Vector3.new(-2440.8,71.71,-3216.07),CM=Vector3.new(-2821.37,75.9,-3070.09)},
    {W=2,Min=900,Max=949,Mob="Marine Captain",Quest="MarineQuest3",Lv=2,CQ=Vector3.new(-2440.8,71.71,-3216.07),CM=Vector3.new(-1861.23,80.18,-3254.7)},
    {W=2,Min=950,Max=974,Mob="Zombie",Quest="ZombieQuest",Lv=1,CQ=Vector3.new(-5497.06,47.59,-795.24),CM=Vector3.new(-5657.78,78.97,-928.69)},
    {W=2,Min=975,Max=999,Mob="Vampire",Quest="ZombieQuest",Lv=2,CQ=Vector3.new(-5497.06,47.59,-795.24),CM=Vector3.new(-6037.67,32.18,-1340.66)},
    {W=2,Min=1000,Max=1049,Mob="Snow Trooper",Quest="SnowMountainQuest",Lv=1,CQ=Vector3.new(609.86,400.12,-5372.26),CM=Vector3.new(549.15,427.39,-5563.7)},
    {W=2,Min=1050,Max=1099,Mob="Winter Warrior",Quest="SnowMountainQuest",Lv=2,CQ=Vector3.new(609.86,400.12,-5372.26),CM=Vector3.new(1142.75,475.64,-5199.42)},
    {W=2,Min=1100,Max=1124,Mob="Lab Subordinate",Quest="IceSideQuest",Lv=1,CQ=Vector3.new(-6064.07,15.24,-4902.98),CM=Vector3.new(-5707.47,15.95,-4513.39)},
    {W=2,Min=1125,Max=1174,Mob="Horned Warrior",Quest="IceSideQuest",Lv=2,CQ=Vector3.new(-6064.07,15.24,-4902.98),CM=Vector3.new(-6341.37,15.95,-5723.16)},
    {W=2,Min=1175,Max=1199,Mob="Magma Ninja",Quest="FireSideQuest",Lv=1,CQ=Vector3.new(-5428.03,15.06,-5299.43),CM=Vector3.new(-5449.67,76.66,-5808.2)},
    {W=2,Min=1200,Max=1249,Mob="Lava Pirate",Quest="FireSideQuest",Lv=2,CQ=Vector3.new(-5428.03,15.06,-5299.43),CM=Vector3.new(-5213.33,49.74,-4701.45)},
    {W=2,Min=1250,Max=1274,Mob="Ship Deckhand",Quest="ShipQuest1",Lv=1,CQ=Vector3.new(1037.8,125.09,32911.6),CM=Vector3.new(1212.01,150.79,33059.25),E=Vector3.new(923.21,126.98,32852.83)},
    {W=2,Min=1275,Max=1299,Mob="Ship Engineer",Quest="ShipQuest1",Lv=2,CQ=Vector3.new(1037.8,125.09,32911.6),CM=Vector3.new(919.48,43.54,32779.97),E=Vector3.new(923.21,126.98,32852.83)},
    {W=2,Min=1300,Max=1324,Mob="Ship Steward",Quest="ShipQuest2",Lv=1,CQ=Vector3.new(968.81,125.09,33244.12),CM=Vector3.new(919.44,129.56,33436.04),E=Vector3.new(923.21,126.98,32852.83)},
    {W=2,Min=1325,Max=1349,Mob="Ship Officer",Quest="ShipQuest2",Lv=2,CQ=Vector3.new(968.81,125.09,33244.12),CM=Vector3.new(1036.02,181.44,33315.73),E=Vector3.new(923.21,126.98,32852.83)},
    {W=2,Min=1350,Max=1374,Mob="Arctic Warrior",Quest="FrostQuest",Lv=1,CQ=Vector3.new(5667.66,26.8,-6486.09),CM=Vector3.new(5966.25,62.97,-6179.38),E=Vector3.new(-6508.56,5000.03,-132.84)},
    {W=2,Min=1375,Max=1424,Mob="Snow Lurker",Quest="FrostQuest",Lv=2,CQ=Vector3.new(5667.66,26.8,-6486.09),CM=Vector3.new(5407.07,69.19,-6880.88)},
    {W=2,Min=1425,Max=1449,Mob="Sea Soldier",Quest="ForgottenQuest",Lv=1,CQ=Vector3.new(-3054.44,235.54,-10142.82),CM=Vector3.new(-3028.22,64.67,-9775.43)},
    {W=2,Min=1450,Max=99999,Mob="Water Fighter",Quest="ForgottenQuest",Lv=2,CQ=Vector3.new(-3054.44,235.54,-10142.82),CM=Vector3.new(-3352.9,285.02,-10534.84)},
    {W=3,Min=1500,Max=1524,Mob="Pirate Millionaire",Quest="PiratePortQuest",Lv=1,CQ=Vector3.new(-450.1,107.68,5950.73),CM=Vector3.new(-246,47.31,5584.1)},
    {W=3,Min=1525,Max=1574,Mob="Pistol Billionaire",Quest="PiratePortQuest",Lv=2,CQ=Vector3.new(-450.1,107.68,5950.73),CM=Vector3.new(-54.81,83.77,5947.84)},
    {W=3,Min=1575,Max=1599,Mob="Dragon Crew Warrior",Quest="DragonCrewQuest",Lv=1,CQ=Vector3.new(6750.49,127.45,-711.03),CM=Vector3.new(6709.76,52.34,-1139.03)},
    {W=3,Min=1600,Max=1624,Mob="Dragon Crew Archer",Quest="DragonCrewQuest",Lv=2,CQ=Vector3.new(6750.49,127.45,-711.03),CM=Vector3.new(6668.76,481.38,329.12)},
    {W=3,Min=1625,Max=1649,Mob="Hydra Enforcer",Quest="VenomCrewQuest",Lv=1,CQ=Vector3.new(5206.4,1004.1,748.35),CM=Vector3.new(4547.12,1003.1,334.19)},
    {W=3,Min=1650,Max=1699,Mob="Venomous Assailant",Quest="VenomCrewQuest",Lv=2,CQ=Vector3.new(5206.4,1004.1,748.35),CM=Vector3.new(4674.93,1134.83,996.31)},
    {W=3,Min=1700,Max=1724,Mob="Marine Commodore",Quest="MarineTreeIsland",Lv=1,CQ=Vector3.new(2481.09,74.27,-6779.64),CM=Vector3.new(2577.25,75.61,-7739.87)},
    {W=3,Min=1725,Max=1774,Mob="Marine Rear Admiral",Quest="MarineTreeIsland",Lv=2,CQ=Vector3.new(2481.09,74.27,-6779.64),CM=Vector3.new(3761.81,123.91,-6823.52)},
    {W=3,Min=1775,Max=1799,Mob="Fishman Raider",Quest="DeepForestIsland3",Lv=1,CQ=Vector3.new(-10581.66,330.87,-8761.19),CM=Vector3.new(-10407.53,331.76,-8368.52)},
    {W=3,Min=1800,Max=1824,Mob="Fishman Captain",Quest="DeepForestIsland3",Lv=2,CQ=Vector3.new(-10581.66,330.87,-8761.19),CM=Vector3.new(-10994.7,352.38,-9002.11)},
    {W=3,Min=1825,Max=1849,Mob="Forest Pirate",Quest="DeepForestIsland",Lv=1,CQ=Vector3.new(-13234.04,331.49,-7625.4),CM=Vector3.new(-13274.48,332.38,-7769.58)},
    {W=3,Min=1850,Max=1899,Mob="Mythological Pirate",Quest="DeepForestIsland",Lv=2,CQ=Vector3.new(-13234.04,331.49,-7625.4),CM=Vector3.new(-13680.61,501.08,-6991.19)},
    {W=3,Min=1900,Max=1924,Mob="Jungle Pirate",Quest="DeepForestIsland2",Lv=1,CQ=Vector3.new(-12680.38,389.97,-9902.02),CM=Vector3.new(-12256.16,331.74,-10485.84)},
    {W=3,Min=1925,Max=1974,Mob="Musketeer Pirate",Quest="DeepForestIsland2",Lv=2,CQ=Vector3.new(-12680.38,389.97,-9902.02),CM=Vector3.new(-13457.9,391.55,-9859.18)},
    {W=3,Min=1975,Max=1999,Mob="Reborn Skeleton",Quest="HauntedQuest1",Lv=1,CQ=Vector3.new(-9479.22,141.22,5566.09),CM=Vector3.new(-8763.72,165.72,6159.86)},
    {W=3,Min=2000,Max=2024,Mob="Living Zombie",Quest="HauntedQuest1",Lv=2,CQ=Vector3.new(-9479.22,141.22,5566.09),CM=Vector3.new(-10144.13,138.63,5838.09)},
    {W=3,Min=2025,Max=2049,Mob="Demonic Soul",Quest="HauntedQuest2",Lv=1,CQ=Vector3.new(-9516.99,172.02,6078.47),CM=Vector3.new(-9505.87,172.1,6158.99)},
    {W=3,Min=2050,Max=2074,Mob="Posessed Mummy",Quest="HauntedQuest2",Lv=2,CQ=Vector3.new(-9516.99,172.02,6078.47),CM=Vector3.new(-9582.02,6.25,6205.48)},
    {W=3,Min=2075,Max=2099,Mob="Peanut Scout",Quest="NutsIslandQuest",Lv=1,CQ=Vector3.new(-2104.39,38.1,-10194.22),CM=Vector3.new(-2143.24,47.72,-10030)},
    {W=3,Min=2100,Max=2124,Mob="Peanut President",Quest="NutsIslandQuest",Lv=2,CQ=Vector3.new(-2104.39,38.1,-10194.22),CM=Vector3.new(-1859.35,38.1,-10422.43)},
    {W=3,Min=2125,Max=2149,Mob="Ice Cream Chef",Quest="IceCreamIslandQuest",Lv=1,CQ=Vector3.new(-820.65,65.82,-10965.8),CM=Vector3.new(-872.25,65.82,-10919.96)},
    {W=3,Min=2150,Max=2199,Mob="Ice Cream Commander",Quest="IceCreamIslandQuest",Lv=2,CQ=Vector3.new(-820.65,65.82,-10965.8),CM=Vector3.new(-558.06,112.05,-11290.77)},
    {W=3,Min=2200,Max=2224,Mob="Cookie Crafter",Quest="CakeQuest1",Lv=1,CQ=Vector3.new(-2021.32,37.8,-12028.73),CM=Vector3.new(-2374.14,37.8,-12125.31)},
    {W=3,Min=2225,Max=2249,Mob="Cake Guard",Quest="CakeQuest1",Lv=2,CQ=Vector3.new(-2021.32,37.8,-12028.73),CM=Vector3.new(-1598.31,43.77,-12244.58)},
    {W=3,Min=2250,Max=2274,Mob="Baking Staff",Quest="CakeQuest2",Lv=1,CQ=Vector3.new(-1927.92,37.8,-12842.54),CM=Vector3.new(-1887.81,77.62,-12998.35)},
    {W=3,Min=2275,Max=2299,Mob="Head Baker",Quest="CakeQuest2",Lv=2,CQ=Vector3.new(-1927.92,37.8,-12842.54),CM=Vector3.new(-2216.19,82.88,-12869.29)},
    {W=3,Min=2300,Max=2324,Mob="Cocoa Warrior",Quest="ChocQuest1",Lv=1,CQ=Vector3.new(233.23,29.88,-12201.23),CM=Vector3.new(-21.55,80.57,-12352.39)},
    {W=3,Min=2325,Max=2349,Mob="Chocolate Bar Battler",Quest="ChocQuest1",Lv=2,CQ=Vector3.new(233.23,29.88,-12201.23),CM=Vector3.new(582.59,77.19,-12463.16)},
    {W=3,Min=2350,Max=2374,Mob="Sweet Thief",Quest="ChocQuest2",Lv=1,CQ=Vector3.new(150.51,30.69,-12774.5),CM=Vector3.new(165.19,76.06,-12600.84)},
    {W=3,Min=2375,Max=2399,Mob="Candy Rebel",Quest="ChocQuest2",Lv=2,CQ=Vector3.new(150.51,30.69,-12774.5),CM=Vector3.new(134.87,77.25,-12876.55)},
    {W=3,Min=2400,Max=2424,Mob="Candy Pirate",Quest="CandyQuest1",Lv=1,CQ=Vector3.new(-1150.04,20.38,-14446.33),CM=Vector3.new(-1310.5,26.02,-14562.4)},
    {W=3,Min=2425,Max=2449,Mob="Snow Demon",Quest="CandyQuest1",Lv=2,CQ=Vector3.new(-1150.04,20.38,-14446.33),CM=Vector3.new(-880.2,71.25,-14538.61)},
    {W=3,Min=2450,Max=2474,Mob="Isle Outlaw",Quest="TikiQuest1",Lv=1,CQ=Vector3.new(-16547.75,61.14,-173.41),CM=Vector3.new(-16442.81,116.14,-264.46)},
    {W=3,Min=2475,Max=2524,Mob="Island Boy",Quest="TikiQuest1",Lv=2,CQ=Vector3.new(-16547.75,61.14,-173.41),CM=Vector3.new(-16901.26,84.07,-192.89)},
    {W=3,Min=2525,Max=2550,Mob="Isle Champion",Quest="TikiQuest2",Lv=2,CQ=Vector3.new(-16539.08,55.69,1051.57),CM=Vector3.new(-16641.68,235.78,1031.28)},
    {W=3,Min=2550,Max=2574,Mob="Serpent Hunter",Quest="TikiQuest3",Lv=1,CQ=Vector3.new(-16665.19,104.6,1579.69),CM=Vector3.new(-16521.06,106.09,1488.78)},
    {W=3,Min=2575,Max=99999,Mob="Skull Slayer",Quest="TikiQuest3",Lv=2,CQ=Vector3.new(-16665.19,104.6,1579.69),CM=Vector3.new(-16855.04,122.46,1478.15)},
}

do -- Royal Squad / Royal Soldier dùng cùng cổng với Shanda (Upper Skylands)
    local skyGate
    for _, q in ipairs(QuestDB) do
        if q.Mob == "Shanda" and q.E then skyGate = q.E end
    end
    for _, q in ipairs(QuestDB) do
        if q.Quest == "SkyExp2Quest" and not q.E then q.E = skyGate end
    end
end

local function SeaForLevel(lv)
    if lv < 700 then return 1 elseif lv < 1500 then return 2 end
    return 3
end
local SeaRemote = { [1] = "TravelMain", [2] = "TravelDressrosa", [3] = "TravelZou" }

local function PickQuest(lv)
    local best
    for _, q in ipairs(QuestDB) do
        if q.W == WORLD and lv >= q.Min and (not best or q.Min > best.Min) then best = q end
    end
    if not best then
        for _, q in ipairs(QuestDB) do
            if q.W == WORLD then
                best = q
                break
            end
        end
    end
    return best
end

-- [SỬA] Không còn phụ thuộc vào chữ tiếng Anh trên bảng quest (client tiếng Việt khiến so khớp tên quái
-- thất bại → bị coi là "quest sai" và bị hủy liên tục). Nhớ quest mình đã nhận bằng QuestKey.
local function QuestKey(q) return q.Quest .. ":" .. q.Lv end

local function QuestState(q)
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = gui and gui:FindFirstChild("Main")
    local frame = main and main:FindFirstChild("Quest")
    if not frame or not frame.Visible then
        S.QuestKey = nil
        return "none"
    end
    local ok, text = pcall(function() return frame.Container.QuestTitle.Title.Text end)
    if ok and type(text) == "string" and string.find(text, q.Mob, 1, true) then return "ok" end
    local ok2, ctext = pcall(function() return frame.Container.QuestTitle.Title.ContentText end)
    if ok2 and type(ctext) == "string" and string.find(ctext, q.Mob, 1, true) then return "ok" end
    if S.QuestKey == QuestKey(q) then return "ok" end
    return "other"
end

-- ════════════════════════════ MOVEMENT / NOCLIP / SIM RADIUS ════════════════════════════
-- [SỬA] Giữ nhân vật đứng yên trên không: BodyVelocity = 0 + triệt tiêu vận tốc thẳng/góc mỗi frame.
-- Trước đây khi Move bật/tắt nhân vật bị trôi theo quán tính hoặc rơi tự do.
local function SetHold(root, on)
    local hold = root:FindFirstChild("LuciferHold")
    if on and not hold then
        hold = Instance.new("BodyVelocity")
        hold.Name = "LuciferHold"
        hold.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        hold.Velocity = Vector3.zero
        hold.Parent = root
    elseif not on and hold then
        hold:Destroy()
    end
end

Track(RunService.Heartbeat:Connect(function(dt)
    local root = GetRoot(LocalPlayer.Character)
    if not root then return end
    if not Move.Active or not Move.Pos then
        SetHold(root, false)
        return
    end
    SetHold(root, true)
    local cur = root.Position
    local delta = Move.Pos - cur
    local dist = delta.Magnitude
    local step = Cfg.Speed * dt
    local newPos = Move.Pos
    if dist > step and dist > 0 then newPos = cur + delta.Unit * step end
    -- [SỬA] quay mặt về cụm quái (hitbox đòn đánh nằm phía trước nhân vật)
    local rot = root.CFrame.Rotation
    if Move.Face and (Move.Face - newPos).Magnitude > 1 then
        rot = CFrame.lookAt(newPos, Move.Face).Rotation
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = CFrame.new(newPos) * rot
end))

Track(RunService.Stepped:Connect(function()
    if not (Move.Active and Cfg.NoClip) then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end))

-- [SỬA] Chỉ mở SimulationRadius khi đang farm + gom quái (không bật vô điều kiện nữa)
task.spawn(function()
    while S.Running do
        if sethiddenproperty and Cfg.AutoFarm and Cfg.Bring and not S.Paused then
            pcall(sethiddenproperty, LocalPlayer, "SimulationRadius", math.huge)
        end
        task.wait(1)
    end
end)

Track(LocalPlayer.CharacterAdded:Connect(function()
    S.Target = nil
    S.Anchor = nil
    S.Attacking = false
    table.clear(BringSet)
end))

-- ════════════════════════════ MOB / COMBAT ════════════════════════════
local ATTACK_RANGE = 60       -- tầm lọc mục tiêu đánh / gửi hit
local BRING_RADIUS = 120      -- [SỬA] chỉ gom quái nằm quanh S.Anchor trong bán kính này
local BRING_MAX = 18          -- số quái gom tối đa
local BRING_OWN_DIST = 350    -- xa hơn mức này người chơi không còn quyền mô phỏng quái
local HOVER_OFFSET = 5        -- lệch ngang để nhân vật nhìn chéo xuống cụm quái

local function FindNearestMob(name, fromPos)
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end
    local best, bestD = nil, math.huge
    for _, mob in ipairs(enemies:GetChildren()) do
        if mob.Name == name and Alive(mob) then
            local r = GetRoot(mob)
            if r then
                local d = (r.Position - fromPos).Magnitude
                if d < bestD then best, bestD = mob, d end
            end
        end
    end
    return best
end

-- Kiểm tra mình có quyền mô phỏng physics quái không (nếu không thì CFrame không đồng bộ lên server)
local function InMyNetwork(part)
    if isnetworkowner then
        local ok, res = pcall(isnetworkowner, part)
        if ok then return res end
    end
    local root = GetRoot(LocalPlayer.Character)
    return root ~= nil and (part.Position - root.Position).Magnitude <= BRING_OWN_DIST
end

-- Chuẩn bị quái 1 lần: tắt va chạm MỌI part (chống đẩy/văng nhau), khoá di chuyển
local function PrepareMob(mob, r, h)
    local info = Prepared[mob]
    if info then return info end
    local parts = {}
    for _, p in ipairs(mob:GetDescendants()) do
        if p:IsA("BasePart") then
            parts[#parts + 1] = p
            p.CanCollide = false
        end
    end
    pcall(function()
        h.WalkSpeed = 0
        h.JumpPower = 0
        h.JumpHeight = 0
    end)
    info = { parts = parts, root = r, hum = h }
    Prepared[mob] = info
    return info
end

-- [SỬA] Hitbox lớn là tuỳ chọn (mặc định TẮT, size 24 thay vì 40) và cần sethiddenproperty
local function ApplyHitbox(info)
    if Cfg.BigHitbox and sethiddenproperty then
        if not info.size0 then info.size0 = info.root.Size end
        info.root.Size = Vector3.new(24, 24, 24)
    elseif info.size0 then
        pcall(function() info.root.Size = info.size0 end)
        info.size0 = nil
    end
end

RestoreHitboxes = function()
    for _, info in pairs(Prepared) do
        if info.size0 and info.root and info.root.Parent then
            pcall(function() info.root.Size = info.size0 end)
            info.size0 = nil
        end
    end
end

-- Chọn tập quái cần ghim: đúng tên quest, còn sống, có root + humanoid, nằm quanh S.Anchor
local function RefreshBringSet(name, anchor)
    table.clear(BringSet)
    S.BringCount, S.BringOwned = 0, 0
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return end
    for _, mob in ipairs(enemies:GetChildren()) do
        if S.BringCount >= BRING_MAX then break end
        if mob.Name == name and Alive(mob) then
            local r, h = GetRoot(mob), GetHum(mob)
            if r and h and (r.Position - anchor).Magnitude <= BRING_RADIUS then
                local info = PrepareMob(mob, r, h)
                if h.WalkSpeed ~= 0 then h.WalkSpeed = 0 end
                ApplyHitbox(info)
                BringSet[mob] = info
                S.BringCount = S.BringCount + 1
                if InMyNetwork(r) then S.BringOwned = S.BringOwned + 1 end
            end
        end
    end
end

-- [SỬA] Ghim quái MỖI FRAME (Heartbeat) về đúng 1 điểm S.Anchor, thẳng đứng, vận tốc = 0.
-- Trước đây gán CFrame theo lưới mỗi 0.1s nên quái bị server kéo lại / trượt / bay loạn giữa các lần gán.
Track(RunService.Heartbeat:Connect(function()
    if S.Paused or not (Cfg.AutoFarm and Cfg.Bring) or not S.Anchor then return end
    local root = GetRoot(LocalPlayer.Character)
    if not root or (root.Position - S.Anchor).Magnitude > BRING_OWN_DIST then return end
    local cf = CFrame.new(S.Anchor)
    for mob, info in pairs(BringSet) do
        local r = info.root
        if r and r.Parent and mob.Parent and info.hum.Health > 0 then
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            r.CFrame = cf
        else
            BringSet[mob] = nil
        end
    end
end))

-- Giữ va chạm của quái được gom luôn tắt (Humanoid hay tự bật lại CanCollide mỗi bước physics)
Track(RunService.Stepped:Connect(function()
    for _, info in pairs(BringSet) do
        for _, p in ipairs(info.parts) do
            if p.CanCollide then p.CanCollide = false end
        end
    end
end))

-- [SỬA] Chỉ lấy quái ĐÚNG TÊN quest hiện tại, còn sống, có root/head hợp lệ, trong tầm đánh; gần nhất xếp trước
local function GetHitTargets(root, range)
    local list, dist = {}, {}
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return list end
    local name = S.QuestMob
    for _, mob in ipairs(enemies:GetChildren()) do
        if (not name or mob.Name == name) and Alive(mob) then
            local r = GetRoot(mob)
            local part = mob:FindFirstChild("Head") or r
            if r and part then
                local d = (r.Position - root.Position).Magnitude
                if d <= range then
                    list[#list + 1] = mob
                    dist[mob] = d
                end
            end
        end
    end
    table.sort(list, function(a, b) return dist[a] < dist[b] end)
    for i = #list, 16, -1 do list[i] = nil end
    return list
end

-- ── Học gói đánh thật của game (hook __namecall) ──
-- [CẬP NHẬT] RegisterHit bản hiện hành cần tham số hợp lệ (mã phiên / hitId) — gửi tay thiếu mã thì server
-- bỏ qua im lặng (đây là lý do chính khiến Fast Attack cũ không gây sát thương).
-- Cách bền nhất theo các hub hiện nay: bắt lại lời gọi RegisterHit THẬT của game rồi phát lại với mục tiêu của mình.
local Cap = env.LuciferBFCap
if not Cap then
    Cap = { on = false, installed = false, hookOk = nil, hit = nil, atk = nil, hitAt = 0, atkAt = 0 }
    env.LuciferBFCap = Cap
end
Cap.RegisterHit, Cap.RegisterAttack = RegisterHit, RegisterAttack
Cap.hit, Cap.atk, Cap.hitAt, Cap.atkAt = nil, nil, 0, 0   -- bản chạy mới: học lại từ đầu

local function InstallHook()
    if Cap.installed then return end
    if not (hookmetamethod and getnamecallmethod) then
        Cap.hookOk = false
        return
    end
    local ok = pcall(function()
        local old
        local function handler(self, ...)
            local method = getnamecallmethod()
            if Cap.on and method == "FireServer" and (self == Cap.RegisterHit or self == Cap.RegisterAttack) then
                if not (checkcaller and checkcaller()) then -- chỉ ghi lời gọi của game, không ghi lời gọi của mình
                    if self == Cap.RegisterHit then
                        Cap.hit = table.pack(...)
                        Cap.hitAt = os.clock()
                    else
                        Cap.atk = table.pack(...)
                        Cap.atkAt = os.clock()
                    end
                end
            end
            return old(self, ...)
        end
        old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(handler) or handler)
    end)
    Cap.installed = ok
    Cap.hookOk = ok
end

local function DescribeArg(v)
    local t = typeof(v)
    if t == "Instance" then return v.ClassName .. ":" .. v.Name end
    if t == "table" then return "table(" .. #v .. ")" end
    if t == "string" then return "str(" .. #v .. ")" end
    return t
end

local function CapSummary()
    local cap = Cap.hit
    if not cap then return "—" end
    local parts = {}
    for i = 1, cap.n do parts[i] = DescribeArg(cap[i]) end
    return table.concat(parts, " | ")
end

local function HookLine()
    if not Cfg.CaptureHook then return "Hook: tắt" end
    if Cap.hookOk == false then return "Hook: executor không hỗ trợ (không học được gói thật)" end
    if Cap.hit then
        return string.format("Gói thật (%.0fs trước): %s", os.clock() - Cap.hitAt, CapSummary())
    end
    return "Hook: chờ gói đánh thật — hãy tự đánh 1 con quái bằng tay một lần"
end

-- ── Vũ khí ──
local WEAPON_VN = { Melee = "Võ", Sword = "Kiếm", Gun = "Súng", ["Blox Fruit"] = "Trái" }

local function WeaponMatches(tool, wtype)
    local tip = tool.ToolTip
    if wtype == "Melee" then return tip == "Melee" or tool.Name == "Combat" end
    -- Trái: chỉ lấy sức mạnh trái đã ăn; trái vật lý (tên có "Fruit" / có EatRemote) KHÔNG BAO GIỜ là vũ khí
    if wtype == "Blox Fruit" then
        return tip == "Blox Fruit" and not string.find(tool.Name, "Fruit") and not tool:FindFirstChild("EatRemote")
    end
    return tip == wtype
end

local function FindWeapon(wtype)
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and WeaponMatches(t, wtype) then return t end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and WeaponMatches(t, wtype) then return t end
        end
    end
    return nil
end

-- [CẬP NHẬT] Trang bị đúng vũ khí; chỉ trả về tool khi đã nằm trong Character VÀ đã "sẵn sàng" 0.25s.
-- Thiếu vũ khí đã chọn → tự dùng loại khác (Võ → Kiếm → Súng → Trái); người mới chỉ có Combat vẫn chạy được.
local function EnsureWeapon()
    local char = LocalPlayer.Character
    local hum = GetHum(char)
    if not char or not hum then return nil end
    local want = Cfg.Weapon
    local tool = FindWeapon(want)
    local fallback = false
    if not tool then
        for _, w in ipairs({ "Melee", "Sword", "Gun", "Blox Fruit" }) do
            if w ~= want then
                tool = FindWeapon(w)
                if tool then
                    fallback = true
                    break
                end
            end
        end
    end
    if not tool then
        S.WeaponMissing = true
        S.EquipNote = "Không có vũ khí nào để equip"
        return nil
    end
    S.WeaponMissing = fallback
    S.EquipNote = fallback and ("Thiếu " .. (WEAPON_VN[want] or want) .. " → đang dùng " .. tool.Name) or ""
    if tool.Parent ~= char then
        if os.clock() - S.LastEquip > 0.35 then
            S.LastEquip = os.clock()
            pcall(function() hum:EquipTool(tool) end)
        end
        S.LastToolInst = nil
        S.EquipNote = "Đang equip " .. tool.Name
        return nil
    end
    if S.LastToolInst ~= tool then -- vừa cầm xong: đợi tool khởi tạo script rồi mới ra đòn
        S.LastToolInst = tool
        S.ToolReadyAt = os.clock() + 0.25
    end
    if os.clock() < S.ToolReadyAt then
        S.EquipNote = "Vừa cầm " .. tool.Name .. ", chuẩn bị..."
        return nil
    end
    return tool
end

local function UpdateHaki()
    if not Cfg.Haki then return end
    local char = LocalPlayer.Character
    if not char or char:FindFirstChild("HasBuso") then return end
    if os.clock() - S.LastHaki < 3 then return end
    S.LastHaki = os.clock()
    Invoke("Buso")
end

-- ── Skill Z/X/C/V: chỉ khi UseSkills bật + ô skill tồn tại, mỗi phím có hồi riêng (không spam đòn thường) ──
local SkillKeys = { "Z", "X", "C", "V" }
local SkillCD = { Z = 3.5, X = 4.5, C = 5.5, V = 6.5 }

local function SkillAvailable(tool, key)
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = gui and gui:FindFirstChild("Main")
    local skills = main and main:FindFirstChild("Skills")
    if not skills then return true end -- không đọc được GUI skill → vẫn cho dùng theo nhịp
    local holder = skills:FindFirstChild(tool.Name)
    local slot = holder and holder:FindFirstChild(key)
    if not slot then return false end
    local ok, visible = pcall(function() return slot.Visible end)
    return ok and visible ~= false
end

local function PressKey(name)
    if not VIM then return end
    pcall(function()
        local k = Enum.KeyCode[name]
        VIM:SendKeyEvent(true, k, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, k, false, game)
    end)
end

-- ── Input đánh thường ──
-- Điểm bấm không rơi vào menu Lucifer; Súng/Trái bấm đúng vị trí quái trên màn hình
local function ClickPoint(aimPos)
    local c = Cam()
    local v = c and c.ViewportSize or Vector2.new(800, 400)
    local pt
    if aimPos and c then
        local sp, onScreen = c:WorldToViewportPoint(aimPos)
        if onScreen and sp.Z > 0 then pt = Vector2.new(sp.X, sp.Y) end
    end
    pt = pt or Vector2.new(v.X * 0.72, v.Y * 0.32)
    local m = UIMain
    if m and m.Visible then
        local p, s = m.AbsolutePosition, m.AbsoluteSize
        if pt.X >= p.X - 4 and pt.X <= p.X + s.X + 4 and pt.Y >= p.Y - 4 and pt.Y <= p.Y + s.Y + 4 then
            pt = Vector2.new(math.min(v.X - 40, p.X + s.X + 40), v.Y * 0.32)
        end
    end
    return pt
end

local function ClickVU(pt)
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton1(pt)
    end)
end

local function ClickVIM(pt)
    if not VIM then return end
    pcall(function()
        local inset = GuiService:GetGuiInset()
        VIM:SendMouseButtonEvent(pt.X, pt.Y + inset.Y, 0, true, game, 1)
        VIM:SendMouseButtonEvent(pt.X, pt.Y + inset.Y, 0, false, game, 1)
    end)
end

-- [MỚI] Chạm màn hình thật (mobile): Tool.Activated trên điện thoại đến từ touch tap
local function TouchVIM(pt)
    if not VIM then return end
    pcall(function()
        local inset = GuiService:GetGuiInset()
        VIM:SendTouchEvent(9, 0, pt.X, pt.Y + inset.Y)
        VIM:SendTouchEvent(9, 2, pt.X, pt.Y + inset.Y)
    end)
end

-- [MỚI] Trái: đòn thường của trái gửi qua tool.LeftClickRemote (hướng, 1)
local function FruitClick(tool, aimPos, root)
    local rem = tool:FindFirstChild("LeftClickRemote")
    if rem and aimPos and root then
        local d = aimPos - root.Position
        if d.Magnitude > 0.1 then pcall(function() rem:FireServer(d.Unit, 1) end) end
    end
end

-- ── Các đường gửi sát thương qua Net ──
local function PickPart(mob, preferName)
    return (preferName and mob:FindFirstChild(preferName)) or mob:FindFirstChild("Head") or GetRoot(mob)
end

-- 1) Phát lại gói RegisterHit THẬT đã bắt được: giữ nguyên mọi tham số (kể cả mã phiên), chỉ thay mục tiêu
local function NetReplay(targets)
    local cap = Cap.hit
    if not cap or not RegisterHit then return false end
    pcall(function()
        local atk = Cap.atk
        if RegisterAttack then
            if atk then RegisterAttack:FireServer(table.unpack(atk, 1, atk.n)) else RegisterAttack:FireServer(0.5) end
        end
    end)
    local pname = (typeof(cap[1]) == "Instance") and cap[1].Name or nil
    local sample = cap[2]
    local mode = "empty"
    if type(sample) == "table" and sample[1] ~= nil then
        mode = (type(sample[1]) == "table") and "pairs" or "flat"
    end
    local n = math.max(cap.n, 2)
    local sent = 0
    if mode == "empty" then
        for _, mob in ipairs(targets) do
            local part = PickPart(mob, pname)
            if part then
                local args = table.pack(table.unpack(cap, 1, cap.n))
                args.n = n
                args[1] = part
                args[2] = {}
                pcall(function() RegisterHit:FireServer(table.unpack(args, 1, n)) end)
                sent = sent + 1
                if sent >= 4 then break end
            end
        end
    else
        local list = {}
        for _, mob in ipairs(targets) do
            local part = PickPart(mob, pname)
            if part then list[#list + 1] = (mode == "pairs") and { mob, part } or part end
        end
        if #list > 0 then
            local args = table.pack(table.unpack(cap, 1, cap.n))
            args.n = n
            args[1] = (mode == "pairs") and list[1][2] or list[1]
            args[2] = list
            pcall(function() RegisterHit:FireServer(table.unpack(args, 1, n)) end)
            sent = 1
        end
    end
    return sent > 0
end

-- 2) Mã phiên tự tính theo mẫu hub công khai: UserId[2..4] .. tostring(thread combat)[11..15]
local function GetSessionID()
    if S.SessionAt and os.clock() - S.SessionAt < 3 then return S.SessionCache end
    S.SessionAt = os.clock()
    local ok, id = pcall(function()
        local send = getrenv()._G.SendHitsToServer
        local thread = getupvalues(send)[1]
        return tostring(LocalPlayer.UserId):sub(2, 4) .. tostring(thread):sub(11, 15)
    end)
    S.SessionCache = (ok and type(id) == "string") and id or nil
    return S.SessionCache
end

local function NetSession(targets)
    local id = GetSessionID()
    if not id or not (RegisterAttack and RegisterHit) then return false end
    pcall(function() RegisterAttack:FireServer(0.5) end)
    task.wait()
    local sent = 0
    for _, mob in ipairs(targets) do
        local part = mob:FindFirstChild("RightLowerLeg") or PickPart(mob)
        if part then
            pcall(function() RegisterHit:FireServer(part, {}, nil, id) end)
            sent = sent + 1
            if sent >= 4 then break end
        end
    end
    return sent > 0
end

-- 3) Hàm gửi đòn của chính game (_G.SendHitsToServer) nếu executor đọc được
local function GameSender()
    local ok, fn = pcall(function() return getrenv()._G.SendHitsToServer end)
    if ok and type(fn) == "function" then return fn end
    return nil
end

local function NetGameFn(targets)
    local fn = GameSender()
    if not fn then return false end
    local list = {}
    for _, mob in ipairs(targets) do
        local part = PickPart(mob)
        if part then list[#list + 1] = { mob, part } end
    end
    if #list == 0 then return false end
    pcall(fn, list[1][2], list)
    return true
end

-- 4) Dạng cũ (cấu trúc đoán): giữ làm phương án cuối
local function NetAttack(targets, mode)
    if not (RegisterAttack and RegisterHit) then return end
    local pairsList, flat = {}, {}
    for _, mob in ipairs(targets) do
        local part = PickPart(mob)
        if part then
            pairsList[#pairsList + 1] = { mob, part }
            flat[#flat + 1] = part
        end
    end
    if #flat == 0 then return end
    pcall(function() RegisterAttack:FireServer(0) end)
    if mode == "pairs" then
        pcall(function() RegisterHit:FireServer(flat[1], pairsList) end)
    else
        pcall(function() RegisterHit:FireServer(flat[1], flat) end)
    end
end

-- ── Phát hiện sát thương: máu quái giảm → đang đánh trúng ──
local HpTrack = setmetatable({}, { __mode = "k" })
local function CheckDamage(targets)
    for _, mob in ipairs(targets) do
        local h = GetHum(mob)
        if h then
            local prev = HpTrack[mob]
            if prev and h.Health < prev - 0.01 then
                S.LastDamageAt = os.clock()
                S.ProfStat[S.ProfName] = "✓"
            end
            HpTrack[mob] = h.Health
        end
    end
end

-- ── Hình học đứng đánh: nếu mọi cách đều không tụt máu thì HẠ THẤP dần (đòn đánh thường có tầm ngắn) ──
local GEO = { 1, 0.5, 0.25 }
local PROFILE_TIME = 2.5

local function EffHover()
    local scale = GEO[S.GeoStep] or 1
    local capH = (Cfg.Weapon == "Melee" or Cfg.Weapon == "Sword") and 10 or 25 -- Võ/Kiếm không đứng quá cao
    local h = math.max(2, math.min(Cfg.Height, capH) * scale)
    local off = math.max(1, HOVER_OFFSET * scale)
    return h, off
end

-- Các "cách đánh": PROFILE_TIME giây không thấy máu quái giảm thì tự chuyển sang cách kế tiếp
local AtkProfiles = {
    { name = "Click" },
    { name = "Replay", replay = true },
    { name = "Session", session = true },
    { name = "GameFn", gamefn = true },
    { name = "NetCu", net = "pairs" },
    { name = "VIM", vim = true },
}

local function ProfileAvailable(p)
    local isNet = p.replay or p.session or p.gamefn or p.net
    if isNet and not Cfg.FastAttack then return false end
    if p.replay then return Cap.hit ~= nil and RegisterHit ~= nil end
    if p.session then return RegisterHit ~= nil and RegisterAttack ~= nil and GetSessionID() ~= nil end
    if p.gamefn then return GameSender() ~= nil end
    if p.net then return RegisterHit ~= nil and RegisterAttack ~= nil end
    return true
end

local function ActiveProfiles()
    local list = {}
    for _, p in ipairs(AtkProfiles) do
        if ProfileAvailable(p) then list[#list + 1] = p end
    end
    return list
end

local function CurrentProfile(profiles)
    for _, p in ipairs(profiles) do
        if p.name == S.ProfName then return p end
    end
    S.ProfName = profiles[1].name
    return profiles[1]
end

local function RotateProfile(profiles)
    if S.ProfStat[S.ProfName] ~= "✓" then S.ProfStat[S.ProfName] = "✗" end
    local idx = 1
    for i, p in ipairs(profiles) do
        if p.name == S.ProfName then
            idx = i
            break
        end
    end
    local nextIdx = idx % #profiles + 1
    if nextIdx == 1 then
        -- đã thử hết các cách ở độ cao này mà vẫn không tụt máu → hạ thấp / lại gần cụm quái hơn
        S.GeoStep = S.GeoStep % #GEO + 1
        S.ProfStat = {}
    end
    S.ProfName = profiles[nextIdx].name
    S.ProfileSince = os.clock()
end

-- Vòng lặp đánh quái
Loop(0.1, function()
    if not (Cfg.AutoFarm and S.Attacking) or S.Paused then
        S.WasAttacking = false
        return
    end
    local char = LocalPlayer.Character
    local root = GetRoot(char)
    if not root then return end

    -- 1) đảm bảo đã cầm đúng vũ khí (Parent == Character, đã sẵn sàng) rồi mới đánh
    local tool = EnsureWeapon()
    if not tool then
        S.AtkNote = S.EquipNote ~= "" and S.EquipNote or "Chưa có vũ khí"
        return
    end

    -- 2) mục tiêu hợp lệ trong tầm
    local targets = GetHitTargets(root, ATTACK_RANGE)
    if #targets == 0 then
        S.AtkNote = "Chưa có " .. tostring(S.QuestMob) .. " trong tầm " .. ATTACK_RANGE .. " (đứng ngoài tầm đánh?)"
        return
    end

    local now = os.clock()
    local profiles = ActiveProfiles()
    if not S.WasAttacking then
        S.WasAttacking = true
        S.LastDamageAt = now
        S.ProfileSince = now
    end
    -- vừa học được gói thật của game mà chưa có dame → thử Replay ngay
    if Cap.hitAt > S.LastCapSeen then
        S.LastCapSeen = Cap.hitAt
        if not S.CapPrinted then
            S.CapPrinted = true
            print("[Lucifer] Gói RegisterHit thật: " .. CapSummary())
            Toast("Đã học được gói đánh thật của game")
        end
        if now - S.LastDamageAt > 1.5 then
            S.ProfName = "Replay"
            S.ProfileSince = now
        end
    end
    if now - S.LastDamageAt > PROFILE_TIME and now - S.ProfileSince > PROFILE_TIME then
        RotateProfile(profiles)
    end
    local prof = CurrentProfile(profiles)

    -- 3) ngắm (Súng / Trái cần chuột trỏ vào quái)
    local first = targets[1]
    local fr = GetRoot(first)
    local aimPos = fr and fr.Position or S.Anchor
    local aimed = (Cfg.Weapon == "Gun" or Cfg.Weapon == "Blox Fruit") and aimPos ~= nil
    if aimed then
        local c = Cam()
        if c then
            local _, onScreen = c:WorldToViewportPoint(aimPos)
            if not onScreen then c.CFrame = CFrame.lookAt(c.CFrame.Position, aimPos) end
        end
    end
    local pt = ClickPoint(aimed and aimPos or nil)

    -- 4) kích hoạt tool + input đánh thường
    pcall(function() tool:Activate() end)
    if tool.ToolTip == "Blox Fruit" then FruitClick(tool, aimPos, root) end
    if prof.vim then
        ClickVIM(pt)
        TouchVIM(pt)
    else
        ClickVU(pt)
    end

    -- 5) gửi sát thương qua Net theo cách đang thử
    if prof.replay then NetReplay(targets)
    elseif prof.session then NetSession(targets)
    elseif prof.gamefn then NetGameFn(targets)
    elseif prof.net then NetAttack(targets, prof.net) end

    -- 6) skill (chỉ chế độ Trái + UseSkills): mỗi lượt 1 phím, theo hồi riêng
    if Cfg.Weapon == "Blox Fruit" and Cfg.UseSkills then
        for _, key in ipairs(SkillKeys) do
            if (S.SkillNext[key] or 0) <= os.clock() and SkillAvailable(tool, key) then
                S.SkillNext[key] = os.clock() + SkillCD[key]
                PressKey(key)
                break
            end
        end
    end

    -- 7) chẩn đoán
    CheckDamage(targets)
    local h = GetHum(first)
    local hp = h and math.floor(h.Health) or 0
    local maxhp = h and math.floor(h.MaxHealth) or 0
    S.LastDist = fr and (root.Position - fr.Position).Magnitude or 0
    S.AtkNote = string.format("[%s] %s HP %d/%d • %d mục tiêu", prof.name, first.Name, hp, maxhp, #targets)
end)

-- Bảng chẩn đoán chi tiết cho DiagInfo (cập nhật độc lập với vòng đánh)
Loop(0.4, function()
    if not Cfg.AutoFarm then
        S.AtkDetail = ""
        return
    end
    local lines = {}
    if S.WasAttacking then
        local since = os.clock() - S.LastDamageAt
        local effH = EffHover()
        local dmg = (since < 1.5) and "Dame: máu quái ĐANG GIẢM ✓" or string.format("Dame: chưa thấy tụt máu (%.1fs)", since)
        lines[#lines + 1] = string.format("%s • cách quái %.1fm • cao≈%.1f", dmg, S.LastDist, effH)
        local stat = {}
        for _, p in ipairs(ActiveProfiles()) do stat[#stat + 1] = p.name .. (S.ProfStat[p.name] or "") end
        lines[#lines + 1] = "Cách đánh: " .. table.concat(stat, " ")
    end
    lines[#lines + 1] = HookLine()
    lines[#lines + 1] = "Net: Attack " .. (RegisterAttack and "✓" or "✗") .. " Hit " .. (RegisterHit and "✓" or "✗") .. " • " .. #NetNames .. " remote"
    S.AtkDetail = table.concat(lines, "\n")
end)

-- Phát hiện banner Safe Zone trên GUI (chỉ để báo trong chẩn đoán)
Loop(2, function()
    if not Cfg.AutoFarm then
        S.InSafeZone = false
        return
    end
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = gui and gui:FindFirstChild("Main")
    if not main then return end
    local found = false
    for _, d in ipairs(main:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" and (string.find(d.Text, "Safe Zone", 1, true) or string.find(d.Text, "An Toàn", 1, true)) then
            local vis = true
            local o = d
            while o and o ~= main.Parent do
                if o:IsA("GuiObject") and not o.Visible then
                    vis = false
                    break
                end
                o = o.Parent
            end
            if vis then
                found = true
                break
            end
        end
    end
    S.InSafeZone = found
end)

-- ════════════════════════════ AUTO FARM LEVEL ════════════════════════════
local function StopFarm()
    S.FarmOn = false
    S.Attacking = false
    S.Target = nil
    S.Anchor = nil
    S.QuestMob = nil
    S.AtkNote = ""
    S.EquipNote = ""
    S.BringCount, S.BringOwned = 0, 0
    S.QuestInfo = "Chưa bật Auto Farm"
    table.clear(BringSet)
    RestoreHitboxes()
    Move.Face = nil
    S.GeoStep, S.ProfName, S.ProfStat, S.AtkDetail = 1, "Click", {}, ""
    if not S.Paused then Move.Active = false end
    SetStatus("Tắt")
end

local function GoTo(pos)
    Move.Pos = pos
    Move.Active = true
end

-- Đảo quá xa (>10000 stud) → dùng cổng dịch chuyển của game
local function FarEntrance(root, pos, q)
    if q.E and (root.Position - pos).Magnitude > 10000 and os.clock() - S.LastEntrance > 6 then
        S.LastEntrance = os.clock()
        SetStatus("Đang dịch chuyển tới đảo...")
        InvokeSync("requestEntrance", q.E)
        task.wait(1.5)
        return true
    end
    return false
end

local function FarmTick()
    if S.Paused then return end
    if not Cfg.AutoFarm then
        if S.FarmOn then StopFarm() end
        return
    end
    S.FarmOn = true
    Cap.on = Cfg.CaptureHook
    if Cfg.CaptureHook and Cap.hookOk == nil then InstallHook() end

    local char = LocalPlayer.Character
    local root, hum = GetRoot(char), GetHum(char)
    if not root or not hum or hum.Health <= 0 then
        S.Attacking = false
        S.Target = nil
        table.clear(BringSet)
        Move.Active = false
        Move.Face = nil
        SetStatus("Đang hồi sinh...")
        return
    end

    local lv = GetLevel()
    local want = SeaForLevel(lv)
    if want ~= WORLD and Cfg.AutoSea then
        if os.clock() - S.LastTravel > 25 then
            S.LastTravel = os.clock()
            SetStatus("Lv " .. lv .. " → qua Sea " .. want .. "...")
            Invoke(SeaRemote[want])
            task.wait(3)
        end
        return
    end

    local q = PickQuest(lv)
    if not q then
        SetStatus("Không có quest cho Sea này")
        return
    end
    S.QuestMob = q.Mob
    S.QuestInfo = string.format("Sea %d • Lv %s • %s (%s-%s)", WORLD, tostring(lv), q.Mob, tostring(q.Min), q.Max >= 99999 and "∞" or tostring(q.Max))

    EnsureWeapon()
    UpdateHaki()

    if os.clock() - S.QuestFailAt > 20 then S.QuestFail = 0 end
    local state = QuestState(q)

    -- quest sai (đã lên level) → bỏ quest cũ
    if state == "other" then
        S.Attacking = false
        Move.Face = nil
        if os.clock() - S.LastAbandon > 2 then
            S.LastAbandon = os.clock()
            InvokeSync("AbandonQuest")
            S.QuestKey = nil
        end
        return
    end

    -- chưa có quest → bay tới NPC nhận
    if state == "none" and S.QuestFail < 4 then
        S.Attacking = false
        S.Target = nil
        S.Anchor = nil
        Move.Face = nil
        table.clear(BringSet)
        S.BringCount, S.BringOwned = 0, 0
        if FarEntrance(root, q.CQ, q) then return end
        GoTo(q.CQ + Vector3.new(0, 4, 0))
        SetStatus("Đi nhận quest: " .. q.Quest)
        S.AtkNote = "Đang đi nhận quest " .. q.Quest
        if (root.Position - q.CQ).Magnitude <= 20 and os.clock() - S.LastQuest > 1.5 then
            S.LastQuest = os.clock()
            S.QuestFail = S.QuestFail + 1
            S.QuestFailAt = os.clock()
            InvokeSync("StartQuest", q.Quest, q.Lv)
            S.QuestKey = QuestKey(q)
            task.wait(0.4)
        end
        return
    end
    if state == "ok" then S.QuestFail = 0 end

    -- đang có quest → farm quái
    local target = S.Target
    if not target or not target.Parent or not Alive(target) then
        if target then S.LastDamageAt = os.clock() end -- vừa hạ 1 con → tính là có sát thương
        target = FindNearestMob(q.Mob, root.Position)
        S.Target = target
        if target then
            local tr = GetRoot(target)
            if tr and (not S.Anchor or (tr.Position - S.Anchor).Magnitude > 40) then
                S.Anchor = tr.Position
            end
        end
    end

    if target then
        local tr = GetRoot(target)
        if tr and not Cfg.Bring then S.Anchor = tr.Position end
        if not S.Anchor then S.Anchor = tr and tr.Position or q.CM end
        if FarEntrance(root, S.Anchor, q) then return end

        -- [SỬA] điểm lơ lửng cố định phía trên-chéo cụm quái, nhân vật quay mặt vào cụm quái
        local effH, effOff = EffHover() -- [CẬP NHẬT] độ cao hiệu dụng (tự hạ thấp nếu không gây dame)
        local hover = S.Anchor + Vector3.new(0, effH, effOff)
        local dHover = (root.Position - hover).Magnitude
        GoTo(hover)
        Move.Face = (dHover < 60) and S.Anchor or nil

        -- chỉ gom khi mình còn trong vùng sở hữu physics của quái
        if Cfg.Bring and (root.Position - S.Anchor).Magnitude <= BRING_OWN_DIST then
            RefreshBringSet(q.Mob, S.Anchor)
        else
            table.clear(BringSet)
            S.BringCount, S.BringOwned = 0, 0
        end

        S.Attacking = dHover < 25
        if S.Attacking then
            SetStatus("Farm " .. q.Mob .. " • " .. S.AtkNote)
        else
            local note = "Bay tới " .. q.Mob .. " (" .. math.floor(dHover) .. "m)"
            S.AtkNote = note
            SetStatus(note)
        end
    else
        S.Target = nil
        S.Anchor = nil
        S.Attacking = false
        Move.Face = nil
        table.clear(BringSet)
        S.BringCount, S.BringOwned = 0, 0
        if FarEntrance(root, q.CM, q) then return end
        GoTo(q.CM + Vector3.new(0, 20, 0))
        S.AtkNote = "Chờ " .. q.Mob .. " xuất hiện"
        SetStatus("Chờ " .. q.Mob .. " xuất hiện...")
    end
end

Loop(0.1, FarmTick)

-- ════════════════════════════ FRUIT ════════════════════════════
local function GetFruits()
    local list = {}
    for _, inst in ipairs(Workspace:GetChildren()) do
        if string.find(inst.Name, "Fruit") and not Players:GetPlayerFromCharacter(inst) then
            local h = inst:FindFirstChild("Handle")
            if h and h:IsA("BasePart") then list[#list + 1] = inst end
        end
    end
    return list
end

local FruitSkip = {}
local function NearestFruit(fromPos)
    local best, bestD = nil, math.huge
    for _, f in ipairs(GetFruits()) do
        if not FruitSkip[f] or FruitSkip[f] < os.clock() then
            local d = (f.Handle.Position - fromPos).Magnitude
            if d < bestD then best, bestD = f, d end
        end
    end
    return best
end

-- ESP
Loop(0.5, function()
    local fruits = GetFruits()
    S.FruitCount = #fruits
    local seen = {}
    if Cfg.FruitESP then
        local root = GetRoot(LocalPlayer.Character)
        for _, f in ipairs(fruits) do
            local h = f:FindFirstChild("Handle")
            if h then
                seen[h] = true
                local bb = ESP[h]
                if not bb or not bb.Parent then
                    bb = Instance.new("BillboardGui")
                    bb.Name = "LuciferESP"
                    bb.Adornee = h
                    bb.AlwaysOnTop = true
                    bb.Size = UDim2.fromOffset(150, 40)
                    bb.StudsOffset = Vector3.new(0, 3, 0)
                    local lbl = Instance.new("TextLabel")
                    lbl.Name = "L"
                    lbl.Size = UDim2.fromScale(1, 1)
                    lbl.BackgroundTransparency = 1
                    lbl.TextColor3 = Color3.fromRGB(255, 120, 70)
                    lbl.TextStrokeTransparency = 0.3
                    lbl.Font = Enum.Font.GothamBold
                    lbl.TextSize = 13
                    lbl.Parent = bb
                    bb.Parent = h
                    ESP[h] = bb
                end
                local lbl = bb:FindFirstChild("L")
                if lbl then
                    local d = root and math.floor((root.Position - h.Position).Magnitude / 3) or 0
                    lbl.Text = f.Name .. "\n" .. d .. "m"
                end
            end
        end
    end
    for h, bb in pairs(ESP) do
        if not seen[h] then
            pcall(function() bb:Destroy() end)
            ESP[h] = nil
        end
    end
end)

-- Bay tới trái & nhặt (tạm dừng mọi chức năng khác)
Loop(0.4, function()
    if not Cfg.FlyFruit then return end
    local root = GetRoot(LocalPlayer.Character)
    if not root then return end
    local fruit = NearestFruit(root.Position)
    if not fruit then return end

    S.Paused = true
    S.Attacking = false
    local picked = false
    local ok, err = pcall(function()
        Toast("Bay tới " .. fruit.Name)
        local t0 = os.clock()
        while S.Running and Cfg.FlyFruit and os.clock() - t0 < 75 do
            if fruit.Parent ~= Workspace then
                picked = true
                break
            end
            local handle = fruit:FindFirstChild("Handle")
            local r = GetRoot(LocalPlayer.Character)
            if handle and r then
                SetStatus("Bay tới trái: " .. fruit.Name)
                GoTo(handle.Position)
                if (r.Position - handle.Position).Magnitude < 6 and firetouchinterest then
                    pcall(firetouchinterest, r, handle, 0)
                    pcall(firetouchinterest, r, handle, 1)
                end
            end
            task.wait(0.1)
        end
    end)
    if not ok then warn("[Lucifer] " .. tostring(err)) end
    if not picked then FruitSkip[fruit] = os.clock() + 120 end
    Move.Active = false
    Move.Pos = nil
    S.Paused = false
    if picked then
        Toast("Đã nhặt " .. fruit.Name .. " — tiếp tục các chức năng khác")
    end
end)

-- Auto cất trái
Loop(1.5, function()
    if not Cfg.StoreFruit or S.Paused then return end
    ForEachTool(function(t)
        if IsPhysicalFruit(t) then
            InvokeSync("StoreFruit", t:GetAttribute("OriginalName") or t.Name, t)
        end
    end)
end)

-- Auto Random Fruit (Lv50+, mỗi 2 giờ; timer lưu file để không mất khi chạy lại)
local TIMER_FILE = "LuciferBF_FruitTimer.txt"
local OLD_TIMER_FILE = "DarkwenBF_FruitTimer.txt"
pcall(function()
    if isfile and readfile then
        for _, f in ipairs({ TIMER_FILE, OLD_TIMER_FILE }) do
            if isfile(f) then
                local v = tonumber(readfile(f))
                if v and v > S.LastRandom then S.LastRandom = v end
            end
        end
    end
end)
local function SaveTimer(t)
    S.LastRandom = t
    pcall(function() if writefile then writefile(TIMER_FILE, tostring(t)) end end)
end

local RANDOM_COOLDOWN = 7200
local RANDOM_MIN_LEVEL = 50

Loop(4, function()
    if S.Paused then return end
    local force = S.ForceRandom
    if not (Cfg.RandomFruit or force) then return end
    local lv = GetLevel()
    if lv < RANDOM_MIN_LEVEL then
        if force then
            S.ForceRandom = false
            Toast("Cần Lv " .. RANDOM_MIN_LEVEL .. " để random trái (hiện Lv " .. lv .. ")")
        end
        return
    end
    local now = os.time()
    local due = now >= S.LastRandom + RANDOM_COOLDOWN and now >= S.RandomRetryAt
    if not (due or force) then return end
    S.ForceRandom = false

    local beli0, fruits0 = tonumber(DataValue("Beli", 0)) or 0, CountFruits()
    InvokeSync("Cousin", "Buy")
    task.wait(1.2)
    local beli1 = tonumber(DataValue("Beli", 0)) or 0
    if beli1 < beli0 or CountFruits() > fruits0 then
        SaveTimer(now)
        Toast("Random trái thành công! Lần sau sau 2 giờ")
    else
        S.RandomRetryAt = now + 600
        Toast("Random chưa được (cooldown / thiếu Beli) — thử lại sau 10 phút")
    end
end)

-- ════════════════════════════ AUTO CODE ════════════════════════════
local Codes = {
    "EASTEREXP", "LIGHTNINGABUSE", "1LOSTADMIN", "SUB2GAMERROBOT_EXP1", "Sub2OfficialNoobie",
    "BIGNEWS", "Axiore", "TantaiGaming", "StrawHatMaine", "Sub2NoobMaster123", "Sub2UncleKizaru",
    "Sub2Daigrock", "Sub2Fer999", "Sub2CaptainMaui", "kittgaming", "Bluxxy", "Magicbus", "JCWK",
    "Starcodeheo", "TheGreatAce", "Chandler", "Fudd10", "fudd10_v2", "Enyu_is_Pro", "NOOB2ADMIN",
    "EXP_5B", "3BVISITS", "UPD16", "UPD15", "UPD14", "UPDATE11", "UPDATE10", "1BILLION", "2BILLION",
    "THIRDSEA", "ShutDownFix2", "XMASEXP", "CONTROL", "youtuber_shipbattle", "STAFFBATTLE",
    "NOMOREHACK", "BANEXPLOIT", "WildDares", "BossBuild", "GetPranked", "EARN_FRUITS", "FIGHT4FRUIT",
    "NOEXPLOITER", "CODESLIDE", "ADMINHACKED", "ADMINDARES", "fruitconcepts", "krazydares",
    "TRIPLEABUSE", "SEATROLLING", "24NOADMIN", "REWARDFUN", "NEWTROLL", "SECRET_ADMIN",
}
-- Code RESET điểm: mặc định KHÔNG nhập vì sẽ xoá điểm kỹ năng đã cộng
local ResetCodes = { "KITT_RESET", "SUB2GAMERROBOT_RESET1", "1MLIKES_RESET", "POINTSRESET", "XMASRESET", "JULYUPDATE_RESET" }

local function RedeemList(list)
    local remote = RedeemRemote or Remotes:FindFirstChild("Redeem")
    if not remote then
        Toast("Không tìm thấy remote nhập code")
        return
    end
    for _, code in ipairs(list) do
        if not S.Running then break end
        pcall(function() remote:InvokeServer(code) end)
        task.wait(0.35)
    end
end

local function RunCodes()
    if S.CodesBusy then
        Toast("Đang nhập code, đợi chút...")
        return
    end
    S.CodesBusy = true
    task.spawn(function()
        local list = {}
        for _, c in ipairs(Codes) do list[#list + 1] = c end
        if Cfg.CodeReset then
            for _, c in ipairs(ResetCodes) do list[#list + 1] = c end
        end
        Toast("Đang nhập " .. #list .. " code...")
        RedeemList(list)
        S.CodesBusy = false
        Toast("Xong! Code hết hạn sẽ tự bị bỏ qua")
    end)
end

-- ════════════════════════════ ANTI AFK ════════════════════════════
local function AntiAfkClick()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end
Track(LocalPlayer.Idled:Connect(function()
    if Cfg.AntiAFK then AntiAfkClick() end
end))
Loop(55, function()
    if Cfg.AntiAFK then AntiAfkClick() end
end)

-- ════════════════════════════ AUTO STATS ════════════════════════════
local StatOrder = { "Melee", "Defense", "Sword", "Gun", "Blox Fruit" }
local StatRemote = { Melee = "Melee", Defense = "Defense", Sword = "Sword", Gun = "Gun", ["Blox Fruit"] = "Demon Fruit" }

Loop(0.3, function()
    if not Cfg.AutoStats or S.Paused then return end
    local points = tonumber(DataValue("Points", 0)) or 0
    if points <= 0 then
        S.StatPending = nil
        return
    end
    local picks = {}
    for _, name in ipairs(StatOrder) do
        if Cfg.Stats[name] then picks[#picks + 1] = name end
    end
    if #picks == 0 then return end

    -- thử cộng 1 lần nhiều điểm; nếu server không nhận thì chuyển sang cộng từng điểm
    if S.StatPending and points >= S.StatPending then
        S.StatFails = S.StatFails + 1
        if S.StatFails >= 2 then S.StatSingle = true end
    end
    S.StatPending = points

    if S.StatSingle then
        for _, name in ipairs(picks) do
            for _ = 1, math.min(5, points) do
                InvokeSync("AddPoint", StatRemote[name], 1)
            end
        end
    else
        local each = math.max(1, math.floor(points / #picks))
        for _, name in ipairs(picks) do
            InvokeSync("AddPoint", StatRemote[name], each)
        end
    end
end)

-- ════════════════════════════ UI ════════════════════════════
local T = {
    BG = Color3.fromRGB(13, 13, 17),
    Side = Color3.fromRGB(20, 20, 27),
    Card = Color3.fromRGB(26, 26, 35),
    Card2 = Color3.fromRGB(35, 35, 47),
    Stroke = Color3.fromRGB(52, 52, 68),
    Text = Color3.fromRGB(242, 242, 247),
    Sub = Color3.fromRGB(143, 143, 160),
    Accent = Color3.fromRGB(229, 57, 53),
    Accent2 = Color3.fromRGB(255, 122, 64),
    Off = Color3.fromRGB(58, 58, 72),
    Good = Color3.fromRGB(80, 220, 120),
    White = Color3.fromRGB(255, 255, 255),
}

local function Make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function Round(o, r) return Make("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function Stroke(o, color, th, tr)
    return Make("UIStroke", {
        Color = color or T.Stroke, Thickness = th or 1, Transparency = tr or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end
local function Label(parent, o)
    return Make("TextLabel", {
        BackgroundTransparency = 1,
        Text = o.Text or "",
        Font = o.Font or Enum.Font.Gotham,
        TextSize = o.Size or 12,
        TextColor3 = o.Color or T.Text,
        TextXAlignment = o.Align or Enum.TextXAlignment.Left,
        TextYAlignment = o.YAlign or Enum.TextYAlignment.Center,
        TextWrapped = o.Wrap or false,
        TextTruncate = o.Wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
        Size = o.W or UDim2.new(1, 0, 0, 16),
        Position = o.Pos or UDim2.new(),
        ZIndex = o.Z or 1,
    }, parent)
end

local function GuiParent()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and typeof(h) == "Instance" then return h end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local Screen = Make("ScreenGui", {
    Name = "LuciferBF", ResetOnSpawn = false, DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
})
if not pcall(function() Screen.Parent = GuiParent() end) or not Screen.Parent then
    Screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
end
Insts[#Insts + 1] = Screen

-- Kéo thả
local function MakeDraggable(handle, frame)
    local st = { Moved = false }
    local dragging, dragStart, startPos = false, nil, nil
    local function isPointer(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    Track(handle.InputBegan:Connect(function(i)
        if isPointer(i) then
            dragging, st.Moved = true, false
            dragStart, startPos = i.Position, frame.Position
        end
    end))
    Track(UserInputService.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - dragStart
        if d.Magnitude > 6 then st.Moved = true end
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end))
    Track(UserInputService.InputEnded:Connect(function(i)
        if isPointer(i) then dragging = false end
    end))
    return st
end

-- Toast
local ToastFrame = Make("Frame", {
    AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
    Size = UDim2.fromOffset(300, 36), BackgroundColor3 = T.Card, BorderSizePixel = 0,
    Visible = false, ZIndex = 50,
}, Screen)
Round(ToastFrame, 10)
Stroke(ToastFrame, T.Accent, 1, 0.3)
local ToastText = Make("TextLabel", {
    Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1,
    TextColor3 = T.Text, Font = Enum.Font.GothamMedium, TextSize = 12, TextWrapped = true, ZIndex = 51, Text = "",
}, ToastFrame)
local toastId = 0
Toast = function(msg)
    toastId = toastId + 1
    local my = toastId
    ToastText.Text = tostring(msg)
    ToastFrame.Visible = true
    task.delay(3.2, function()
        if toastId == my then ToastFrame.Visible = false end
    end)
end

-- Cửa sổ chính
local vp = Cam() and Cam().ViewportSize or Vector2.new(800, 400)
local W = math.clamp(vp.X - 24, 330, 580)
local H = math.clamp(vp.Y - 36, 250, 380)
local compact = W < 420
local SW = compact and 50 or 108

local Main = Make("Frame", {
    Name = "Main", Size = UDim2.fromOffset(W, H), AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = T.BG, BorderSizePixel = 0,
}, Screen)
Round(Main, 14)
Stroke(Main, T.Stroke, 1, 0.1)
UIMain = Main

local Header = Make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, Main)
local Mark = Make("Frame", {
    Size = UDim2.fromOffset(4, 22), Position = UDim2.fromOffset(14, 11),
    BackgroundColor3 = T.Accent, BorderSizePixel = 0,
}, Header)
Round(Mark, 2)
Make("UIGradient", {
    Rotation = 90,
    Color = ColorSequence.new(T.Accent, T.Accent2),
}, Mark)
Label(Header, { Text = "LUCIFER HUB", Font = Enum.Font.GothamBlack, Size = 15, W = UDim2.new(1, -120, 0, 20), Pos = UDim2.fromOffset(26, 5) })
Label(Header, { Text = "Blox Fruits • Sea " .. WORLD .. " • Delta X", Size = 10, Color = T.Sub, W = UDim2.new(1, -120, 0, 14), Pos = UDim2.fromOffset(26, 25) })

local function HeaderBtn(text, xOff, color)
    local b = Make("TextButton", {
        Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, xOff, 0, 7),
        BackgroundColor3 = T.Card, Text = text, TextColor3 = color, Font = Enum.Font.GothamBold,
        TextSize = 16, AutoButtonColor = false,
    }, Header)
    Round(b, 8)
    return b
end
local MinBtn = HeaderBtn("–", -74, T.Text)
local CloseBtn = HeaderBtn("×", -40, T.Accent)
local mainDrag = MakeDraggable(Header, Main)

local bodyH = H - 44 - 40
local Side = Make("Frame", {
    Size = UDim2.fromOffset(SW, bodyH), Position = UDim2.fromOffset(8, 46),
    BackgroundColor3 = T.Side, BorderSizePixel = 0,
}, Main)
Round(Side, 12)
Make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, Side)
Make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, Side)

local Content = Make("Frame", {
    Size = UDim2.fromOffset(W - SW - 24, bodyH), Position = UDim2.fromOffset(SW + 16, 46),
    BackgroundTransparency = 1,
}, Main)

local Footer = Make("Frame", {
    Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 8, 1, -34),
    BackgroundColor3 = T.Side, BorderSizePixel = 0,
}, Main)
Round(Footer, 9)
local Dot = Make("Frame", {
    Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 12, 0.5, -4),
    BackgroundColor3 = T.Off, BorderSizePixel = 0,
}, Footer)
Round(Dot, 4)
local StatusLbl = Label(Footer, { Text = S.Status, Size = 11, Color = T.Sub, W = UDim2.new(1, -90, 1, 0), Pos = UDim2.fromOffset(28, 0) })
local LvLbl = Label(Footer, { Text = "Lv ?", Size = 11, Font = Enum.Font.GothamBold, Color = T.Accent2, Align = Enum.TextXAlignment.Right, W = UDim2.fromOffset(60, 28), Pos = UDim2.new(1, -70, 0, 0) })

-- Tabs
local Pages, TabBtns = {}, {}
local function SelectTab(idx)
    for i, P in ipairs(Pages) do
        P.Frame.Visible = (i == idx)
        local b = TabBtns[i]
        b.BackgroundTransparency = (i == idx) and 0 or 1
        b.TextColor = (i == idx) and T.White or T.Sub
        b.Btn.TextColor3 = (i == idx) and T.White or T.Sub
    end
end

local function AddPage(name, icon)
    local idx = #Pages + 1
    local btn = Make("TextButton", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.Accent, BackgroundTransparency = 1,
        Text = compact and icon or (icon .. "  " .. name), TextColor3 = T.Sub,
        Font = Enum.Font.GothamSemibold, TextSize = compact and 16 or 12, AutoButtonColor = false, LayoutOrder = idx,
    }, Side)
    Round(btn, 9)
    TabBtns[idx] = { Btn = btn }
    setmetatable(TabBtns[idx], { __newindex = function(t, k, v) if k == "BackgroundTransparency" then btn.BackgroundTransparency = v end rawset(t, k, v) end })
    local scroll = Make("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = T.Accent, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
    }, Content)
    Make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
    Make("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, scroll)
    local P = { Frame = scroll, n = 0 }
    Pages[idx] = P
    Track(btn.Activated:Connect(function() SelectTab(idx) end))
    return P
end

-- Components
local function Row(P, h)
    P.n = P.n + 1
    local f = Make("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = T.Card, BorderSizePixel = 0, LayoutOrder = P.n }, P.Frame)
    Round(f, 10)
    return f
end

local function Section(P, text)
    P.n = P.n + 1
    local l = Label(P.Frame, { Text = text, Font = Enum.Font.GothamBold, Size = 10, Color = T.Sub, W = UDim2.new(1, 0, 0, 18) })
    l.LayoutOrder = P.n
end

local function Toggle(P, title, desc, key, cb)
    local row = Row(P, 54)
    Label(row, { Text = title, Font = Enum.Font.GothamSemibold, Size = 13, W = UDim2.new(1, -76, 0, 18), Pos = UDim2.fromOffset(12, 7) })
    Label(row, { Text = desc, Size = 10, Color = T.Sub, Wrap = true, YAlign = Enum.TextYAlignment.Top, W = UDim2.new(1, -76, 0, 26), Pos = UDim2.fromOffset(12, 25) })
    local track = Make("TextButton", {
        Size = UDim2.fromOffset(44, 24), Position = UDim2.new(1, -56, 0.5, -12),
        BackgroundColor3 = T.Off, Text = "", AutoButtonColor = false,
    }, row)
    Round(track, 12)
    local knob = Make("Frame", { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = T.White, BorderSizePixel = 0 }, track)
    Round(knob, 9)
    local function render(instant)
        local info = TweenInfo.new(instant and 0 or 0.16, Enum.EasingStyle.Quad)
        local on = Cfg[key]
        TweenService:Create(track, info, { BackgroundColor3 = on and T.Accent or T.Off }):Play()
        TweenService:Create(knob, info, { Position = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3) }):Play()
    end
    Track(track.Activated:Connect(function()
        Cfg[key] = not Cfg[key]
        render(false)
        if cb then task.spawn(cb, Cfg[key]) end
    end))
    render(true)
end

local function Segment(P, title, options, key)
    local row = Row(P, 68)
    Label(row, { Text = title, Font = Enum.Font.GothamSemibold, Size = 13, W = UDim2.new(1, -24, 0, 18), Pos = UDim2.fromOffset(12, 8) })
    local holder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 30) }, row)
    Make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
    local n = #options
    local btns = {}
    local function render()
        for _, b in ipairs(btns) do
            local on = Cfg[key] == b.value
            b.btn.BackgroundColor3 = on and T.Accent or T.Card2
            b.btn.TextColor3 = on and T.White or T.Sub
        end
    end
    for i, opt in ipairs(options) do
        local b = Make("TextButton", {
            Size = UDim2.new(1 / n, -(6 * (n - 1)) / n, 1, 0), BackgroundColor3 = T.Card2, Text = opt[1],
            TextColor3 = T.Sub, Font = Enum.Font.GothamSemibold, TextSize = 12, AutoButtonColor = false, LayoutOrder = i,
        }, holder)
        Round(b, 8)
        btns[#btns + 1] = { btn = b, value = opt[2] }
        Track(b.Activated:Connect(function()
            Cfg[key] = opt[2]
            render()
        end))
    end
    render()
end

local function Chips(P, title, options, tbl)
    local row = Row(P, 68)
    Label(row, { Text = title, Font = Enum.Font.GothamSemibold, Size = 13, W = UDim2.new(1, -24, 0, 18), Pos = UDim2.fromOffset(12, 8) })
    local holder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 30) }, row)
    Make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
    local n = #options
    for i, opt in ipairs(options) do
        local b = Make("TextButton", {
            Size = UDim2.new(1 / n, -(5 * (n - 1)) / n, 1, 0), BackgroundColor3 = T.Card2, Text = opt[1],
            TextColor3 = T.Sub, Font = Enum.Font.GothamSemibold, TextSize = 11, AutoButtonColor = false, LayoutOrder = i,
        }, holder)
        Round(b, 8)
        local function render()
            local on = tbl[opt[2]] == true
            b.BackgroundColor3 = on and T.Accent or T.Card2
            b.TextColor3 = on and T.White or T.Sub
        end
        Track(b.Activated:Connect(function()
            tbl[opt[2]] = not tbl[opt[2]]
            render()
        end))
        render()
    end
end

local function Slider(P, title, min, max, step, key, suffix)
    local row = Row(P, 60)
    Label(row, { Text = title, Font = Enum.Font.GothamSemibold, Size = 13, W = UDim2.new(1, -100, 0, 18), Pos = UDim2.fromOffset(12, 8) })
    local val = Label(row, { Text = "", Font = Enum.Font.GothamBold, Size = 12, Color = T.Accent2, Align = Enum.TextXAlignment.Right, W = UDim2.fromOffset(80, 18), Pos = UDim2.new(1, -92, 0, 8) })
    local bar = Make("Frame", { Size = UDim2.new(1, -24, 0, 6), Position = UDim2.fromOffset(12, 40), BackgroundColor3 = T.Off, BorderSizePixel = 0 }, row)
    Round(bar, 3)
    local fill = Make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0 }, bar)
    Round(fill, 3)
    local knob = Make("Frame", {
        Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = T.White, BorderSizePixel = 0,
    }, bar)
    Round(knob, 8)
    local hit = Make("TextButton", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 28), BackgroundTransparency = 1, Text = "", ZIndex = 2 }, row)
    local function render()
        local a = (Cfg[key] - min) / (max - min)
        fill.Size = UDim2.fromScale(a, 1)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
        val.Text = tostring(Cfg[key]) .. (suffix or "")
    end
    local dragging = false
    local function setX(x)
        local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = min + math.floor((a * (max - min)) / step + 0.5) * step
        Cfg[key] = math.clamp(v, min, max)
        render()
    end
    local function isPointer(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    Track(hit.InputBegan:Connect(function(i)
        if isPointer(i) then
            dragging = true
            P.Frame.ScrollingEnabled = false
            setX(i.Position.X)
        end
    end))
    Track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setX(i.Position.X)
        end
    end))
    Track(UserInputService.InputEnded:Connect(function(i)
        if dragging and isPointer(i) then
            dragging = false
            P.Frame.ScrollingEnabled = true
        end
    end))
    render()
end

local function Button(P, title, desc, cb)
    local row = Row(P, 48)
    Label(row, { Text = title, Font = Enum.Font.GothamSemibold, Size = 13, W = UDim2.new(1, -50, 0, 18), Pos = UDim2.fromOffset(12, 7) })
    Label(row, { Text = desc, Size = 10, Color = T.Sub, W = UDim2.new(1, -50, 0, 14), Pos = UDim2.fromOffset(12, 26) })
    Label(row, { Text = "›", Font = Enum.Font.GothamBold, Size = 22, Color = T.Accent, Align = Enum.TextXAlignment.Center, W = UDim2.fromOffset(30, 48), Pos = UDim2.new(1, -38, 0, 0) })
    local b = Make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 3 }, row)
    Track(b.Activated:Connect(function()
        row.BackgroundColor3 = T.Card2
        task.delay(0.12, function() row.BackgroundColor3 = T.Card end)
        task.spawn(cb)
    end))
end

local function Input(P, title, placeholder, btnText, cb)
    local row = Row(P, 64)
    Label(row, { Text = title, Font = Enum.Font.GothamSemibold, Size = 13, W = UDim2.new(1, -24, 0, 18), Pos = UDim2.fromOffset(12, 7) })
    local box = Make("TextBox", {
        Size = UDim2.new(1, -112, 0, 28), Position = UDim2.fromOffset(12, 28), BackgroundColor3 = T.Card2,
        TextColor3 = T.Text, PlaceholderText = placeholder, PlaceholderColor3 = T.Sub, Text = "",
        Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    Round(box, 8)
    Make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
    local b = Make("TextButton", {
        Size = UDim2.fromOffset(80, 28), Position = UDim2.new(1, -92, 0, 28), BackgroundColor3 = T.Accent,
        Text = btnText, TextColor3 = T.White, Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false,
    }, row)
    Round(b, 8)
    Track(b.Activated:Connect(function() cb(box.Text) end))
end

local function InfoRow(P, h, text)
    local row = Row(P, h)
    local l = Label(row, { Text = text, Size = 11, Color = T.Sub, Wrap = true, YAlign = Enum.TextYAlignment.Top, W = UDim2.new(1, -24, 1, -16), Pos = UDim2.fromOffset(12, 8) })
    return l
end

-- ── Trang FARM ──
local PFarm = AddPage("Farm", "⚔")
Section(PFarm, "AUTO FARM LEVEL")
Toggle(PFarm, "Auto Farm Level", "Tự check level • nhận quest • bay tới quái • gom quái • đánh", "AutoFarm", function(on)
    if on then
        SetStatus("Đang khởi động...")
        Toast("Auto Farm: BẬT (Sea " .. WORLD .. ")")
    else
        Toast("Auto Farm: TẮT")
    end
end)
local FarmInfo = InfoRow(PFarm, 42, S.QuestInfo)
local DiagInfo = InfoRow(PFarm, 122, "")
Segment(PFarm, "Vũ khí để đánh", { { "Võ", "Melee" }, { "Kiếm", "Sword" }, { "Súng", "Gun" }, { "Trái", "Blox Fruit" } }, "Weapon")
Slider(PFarm, "Tốc độ bay", 100, 400, 10, "Speed", "")
Slider(PFarm, "Độ cao khi đánh", 4, 25, 1, "Height", "")
Section(PFarm, "NÂNG CAO")
Toggle(PFarm, "Gom quái", "Ghim quái đúng loại quest về 1 điểm, mỗi frame, không va chạm", "Bring")
Toggle(PFarm, "Hitbox lớn (tuỳ chọn)", "Chỉ bật nếu đánh không trúng; cần executor có sethiddenproperty", "BigHitbox")
Toggle(PFarm, "Học gói đánh thật (hook)", "Bắt lời gọi RegisterHit thật của game rồi phát lại; cần hookmetamethod", "CaptureHook")
Toggle(PFarm, "Fast Attack (Net)", "Gửi thêm đòn qua Net; tự đổi cách đánh nếu không thấy sát thương", "FastAttack")
Toggle(PFarm, "Auto Haki", "Tự bật Buso Haki", "Haki")
Toggle(PFarm, "NoClip khi bay", "Xuyên vật cản khi di chuyển", "NoClip")
Toggle(PFarm, "Dùng skill Z/X/C/V", "Chỉ áp dụng khi chọn vũ khí là Trái", "UseSkills")
Toggle(PFarm, "Tự qua Sea theo level", "Lv 700 → Sea 2, Lv 1500 → Sea 3 (cần đủ điều kiện mở Sea)", "AutoSea")

-- ── Trang FRUIT ──
local PFruit = AddPage("Fruit", "🍎")
Section(PFruit, "TRÁI ÁC QUỶ (bật riêng từng mục)")
Toggle(PFruit, "ESP Trái", "Hiện tên + khoảng cách mọi trái đang có trên map", "FruitESP")
Toggle(PFruit, "Auto Random Fruit", "Cần Lv 50 • random xong lặp lại mỗi 2 giờ", "RandomFruit")
Toggle(PFruit, "Tự cất trái vào túi", "Cất trái trong balo vào kho (Store)", "StoreFruit")
Toggle(PFruit, "Bay tới trái trên map", "Tạm dừng mọi chức năng khác tới khi nhặt xong", "FlyFruit")
local FruitInfo = InfoRow(PFruit, 56, "")
Button(PFruit, "Random trái ngay", "Thử random một lần (cần Lv 50 + đủ Beli + hết cooldown)", function()
    S.ForceRandom = true
    Toast("Đang thử random trái...")
end)

-- ── Trang STATS ──
local PStats = AddPage("Stats", "📈")
Section(PStats, "TỰ ĐỘNG NÂNG ĐIỂM")
Toggle(PStats, "Auto Stats", "Tự cộng toàn bộ điểm vào chỉ số đã chọn", "AutoStats")
Chips(PStats, "Chỉ số (chọn nhiều được)", { { "Melee", "Melee" }, { "Def", "Defense" }, { "Sword", "Sword" }, { "Gun", "Gun" }, { "Fruit", "Blox Fruit" } }, Cfg.Stats)
InfoRow(PStats, 40, "Nhiều chỉ số được chọn → điểm chia đều giữa các chỉ số đó.")

-- ── Trang TIỆN ÍCH ──
local PMisc = AddPage("Tiện ích", "🧰")
Section(PMisc, "CODE")
Toggle(PMisc, "Auto Nhập Code", "Bật là nhập hết danh sách code ngay", "AutoCode", function(on)
    if on then RunCodes() end
end)
Button(PMisc, "Nhập code ngay", "Chạy lại toàn bộ danh sách", RunCodes)
Input(PMisc, "Nhập code của bạn", "Dán code vào đây", "Nhập", function(text)
    text = tostring(text or ""):gsub("%s+", "")
    if text == "" then
        Toast("Chưa nhập code")
        return
    end
    task.spawn(function()
        RedeemList({ text })
        Toast("Đã gửi code: " .. text)
    end)
end)
Toggle(PMisc, "Gồm code RESET điểm", "CẨN THẬN: code reset sẽ xoá điểm kỹ năng đã cộng", "CodeReset")
Section(PMisc, "KHÁC")
Toggle(PMisc, "Anti AFK", "Chống bị kick khi treo máy", "AntiAFK")
Button(PMisc, "Gỡ script", "Tắt mọi chức năng và xoá menu", function()
    Cleanup()
end)

SelectTab(1)

-- Launcher (nút nổi)
local Launcher = Make("TextButton", {
    Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0, 14, 0, 70), BackgroundColor3 = T.Accent,
    Text = "L", TextColor3 = T.White, Font = Enum.Font.GothamBlack, TextSize = 20, AutoButtonColor = false, Visible = false,
}, Screen)
Round(Launcher, 22)
Stroke(Launcher, T.White, 1, 0.7)
local launcherDrag = MakeDraggable(Launcher, Launcher)

local function ShowMain(show)
    Main.Visible = show
    Launcher.Visible = not show
end
Track(Launcher.Activated:Connect(function()
    if launcherDrag.Moved then
        launcherDrag.Moved = false
        return
    end
    ShowMain(true)
end))
Track(MinBtn.Activated:Connect(function() ShowMain(false) end))

local closeArmed = false
Track(CloseBtn.Activated:Connect(function()
    if closeArmed then
        Cleanup()
        return
    end
    closeArmed = true
    CloseBtn.Text = "?"
    Toast("Bấm × lần nữa để gỡ script")
    task.delay(2.5, function()
        closeArmed = false
        if CloseBtn.Parent then CloseBtn.Text = "×" end
    end)
end))

-- Cập nhật giao diện live
Loop(0.4, function()
    StatusLbl.Text = S.Status
    LvLbl.Text = "Lv " .. tostring(GetLevel())
    Dot.BackgroundColor3 = (Cfg.AutoFarm or S.Paused) and T.Good or T.Off
    FarmInfo.Text = S.QuestInfo
    local diag = (S.AtkNote ~= "") and S.AtkNote or "—"
    if S.AtkDetail ~= "" then diag = diag .. "\n" .. S.AtkDetail end
    if Cfg.Bring and S.BringCount > 0 then
        diag = diag .. "\nGom quái: " .. S.BringCount .. " (đang điều khiển được: " .. S.BringOwned .. ")"
    end
    if S.EquipNote ~= "" then diag = diag .. "\n" .. S.EquipNote end
    if S.InSafeZone then diag = diag .. "\n⚠ Đang ở Safe Zone" end
    DiagInfo.Text = diag

    local remain = (S.LastRandom + RANDOM_COOLDOWN) - os.time()
    local rnd
    if GetLevel() < RANDOM_MIN_LEVEL then
        rnd = "chưa đủ Lv " .. RANDOM_MIN_LEVEL
    elseif remain <= 0 then
        rnd = "sẵn sàng"
    else
        rnd = FmtTime(remain)
    end
    FruitInfo.Text = "Trái đang có trên map: " .. S.FruitCount .. "\nRandom tiếp theo: " .. rnd
end)

print("[Lucifer] Hub đã tải • Sea " .. WORLD)
Toast("Lucifer Hub đã sẵn sàng • Sea " .. WORLD)
