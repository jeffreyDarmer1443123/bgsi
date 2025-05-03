-- tp.lua: Zufälliges Server-Hopping mit JSON-Daten und sicherem HTTP-Fallback

-- Services
local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Players          = game:GetService("Players")

-- Konfiguration
local gameId           = 85896571713843
local baseUrl          = string.format(
    "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100",
    gameId
)
local dataFile         = "tp_data.json"
local refreshCooldown  = shared.refreshCooldown or 60    -- in Sekunden
local maxAttempts      = shared.maxAttempts or 5        -- Maximale Teleport-Versuche
local maxServerIds     = shared.maxServerIds or 200     -- Maximale Anzahl gesammelter Server-IDs

-- Seed für Zufallszahlengenerator
math.randomseed(os.time())

-- Safe HTTP-Request Utility
local function safeRequest(opts)
    local methods = {}
    if syn and syn.request      then table.insert(methods, syn.request)      end
    if fluxus and fluxus.request then table.insert(methods, fluxus.request) end
    if http and http.request    then table.insert(methods, http.request)    end
    if request                  then table.insert(methods, request)         end
    if http_request             then table.insert(methods, http_request)    end
    -- Fallback auf HttpService
    table.insert(methods, function(o)
        return HttpService:RequestAsync({
            Url     = o.Url,
            Method  = o.Method,
            Headers = o.Headers,
            Body    = o.Body,
        })
    end)
    -- Probiere jede Methode
    for _, fn in ipairs(methods) do
        local ok, res = pcall(fn, opts)
        if ok and type(res) == "table" then
            local code = res.StatusCode or res.code or 0
            if res.Success ~= false and code >= 200 and code < 300 then
                return true, res
            end
        end
    end
    return false, "Kein HTTP-Call hat erfolgreich geantwortet."
end

-- JSON-Daten einlesen
local function loadData(path)
    if not isfile(path) then return nil end
    local content = readfile(path)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, content)
    return ok and data or nil
end

-- JSON-Daten speichern
local function saveData(path, tbl)
    local content = HttpService:JSONEncode(tbl)
    writefile(path, content)
end

-- Holt JSON mit Retry-Logik
local function fetchWithRetry(url)
    local retries = 0
    while retries < 5 do
        retries = retries + 1
        local ok, res = safeRequest({ Url = url, Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
        if ok and res then
            local code = res.StatusCode or res.code
            if code == 200 then
                return res.Body
            elseif code == 429 then
                task.wait(5 * retries)
            else
                warn("❗ HTTP-Error: "..tostring(code))
                return nil
            end
        else
            task.wait(2)
        end
    end
    warn("❗ Zu viele Fehlversuche beim HTTP-Request.")
    return nil
end

-- Aktualisiert und speichert neue Server-IDs
local function refreshServerIds()
    local allIds = {}
    local url    = baseUrl
    while url and #allIds < maxServerIds do
        local body = fetchWithRetry(url)
        if not body then break end
        local data = HttpService:JSONDecode(body)
        for _, srv in ipairs(data.data) do
            if not srv.vipServerId and #allIds < maxServerIds then
                table.insert(allIds, srv.id)
            end
        end
        url = data.nextPageCursor and (baseUrl.."&cursor="..data.nextPageCursor) or nil
        task.wait(1)
    end
    if #allIds == 0 then
        error("❗ Keine öffentlichen Server gefunden.")
    end
    saveData(dataFile, { serverIds = allIds, nextRefresh = os.time() + refreshCooldown })
    print("✔️ Serverliste aktualisiert ("..#allIds.." IDs). Nächster Refresh in "..refreshCooldown.."s.")
end

-- Lädt Server-IDs aus JSON
local function loadServerIds()
    local data = loadData(dataFile)
    return (data and data.serverIds) or {}
end

-- Sicherer Teleport-Aufruf
local function safeTeleportToInstance(placeId, jobId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId)
    end)
    if not ok then warn("❗ Teleport fehlgeschlagen: "..tostring(err)) end
    return ok
end

-- Hoppt zufällig durch bis Erfolg
local function tryHopServers(serverIds)
    local attempts = 0
    local startJob = game.JobId
    while #serverIds > 0 and attempts < maxAttempts do
        attempts = attempts + 1
        local idx      = math.random(1, #serverIds)
        local serverId = table.remove(serverIds, idx)
        saveData(dataFile, { serverIds = serverIds, nextRefresh = loadData(dataFile).nextRefresh })
        print("🚀 Versuch #"..attempts..": Teleport zu "..serverId)
        task.wait(3)
        if safeTeleportToInstance(gameId, serverId) then
            task.wait(8)
            if game.JobId ~= startJob then
                print("✅ Server gewechselt: "..serverId)
                return
            end
        end
        warn("❗ Wechsel fehlgeschlagen, neuer Versuch...")
        task.wait(2)
    end
    warn("❗ Maximalversuche erreicht. Kein neuer Server gefunden.")
end

-- Hauptlogik
local function main()
    local data = loadData(dataFile)
    local serverIds = {}
    local needRefresh = true
    if data then
        serverIds    = data.serverIds or {}
        needRefresh  = os.time() >= (data.nextRefresh or 0)
    end
    if needRefresh or #serverIds == 0 then
        refreshServerIds()
        data      = loadData(dataFile)
        serverIds = data.serverIds
    end
    tryHopServers(serverIds)
end

-- Ausführen
main()
