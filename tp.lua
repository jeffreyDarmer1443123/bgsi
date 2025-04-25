-- ✅ ServerHopper v5 – Anti-Crash Edition für AWP, KRNL, Synapse, Fluxus
-- Features: LocalPlayer-Teleport, Fallback, HTTP-Toleranz, Debuglog

wait(2)

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local PlaceID = game.PlaceId
local CurrentServerId = game.JobId

local Config = {
    MinPlayers         = 2,   -- Mindestanzahl an Spielern im Zielserver
    RequiredFreeSlots  = 8,   -- Mindestanzahl an freien Plätzen
    MaxRetries         = 5,   -- Max. Wiederholungen bei Fehlschlägen
    RetryDelay         = 5,   -- Zeit zwischen Versuchen (Sekunden)
    RateLimitThreshold = 3    -- Max. erlaubte HTTP-Fehler
}

local AttemptCount = 0
local RateLimitCount = 0

local function debugLog(...)
    print(os.date("[%H:%M:%S]") .. " [ServerHopper]", ...)
end

local function safeHttpGet(url)
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"
    local methods = {
        ["synapse"] = function() return syn.request({Url = url}) end,
        ["krnl"] = function() return http.request({Url = url}) end,
        ["fluxus"] = function() return fluxus.request({Url = url}) end,
        ["electron"] = function() return request({Url = url}) end,
        ["awp"] = function() return game:HttpGet(url) end,
    }

    local handler = methods[executor]
    if not handler then
        error("❌ HTTP nicht unterstützt für: " .. executor)
    end

    local success, response = pcall(handler)
    if success then
        return response.Body or response
    else
        RateLimitCount += 1
        debugLog("⚠️ HTTP fehlgeschlagen:", response)
        return nil
    end
end

local function fetchServers()
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", PlaceID)
    local response = safeHttpGet(url)
    if not response then return nil end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)
    if not ok or not data then
        RateLimitCount += 1
        debugLog("⚠️ JSON-Dekodierung fehlgeschlagen.")
        return nil
    end

    return data.data or {}
end

local function filterServers(servers)
    local valid = {}
    for _, server in ipairs(servers) do
        if server.id ~= CurrentServerId
        and server.playing >= Config.MinPlayers
        and (server.maxPlayers - server.playing) >= Config.RequiredFreeSlots
        and not server.vip then
            table.insert(valid, server.id)
        end
    end
    return valid
end

local function verifyTeleport(targetId)
    task.delay(10, function()
        if game.JobId == CurrentServerId then
            debugLog("🕒 Teleport nicht erfolgt. Erzwungener Fallback...")
            pcall(function()
                TeleportService:Teleport(PlaceID, player)
            end)
        else
            debugLog("✅ Erfolgreich gewechselt zu neuem Server:", targetId)
        end
    end)
end

local function attemptTeleport()
    local servers = fetchServers()
    if not servers then
        debugLog("❌ Keine Serverdaten erhalten.")
        return false
    end

    local valid = filterServers(servers)
    if #valid == 0 then
        debugLog("❌ Keine geeigneten Server gefunden.")
        return false
    end

    local target = valid[math.random(1, #valid)]
    debugLog("🎯 Teleportiere zu:", target)

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, target, player)
    end)

    if success then
        debugLog("📡 Teleport initiiert.")
        verifyTeleport(target)
        task.wait(5) -- 🛡️ Verhindert Crash nach zu schnellem Script-Ende
        return true
    else
        debugLog("❌ Teleport fehlgeschlagen:", err)
        return false
    end
end

local function main()
    debugLog("🚀 Starte ServerHopper für PlaceID:", PlaceID)
    while AttemptCount < Config.MaxRetries and RateLimitCount < Config.RateLimitThreshold do
        AttemptCount += 1
        if attemptTeleport() then
            return
        end
        debugLog("🔁 Neuer Versuch in", Config.RetryDelay .. "s")
        task.wait(Config.RetryDelay)
    end

    debugLog("🛑 Max. Versuche erreicht. Fallback zu Standard-Teleport...")
    pcall(function()
        TeleportService:Teleport(PlaceID, player)
    end)
end

main()
