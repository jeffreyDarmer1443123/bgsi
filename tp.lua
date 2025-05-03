-- tp.lua: Zufälliges Server-Hopping mit sicherem HTTP-Fallback

-- Safe HTTP-Request Utility für verschiedene Exploiter
local HttpService = game:GetService("HttpService")

eval(function()
    local methods = {}
    if syn and syn.request      then table.insert(methods, syn.request)      end
    if fluxus and fluxus.request then table.insert(methods, fluxus.request) end
    if http and http.request    then table.insert(methods, http.request)    end
    if request                  then table.insert(methods, request)         end
    if http_request             then table.insert(methods, http_request)    end
    table.insert(methods, function(o)
        return HttpService:RequestAsync({
            Url     = o.Url,
            Method  = o.Method,
            Headers = o.Headers,
            Body    = o.Body,
        })
    end)

    return function(opts)
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
end)()

-- Seed für Zufallszahlengenerator
math.randomseed(tick())

-- Services
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")

-- Konfiguration
local gameId         = 85896571713843
local baseUrl        = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100", gameId)
local serverFile     = "server_ids.txt"
local cooldownFile   = "server_refresh_time.txt"
local refreshCooldown= 60      -- in Sekunden
local maxAttempts    = 5       -- Maximal 5 Server-Versuche

-- Funktion: TeleportToPlaceInstance sicher aufrufen
local function safeTeleportToInstance(placeId, jobId, player)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, { player })
    end)
    if not ok then
        warn("❗ Teleport fehlgeschlagen: " .. tostring(err))
    end
    return ok, err
end

-- Holt JSON mit Retry-Logik
local function fetchWithRetry(url)
    local maxRetries = 5
    local retries    = 0

    while retries <= maxRetries do
        local ok, res = safeRequest({ Url = url, Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
        if ok and res then
            local code = res.StatusCode or res.code
            if code == 200 then
                return res.Body
            elseif code == 429 then
                retries = retries + 1
                local waitTime = 5 * retries
                warn("❗ Rate-Limit, warte "..waitTime.."s ("..retries.."/"..maxRetries..")")
                task.wait(waitTime)
            else
                warn("❗ HTTP-Error: "..tostring(code))
                return nil
            end
        else
            retries = retries + 1
            task.wait(2)
        end
    end

    error("❗ Zu viele Fehlversuche beim HTTP-Request.")
end

-- Aktualisiert und speichert Server-IDs
local function refreshServerIds()
    local allIds = {}
    local url    = baseUrl

    while url and #allIds < 200 do
        local body = fetchWithRetry(url)
        if not body then break end

        local data = HttpService:JSONDecode(body)
        for _, srv in ipairs(data.data) do
            if not srv.vipServerId and #allIds < 200 then
                table.insert(allIds, srv.id)
            end
        end

        if data.nextPageCursor and #allIds < 200 then
            url = baseUrl .. "&cursor=" .. data.nextPageCursor
        else
            url = nil
        end
        task.wait(1)
    end

    if #allIds == 0 then
        error("❗ Keine öffentlichen Server gefunden.")
    end

    writefile(serverFile, table.concat(allIds, "\n"))
    writefile(cooldownFile, tostring(os.time() + refreshCooldown))
    print("✔️ Serverliste aktualisiert ("..#allIds.." IDs).")
end

-- Lädt gespeicherte Server-IDs aus Datei
local function loadServerIds()
    if not isfile(serverFile) then return {} end
    local ids = {}
    for line in readfile(serverFile):gmatch("[^\r\n]+") do
        table.insert(ids, line)
    end
    return ids
end

-- Hoppt zufällig durch bis Erfolg
local function tryHopServers(serverIds)
    local attempts = 0
    local startJob = game.JobId

    while #serverIds > 0 and attempts < maxAttempts do
        attempts = attempts + 1
        local idx = math.random(1, #serverIds)
        local serverId = table.remove(serverIds, idx)
        writefile(serverFile, table.concat(serverIds, "\n"))

        print("🚀 Versuch #"..attempts..": Teleport zu "..serverId)
        local ok = safeTeleportToInstance(gameId, serverId, Players.LocalPlayer)
        task.wait(8)
        if ok and game.JobId ~= startJob then
            print("✅ Server gewechselt: "..serverId)
            return
        else
            warn("❗ Wechsel fehlgeschlagen, neuer Versuch...")
            task.wait(2)
        end
    end

    warn("❗ Maximalversuche erreicht. Kein neuer Server gefunden.")
end

-- Hauptlogik
local function main()
    local needRefresh = true
    if isfile(cooldownFile) then
        local t = tonumber(readfile(cooldownFile))
        if t and os.time() < t then
            needRefresh = false
        end
    end

    if needRefresh then
        refreshServerIds()
    end

    local serverIds = loadServerIds()
    if #serverIds == 0 then
        warn("❗ Keine Server-IDs verfügbar, erneutes Laden...")
        refreshServerIds()
        serverIds = loadServerIds()
        if #serverIds == 0 then
            warn("❗ Immer noch keine Server-IDs gefunden, breche ab.")
            return
        end
    end

    tryHopServers(serverIds)
end

-- Ausführen
main()
