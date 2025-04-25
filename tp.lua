-- ✅ Zuverlässiger ServerHopper v5
-- Unterstützt Synapse, KRNL, Fluxus, AWP – mit LocalPlayer-Teleport und Fallback

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local PlaceID = game.PlaceId
local CurrentServerId = game.JobId

local Config = {
    MinPlayers         = 2,   -- Mindestens x Spieler im Zielserver
    RequiredFreeSlots  = 2,   -- Zielserver braucht mindestens x freie Plätze
    MaxRetries         = 5,   -- Wie oft soll neu versucht werden
    RetryDelay         = 5,   -- Sekunden zwischen Versuchen
    RateLimitThreshold = 3    -- Wie oft HTTP-Fehler toleriert werden
}

local AttemptCount = 0
local RateLimitCount = 0

local function debugLog(...)
    print(os.date("[%H:%M:%S]") .. " [ServerHopper]", ...)
end

local function handleHttpRequest(url)
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"
    local methods = {
        ["synapse"] = function() return syn.request({Url = url}) end,
        ["krnl"] = function() return http.request({Url = url}) end,
        ["fluxus"] = function() return fluxus.request({Url = url}) end,
        ["electron"] = function() return request({Url = url}) end,
        ["awp"] = function() return game:HttpGet(url) end
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
    local response = handleHttpRequest(url)
    if not response then return nil end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)
    return ok and data.data or nil
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

local function verifyTeleport(successId)
    task.delay(10, function()
        if game.JobId == CurrentServerId then
            debugLog("⏱️ Kein Serverwechsel erfolgt. Wiederhole Teleport...")
            TeleportService:Teleport(PlaceID, player)
        else
            debugLog("✅ Erfolgreich gewechselt zu neuem Server:", successId)
        end
    end)
end

local function attemptTeleport()
    local servers = fetchServers()
    if not servers then return false end

    local valid = filterServers(servers)
    if #valid == 0 then
        debugLog("❌ Keine passenden Server gefunden.")
        return false
    end

    local target = valid[math.random(1, #valid)]
    debugLog("🎯 Versuche Teleport zu Server:", target)

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, target, player)
    end)

    if success then
        debugLog("📡 Teleport initiiert.")
        verifyTeleport(target)
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
        if attemptTeleport() then return end
        debugLog("🔁 Neuer Versuch in", Config.RetryDelay .. "s")
        task.wait(Config.RetryDelay)
    end

    debugLog("🛑 Max. Versuche erreicht – normaler Teleport...")
    TeleportService:Teleport(PlaceID, player)
end

main()
