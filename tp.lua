local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Players          = game:GetService("Players")

-- Konfiguration
local gameId = 85896571713843
local baseUrl = "https://games.roblox.com/v1/games/"..gameId.."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
local dataFile = "server_data.json"
local refreshCooldown = shared.refreshCooldown or 300        -- 5 Min.
local maxAttempts = shared.maxAttempts or 5
local maxServerIds = shared.maxServerIds or 200
local lockTimeout = shared.lockTimeout or 60,
local baseDelay = shared.lockTimeout or 5
local username = Players.LocalPlayer.Name


-- 🔄 JSON Speicherfunktionen (unverändert)
local function loadData()
    if not isfile(dataFile) then
        return {
            serverIds = {},
            refreshCooldownUntil = 0,
            refreshInProgress = false,
            lockOwner = nil,
            lockTimestamp = 0
        }
    end

    local content = readfile(dataFile)
    local success, result = pcall(HttpService.JSONDecode, HttpService, content)
    return success and result or {
        serverIds = {},
        refreshCooldownUntil = 0,
        refreshInProgress = false,
        lockOwner = nil,
        lockTimestamp = 0
    }
end

local function saveData(data)
    writefile(dataFile, HttpService:JSONEncode(data))
end

-- 🌐 Safe HTTP-Request Utility (unverändert)
local function safeRequest(opts)
    local methods = {}
    if syn and syn.request then table.insert(methods, syn.request) end
    if fluxus and fluxus.request then table.insert(methods, fluxus.request) end
    if http and http.request then table.insert(methods, http.request) end
    if request then table.insert(methods, request) end
    if http_request then table.insert(methods, http_request) end

    table.insert(methods, function(o)
        return HttpService:RequestAsync({
            Url = o.Url,
            Method = o.Method,
            Headers = o.Headers,
            Body = o.Body,
        })
    end)

    for _, fn in ipairs(methods) do
        local ok, res = pcall(fn, opts)
        if ok and type(res) == "table" then
            local code = res.StatusCode or res.code or 0
            if (res.Success ~= false) and (code >= 200 and code < 300) then
                return true, res
            end
        end
    end

    return false, "Kein erfolgreicher HTTP-Call"
end

-- 🔄 Verbesserte Synchronisationslogik
local function acquireLock(data)
    -- Prüfe auf bestehendes Lock
    if data.refreshInProgress then
        -- Lock ist abgelaufen?
        if os.time() - data.lockTimestamp > config.lockTimeout then
            warn(username.." 🔓 Übernehme abgelaufenen Lock von "..(data.lockOwner or "unknown"))
            return true
        end
        return false
    end
    
    -- Setze neuen Lock
    data.refreshInProgress = true
    data.lockOwner = username
    data.lockTimestamp = os.time()
    saveData(data)
    return true
end

local function releaseLock(data)
    data.refreshInProgress = false
    data.lockOwner = nil
    data.lockTimestamp = 0
    saveData(data)
end

-- 🔄 Verbesserte Serverlist-Aktualisierung
local function refreshServerIds()
    local data = loadData()
    
    -- Versuche Lock zu erhalten mit zufälliger Verzögerung
    math.randomseed(os.clock()*1e6)
    task.wait(math.random(0, 3)) -- Anti-Flood
    
    if not acquireLock(data) then
        warn(username.." ⏳ Warte auf bestehenden Lock von "..data.lockOwner)
        local waitStart = os.time()
        while os.time() - waitStart < config.lockTimeout do
            task.wait(2)
            data = loadData()
            if not data.refreshInProgress then break end
        end
        if data.refreshInProgress then
            warn(username.." ⚠️ Lock-Timeout, erzwinge Übernahme")
            releaseLock(data)
        end
        return refreshServerIds() -- Rekursiver Neustart
    end

    -- Eigentlicher Refresh-Prozess
    warn(username.." 🔒 Lock erhalten - Starte Aktualisierung")
    local allIds, url = {}, baseUrl
    while url and #allIds < config.maxServerIds do
        local success, res = safeRequest({Url = url, Method = "GET"})
        if not success then
            warn(username.." ❗ Kritischer HTTP-Fehler - Breche ab")
            releaseLock(data)
            error("HTTP Request failed")
        end

        local ok, resp = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if not ok then
            warn(username.." ❗ Ungültige Server-Antwort")
            break
        end

        for _, srv in ipairs(resp.data or {}) do
            if not srv.vipServerId then
                table.insert(allIds, srv.id)
            end
        end
        url = resp.nextPageCursor and (baseUrl.."&cursor="..resp.nextPageCursor) or nil
    end

    -- Update Daten
    data.serverIds = allIds
    data.refreshCooldownUntil = os.time() + config.refreshCooldown
    releaseLock(data)
    warn(username.." ✔️ Serverliste aktualisiert ("..#allIds.." Server)")
end

-- 🚀 Verbesserte Teleport-Funktion (unverändert)
local function safeTeleportToInstance(gameId, serverId)
    local maxRetries = config.maxAttempts
    for i = 1, maxRetries do
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(gameId, serverId)
        end)
        if ok then return true end
        
        -- Exponentielles Backoff mit Jitter
        local delay = math.pow(config.baseDelay, i) + math.random()
        warn(username.." 🔄 Teleport-Versuch "..i.."/"..maxRetries.." - Warte "..string.format("%.1f", delay).."s")
        task.wait(delay)
    end
    return false
end

-- 🔄 Hauptsteuerung mit Sicherheitschecks
local function main()
    local data = loadData()
    
    -- 1) Cooldown-Check
    if os.time() < data.refreshCooldownUntil and #data.serverIds > 0 then
        warn(username.." ⏲️ Cooldown aktiv ("..(data.refreshCooldownUntil - os.time()).."s)")
        return tryHopServers(data)
    end

    -- 2) Serverlist-Update erforderlich
    local success, err = pcall(refreshServerIds)
    if not success then
        warn(username.." ❗ Kritischer Fehler beim Refresh: "..tostring(err))
        task.wait(config.baseDelay * 2)
        return main() -- Neustart
    end

    -- 3) Erneuter Ladeversuch
    data = loadData()
    if #data.serverIds == 0 then
        error(username.." ❗ Keine Server verfügbar nach Refresh")
    end

    -- 4) Server-Hopping
    tryHopServers(data)
end

-- 🎯 Unveränderte Hopping-Logik
local function tryHopServers(data)
    local startJobId = game.JobId
    local attempts = 0
    
    while attempts < config.maxAttempts do
        attempts += 1
        if #data.serverIds == 0 then break end
        
        local idx = math.random(#data.serverIds)
        local sid = table.remove(data.serverIds, idx)
        saveData(data)

        warn(username.." 🚀 Versuch #"..attempts..": "..sid)
        if safeTeleportToInstance(gameId, sid) then
            task.wait(20) -- Erfolgswartezeit
            if game.JobId ~= startJobId then return end
        end
    end
    
    warn(username.." ❗ Maximale Versuche erreicht")
end

-- ▶️ Gesicherte Ausführung
while true do
    local success, err = pcall(main)
    if not success then
        warn(username.." ⚠️ Fehler in Hauptschleife: "..tostring(err))
        warn(username.." ⏳ Neustart in 30s...")
        task.wait(30)
    end
    task.wait(1) -- Grundverzögerung
end