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
    local retries = 0

    while retries <= maxRetries do
        local ok, res = safeRequest({
            Url = url,
            Method = "GET",
            Headers = { ["Content-Type"] = "application/json" },
        })

        if ok and res then
            local code = res.StatusCode or res.code
            if code == 200 then
                return res.Body
            elseif code == 429 then
                retries += 1
                warn("❗ Rate-Limit erreicht, warte " .. (retries * 5) .. "s")
                wait(retries * 5)
            else
                warn("❗ HTTP-Fehler: " .. tostring(code))
                return nil
            end
        else
            retries += 1
        end
    end

    warn("❗ Zu viele fehlgeschlagene HTTP-Versuche.")
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

        local response = HttpService:JSONDecode(body)
        for _, srv in ipairs(response.data) do
            if not srv.vipServerId then
                table.insert(allIds, srv.id)
            end
        end

        if response.nextPageCursor and #allIds < maxServerIds then
            url = baseUrl.."&cursor="..response.nextPageCursor
        else
            url = nil
        end
    end

    if #allIds == 0 then
        error("❗ Keine öffentlichen Server gefunden.")
    end

    data.serverIds = allIds
    data.refreshCooldownUntil = os.time() + refreshCooldown
    data.refreshInProgress = false
    saveData(data)

    print("✔️ Serverliste aktualisiert: "..#allIds.." Server gespeichert.")
end

-- 🧭 Sicheres Teleportieren
local function safeTeleportToInstance(gameId, serverId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(gameId, serverId)
    end)
    if not ok then
        warn("❗ Teleport-Fehler: "..tostring(err))
    end
    return ok, err
end

-- 🔀 Versucht, Server zu wechseln
local function tryHopServers(data)
    local attempts = 0
    local startJob = game.JobId
    local username = Players.LocalPlayer.Name

    while #data.serverIds > 0 and attempts < maxAttempts do
        attempts += 1
        local idx = math.random(1, #data.serverIds)
        local serverId = data.serverIds[idx]

        table.remove(data.serverIds, idx)
        saveData(data)

        print(username .. " 🚀 Versuch #" .. attempts .. ": Teleport zu " .. serverId)
        local ok, _ = safeTeleportToInstance(gameId, serverId)

        if ok then
            task.wait(2)
            if game.JobId ~= startJob then
                return
            end
        end
    end

    warn("❗ Kein gültiger Server nach "..maxAttempts.." Versuchen.")
end

-- 🚀 Hauptfunktion
local function main()
    local data = loadData()

    if data.refreshInProgress then
        warn("❗ Serveraktualisierung läuft gerade auf anderem Client. Bitte warten.")
        main()
        return
    end

    if os.time() >= (data.refreshCooldownUntil or 0) or #data.serverIds == 0 then
        refreshServerIds(data)
    end

    if #data.serverIds == 0 then
        warn("❗ Keine Server-IDs verfügbar.")
        return
    end

    tryHopServers(data)
end

-- ▶️ Start
main()