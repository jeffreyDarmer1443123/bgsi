-- ✅ ServerHopper v6.1 – mit echtem Serverwechsel, Cursor + Fallback

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local PlaceID = game.PlaceId
local CurrentServerId = game.JobId

local Config = {
    MinPlayers         = 1,   -- Mehr Server-Auswahl
    RequiredFreeSlots  = 2,
    MaxRetries         = 5,
    RetryDelay         = 5,
    RateLimitThreshold = 3
}

local AttemptCount = 0
local RateLimitCount = 0

local function debugLog(...)
    print(os.date("[%H:%M:%S]") .. " [ServerHopper]", ...)
end

local function safeHttpGet(url)
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"
    local handlers = {
        ["synapse"] = function() return syn.request({Url = url}).Body end,
        ["krnl"] = function() return http.request({Url = url}).Body end,
        ["fluxus"] = function() return fluxus.request({Url = url}).Body end,
        ["electron"] = function() return request({Url = url}).Body end,
        ["awp"] = function() return game:HttpGet(url) end,
    }
    local handler = handlers[executor]
    if not handler then error("❌ HTTP nicht unterstützt für: " .. executor) end

    local success, response = pcall(handler)
    if not success then
        RateLimitCount += 1
        debugLog("⚠️ HTTP fehlgeschlagen:", response)
        return nil
    end
    return response
end

local function fetchAllServers()
    local servers = {}
    local cursor = ""
    repeat
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s")
            :format(PlaceID, cursor ~= "" and ("&cursor=" .. cursor) or "")
        local response = safeHttpGet(url)
        if not response then return servers end
        local ok, data = pcall(function() return HttpService:JSONDecode(response) end)
        if ok and data and data.data then
            for _, s in ipairs(data.data) do table.insert(servers, s) end
            cursor = data.nextPageCursor
        else
            break
        end
        task.wait(0.3)
    until not cursor
    return servers
end

local function filterServers(servers)
    local valid = {}
    for _, s in ipairs(servers) do
        if s.id ~= CurrentServerId
        and s.playing >= Config.MinPlayers
        and (s.maxPlayers - s.playing) >= Config.RequiredFreeSlots
        and not s.vip then
            table.insert(valid, s.id)
        end
    end
    return valid
end

local function verifyTeleport(originalServerId)
    task.delay(10, function()
        if game.JobId == originalServerId then
            debugLog("🕒 Serverwechsel fehlgeschlagen. Suche neuen Server...")

            local servers = fetchAllServers()
            local valid = filterServers(servers)

            local fresh = {}
            for _, sid in ipairs(valid) do
                if sid ~= originalServerId then
                    table.insert(fresh, sid)
                end
            end

            if #fresh > 0 then
                local newTarget = fresh[math.random(1, #fresh)]
                debugLog("🔁 Erzwungener zweiter Versuch mit:", newTarget)
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(PlaceID, newTarget, player)
                end)
                task.wait(5)
            else
                debugLog("❌ Kein anderer Server mehr übrig. Kick für Rejoin...")
                player:Kick("🔁 Kein neuer Server gefunden – bitte erneut beitreten.")
            end
        else
            debugLog("✅ Teleport erfolgreich (neuer Server erreicht).")
        end
    end)
end

local function attemptTeleport()
    local servers = fetchAllServers()
    if #servers == 0 then
        debugLog("❌ Keine Serverdaten erhalten.")
        return false
    end

    local valid = filterServers(servers)
    if #valid == 0 then
        debugLog("❌ Keine passenden Server gefunden.")
        return false
    end

    local target = valid[math.random(1, #valid)]
    debugLog("🎯 Versuche Teleport zu:", target)

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, target, player)
    end)

    if success then
        debugLog("📡 Teleport initiiert.")
        verifyTeleport(CurrentServerId)
        task.wait(5)
        return true
    else
        debugLog("❌ Teleport fehlgeschlagen:", err)
        return false
    end
end

local function ultimateFallback()
    debugLog("🛑 Alle Versuche fehlgeschlagen. Versuche Platz-Neustart...")
    pcall(function()
        TeleportService:Teleport(PlaceID, player)
    end)
    task.wait(10)
    if game.JobId == CurrentServerId then
        debugLog("💀 Immer noch im selben Server. Kick für Autorejoin...")
        player:Kick("🔁 Restarting – Join erneut.")
    end
end

local function main()
    debugLog("🚀 Starte ServerHopper v6.1 für PlaceID:", PlaceID)
    while AttemptCount < Config.MaxRetries and RateLimitCount < Config.RateLimitThreshold do
        AttemptCount += 1
        local success = attemptTeleport()
        if success then return end
        debugLog("🔁 Versuch", AttemptCount, "fehlgeschlagen. Nächster in", Config.RetryDelay .. "s")
        task.wait(Config.RetryDelay)
    end
    ultimateFallback()
end

main()
