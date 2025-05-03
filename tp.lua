local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Players          = game:GetService("Players")

-- Konfiguration
local gameId = 85896571713843
local baseUrl = "https://games.roblox.com/v1/games/"..gameId.."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
local dataFile = "server_data.json"
local refreshCooldown = shared.refreshCooldown or 60
local maxAttempts = shared.maxAttempts or 25
local maxServerIds = shared.maxServerIds or 200
local lockTimeout = shared.lockTimeout or 60
local baseDelay = shared.baseDelay or 5
local username = Players.LocalPlayer.Name


-- 🔄 JSON Speicherfunktionen (unverändert)
local function loadData()
    local defaultData = {
        serverIds = {},
        refreshCooldownUntil = 0,  -- Sicherstellen, dass immer ein Wert vorhanden ist
        refreshInProgress = false,
        lockOwner = nil,
        lockTimestamp = 0
    }

    if not isfile(dataFile) then
        return defaultData
    end

    local content = readfile(dataFile)
    local success, result = pcall(HttpService.JSONDecode, HttpService, content)
    
    -- Führe einen Deep Merge mit Default-Werten durch
    if success and type(result) == "table" then
        return setmetatable(result, {__index = defaultData})
    end
    
    return defaultData
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
            if code >= 200 and code < 300 then
                return true, {
                    Body = res.Body or res.response,
                    StatusCode = code
                }
            end
            return false, "HTTP-"..tostring(code)
        end
    end
    return false, "Alle HTTP-Methoden fehlgeschlagen"
end

-- 🔄 Verbesserte Synchronisationslogik
-- 🔄 Verbessertes Lock-Handling
local function acquireLock(data)
    if data.refreshInProgress then
        -- Validiere Lock-Zeitstempel
        if type(data.lockTimestamp) ~= "number" then
            data.lockTimestamp = 0
        end
        
        local lockAge = os.time() - data.lockTimestamp
        if lockAge > lockTimeout then
            warn(username.." 🔓 Übernehme abgelaufenen Lock (Alter: "..lockAge.."s)")
            return true
        end
        return false
    end
    
    -- Setze neuen Lock mit Validierung
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
    
    -- Anti-Flood mit seed
    math.randomseed(tick())
    task.wait(math.random() * 3)

    -- Lock-Handling mit Timeout
    local lockAcquired = acquireLock(data)
    if not lockAcquired then
        local waitStart = os.time()
        repeat
            task.wait(2)
            data = loadData()
        until not data.refreshInProgress or (os.time() - waitStart) > lockTimeout
        
        if data.refreshInProgress then
            warn(username.." ⚠️ Lock-Timeout - Erzwinge Übernahme")
            releaseLock(data)
        end
        return refreshServerIds()
    end

    -- HTTP-Request mit verbessertem Handling
    local allIds = {}
    local nextCursor = ""
    repeat
        local url = baseUrl..(nextCursor ~= "" and "&cursor="..nextCursor or "")
        local httpSuccess, response = safeRequest({Url = url, Method = "GET"})
        
        if not httpSuccess then
            releaseLock(data)
            error("HTTP-Request fehlgeschlagen: "..tostring(response))
        end

        -- JSON-Decoding mit Fehlerabfang
        local decoded
        local decodeSuccess, err = pcall(function()
            decoded = HttpService:JSONDecode(response.Body)
        end)
        
        if not decodeSuccess or not decoded then
            releaseLock(data)
            error("Invalid JSON: "..tostring(err))
        end

        nextCursor = decoded.nextPageCursor or ""
        
        -- Serverfilterung mit erweiterten nil-Checks
        for _, srv in ipairs(decoded.data or {}) do
            if type(srv) == "table" and srv.id and not srv.vipServerId then
                table.insert(allIds, srv.id)
            end
        end
    until nextCursor == "" or #allIds >= maxServerIds

    -- Speichern mit Validierung
    if #allIds > 0 then
        data.serverIds = allIds
        data.refreshCooldownUntil = os.time() + refreshCooldown
        saveData(data)
        warn(username.." ✔️ Aktualisiert ("..#allIds.." Server)")
    else
        warn(username.." ⚠️ Leere Serverliste erhalten")
    end
    
    releaseLock(data)
    return true
end

-- 🚀 Verbesserte Teleport-Funktion (unverändert)
local function safeTeleportToInstance(gameId, serverId)
    local maxRetries = maxAttempts
    for i = 1, maxRetries do
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(gameId, serverId)
        end)
        if ok then return true end
        
        -- Exponentielles Backoff mit Jitter
        local delay = math.pow(baseDelay, i) + math.random()
        warn(username.." 🔄 Teleport-Versuch "..i.."/"..maxRetries.." - Warte "..string.format("%.1f", delay).."s")
        task.wait(delay)
    end
    return false
end

-- 🔄 Hauptsteuerung mit Sicherheitschecks
-- 🔄 Hauptsteuerung mit erweitertem Error-Handling
local function main()
    local maxRestarts = 3
    local restartCount = 0
    local lastError
    
    while restartCount < maxRestarts do
        local data = loadData()
        
        -- 1) Cooldown-Check mit Validierung
        local currentTime = os.time()
        local cooldownValid = type(data.refreshCooldownUntil) == "number"
        local cooldownActive = cooldownValid and (data.refreshCooldownUntil > currentTime)
        
        if cooldownActive and #data.serverIds > 0 then
            local remaining = data.refreshCooldownUntil - currentTime
            warn(username.." ⏲️ Cooldown aktiv ("..math.floor(remaining).."s)")
            return tryHopServers(data)
        end

        -- 2) Serverlist-Update mit erweitertem Lock-Handling
        local refreshSuccess, refreshError = pcall(function()
            -- Lock-Mechanismus mit Deadlock-Prävention
            local lockAttempts = 0
            repeat
                lockAttempts += 1
                data = loadData()
                
                if acquireLock(data) then
                    warn(username.." 🔒 Lock erhalten (Versuch "..lockAttempts..")")
                    break
                else
                    local lockOwner = data.lockOwner or "unknown"
                    local lockAge = currentTime - (data.lockTimestamp or 0)
                    warn(username.." ⏳ Warte auf Lock von "..lockOwner.." ("..lockAge.."s)")
                    task.wait(math.random(2, 5))
                end
            until lockAttempts >= 3
            
            -- HTTP-Request mit Response-Validierung
            local allIds = {}
            local nextCursor = ""
            repeat
                local url = baseUrl..(nextCursor ~= "" and "&cursor="..nextCursor or "")
                local httpOk, response = safeRequest({Url = url, Method = "GET"})
                
                if not httpOk then
                    error("HTTP-Fehler: "..tostring(response))
                end
                
                -- JSON-Decoding mit Fehlerstack
                local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, response.Body)
                if not decodeOk then
                    error("JSON-Parserfehler: "..tostring(decoded))
                end
                
                nextCursor = decoded.nextPageCursor or ""
                
                -- Server-Validierung
                for _, srv in ipairs(decoded.data or {}) do
                    if type(srv) == "table" and srv.id and not srv.vipServerId then
                        table.insert(allIds, srv.id)
                    end
                end
            until nextCursor == "" or #allIds >= maxServerIds
            
            -- Datenvalidierung vor dem Speichern
            if #allIds < 10 then
                error("Unzureichende Server ("..#allIds..")")
            end
            
            data.serverIds = allIds
            data.refreshCooldownUntil = currentTime + refreshCooldown
            saveData(data)
        end)

        -- 3) Error-Handling
        if not refreshSuccess then
            lastError = tostring(refreshError):sub(1, 100)
            warn(username.." ❗ Refresh-Fehler: "..lastError)
            
            -- Lock-Cleanup bei Fehlern
            pcall(function()
                local data = loadData()
                if data.lockOwner == username then
                    releaseLock(data)
                    warn(username.." 🔓 Lock nach Fehler freigegeben")
                end
            end)
            
            restartCount += 1
            local delay = math.min(30, math.pow(2, restartCount) + math.random())
            warn(username.." ⏳ Neustart "..restartCount.."/"..maxRestarts.." in "..delay.."s")
            task.wait(delay)
        else
            -- 4) Erfolgreiches Hopping
            data = loadData()
            if not data.serverIds or #data.serverIds == 0 then
                error("Kritischer Fehler: Leere Liste nach Refresh")
            end
            
            warn(username.." ✅ Erfolgreich aktualisiert ("..#data.serverIds.." Server)")
            return tryHopServers(data)
        end
    end
    
    error(username.." ❗ Kritischer Fehler ("..(lastError or "unbekannt")..") nach "..maxRestarts.." Versuchen")
end

-- 🎯 Unveränderte Hopping-Logik
local function tryHopServers(data)
    local startJobId = game.JobId
    local attempts = 0
    
    while attempts < maxAttempts do
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