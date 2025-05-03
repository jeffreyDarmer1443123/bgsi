-- tp.lua: JSON-basiertes Server-Hopping mit Synchronisation über refreshInProgress

local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Players          = game:GetService("Players")

-- Konfiguration
local gameId           = 85896571713843
local baseUrl          = "https://games.roblox.com/v1/games/"..gameId.."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
local dataFile         = "server_data.json"
local refreshCooldown  = shared.refreshCooldown or 300        -- 5 Min.
local maxAttempts      = shared.maxAttempts or 5
local maxServerIds     = shared.maxServerIds or 200
local username = Players.LocalPlayer.Name

-- 🔧 Safe HTTP-Request Utility
local function safeRequest(opts)
    local methods = {}
    if syn and syn.request then table.insert(methods, syn.request) end
    if fluxus and fluxus.request then table.insert(methods, fluxus.request) end
    if http and http.request then table.insert(methods, http.request) end
    if request then table.insert(methods, request) end
    if http_request then table.insert(methods, http_request) end

    table.insert(methods, function(o)
        return HttpService:RequestAsync({
            Url     = o.Url,
            Method  = o.Method,
            Headers = o.Headers,
            Body    = o.Body,
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

    return false, "Kein einziger HTTP-Call hat erfolgreich geantwortet."
end

-- 🔄 JSON Speicherfunktionen
local function loadData()
    if not isfile(dataFile) then
        return {
            serverIds = {},
            refreshCooldownUntil = 0,
            refreshInProgress = false
        }
    end

    local content = readfile(dataFile)
    local success, result = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if success and type(result) == "table" then
        return result
    end

    return {
        serverIds = {},
        refreshCooldownUntil = 0,
        refreshInProgress = false
    }
end

local function saveData(data)
    writefile(dataFile, HttpService:JSONEncode(data))
end

-- 🌐 Retry-fähiges HTTP-Fetch
local function fetchWithRetry(url)
    local maxRetries = 5
    local baseDelay = 5
    for attempt = 1, maxRetries do
        local ok, res = safeRequest({ Url = url, Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
        if ok and res then
            local code = res.StatusCode or res.code
            if code == 200 then
                return res.Body
            elseif code == 429 then
                local delay = baseDelay * attempt + math.random()
                warn(string.format(username .. "❗ Rate-Limit (%d/%d), warte %.1fs", attempt, maxRetries, delay))
                task.wait(delay)
            else
                error(string.format("HTTP-Fehler: %d", code))
            end
        else
            local delay = baseDelay * attempt
            warn(string.format(username .. "❗ HTTP-Request fehlgeschlagen (%d/%d), warte %ds", attempt, maxRetries, delay))
            task.wait(delay)
        end
    end
    error("❗ Zu viele fehlgeschlagene HTTP-Versuche.")
end

-- 🔃 Serverliste aktualisieren
local function refreshServerIds(data)
    data.refreshInProgress = true
    saveData(data)

    local allIds = {}
    local url = baseUrl

    while url and #allIds < maxServerIds do
        local body = fetchWithRetry(url)
        if not body then break end

        local okDecode, response = pcall(HttpService.JSONDecode, HttpService, body)
        if not okDecode or type(response) ~= "table" or not response.data then
            warn(username .. "❗ Ungültige Server-Antwort erhalten.")
            break
        end

        for _, srv in ipairs(response.data) do
            if not srv.vipServerId then
                table.insert(allIds, srv.id)
            end
        end

        if response.nextPageCursor and #allIds < maxServerIds then
            url = baseUrl .. "&cursor=" .. response.nextPageCursor
        else
            url = nil
        end
    end

    if #allIds == 0 then
        warn(username .. "❗ Keine öffentlichen Server gefunden. Versuche es später erneut.")
        data.refreshInProgress = false
        saveData(data)
        return
    end

    data.serverIds = allIds
    data.refreshCooldownUntil = os.time() + refreshCooldown
    data.refreshInProgress = false
    saveData(data)

    print(username .."✔️ Serverliste aktualisiert: " .. #allIds .. " Server gespeichert.")
end

local function safeTeleportToInstance(gameId, serverId)
    local maxAttempts = 25
    local baseDelay = 5  -- Basisverzögerung in Sekunden
    for attempt = 1, maxAttempts do
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(gameId, serverId)
        end)
        if ok then
            return true
        end
        warn(string.format(username .. "❗ Teleport-Fehler (%d/%d): %s", attempt, maxAttempts, tostring(err)))
        local delay = baseDelay * attempt + math.random()
        warn(string.format(username .. "❗ Warte %.1fs vor erneutem Versuch…", delay))
        task.wait(delay)
    end
    warn(username .. "❗ Maximale Teleport-Versuche erreicht, breche ab.")
    return false
end



-- Server-Hopping mit Zufallsoffset und längeren Pausen bei Fehlschlägen
local function tryHopServers(data)
    local attempts = 0
    local startJob = game.JobId
    local username = Players.LocalPlayer.Name

    -- Zufälliger Startoffset, um gleichzeitige Teleports zu entzerren
    task.wait(math.random(1, 10))

    while #data.serverIds > 0 and attempts < maxAttempts do
        attempts = attempts + 1
        local idx = math.random(1, #data.serverIds)
        local serverId = table.remove(data.serverIds, idx)
        saveData(data)

        print(string.format("%s 🚀 Versuch #%d: Teleport zu %s", username, attempts, serverId))
        local success = safeTeleportToInstance(gameId, serverId)

        if success then
            -- Ausreichend Wartezeit, damit der Client vollständig verbindet
            task.wait(20)
            if game.JobId ~= startJob then
                return true
            end
        else
            -- Längere Pause nach Fehlschlag
            warn(username .. "❗ Teleport gescheitert, warte 30s vor nächstem Versuch.")
            task.wait(30)
        end
    end

    warn(string.format(username .. "❗ Kein gültiger Server nach %d Versuchen." , maxAttempts))
    return false
end

-- 🚀 Hauptfunktion
local function main()
    local data = loadData()

    -- 1) Wenn gerade ein Refresh läuft, max. 60 s darauf warten
    if data.refreshInProgress then
        warn(username .. "❗ Serveraktualisierung läuft gerade auf anderem Client. Warte…")
        local waitStart = os.time()
        repeat
            task.wait(1)
            data = loadData()
            if os.time() - waitStart > 60 then
                warn(username .. "❗ Wartezeit überschritten – setze Lock zurück.")
                data.refreshInProgress = false
                saveData(data)
                break
            end
        until not data.refreshInProgress
        print(username .. "ℹ️ Serveraktualisierung abgeschlossen oder Lock zurückgesetzt.")
    end

    -- 2) Immer dann neu holen, wenn Cooldown abgelaufen oder keine IDs da sind
    if os.time() >= (data.refreshCooldownUntil or 0) or #data.serverIds == 0 then
        refreshServerIds(data)
        -- nach dem Refresh unbedingt neu einlesen
        data = loadData()
        print(username .. "ℹ️ Serverliste aktualisiert.")
    end

    -- 3) Nochmal prüfen, ob wir jetzt IDs haben
    if #data.serverIds == 0 then
        warn(username .. "❗ Keine Server-IDs verfügbar.")
        return
    end

    -- 4) Und erst jetzt hoppeln wir los
    tryHopServers(data)
end

-- ▶️ Start
main()
