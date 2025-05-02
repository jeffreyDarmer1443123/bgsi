-- Safe HTTP-Request Utility für verschiedene Exploiter
local HttpService = game:GetService("HttpService")

local function safeRequest(opts)
    local methods = {}

    if syn and syn.request then
        table.insert(methods, syn.request)
    end
    if fluxus and fluxus.request then
        table.insert(methods, fluxus.request)
    end
    if http and http.request then
        table.insert(methods, http.request)
    end
    if request then
        table.insert(methods, request)
    end
    if http_request then
        table.insert(methods, http_request)
    end
    -- Fallback: HttpService
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
        if ok and res then
            local code = res.StatusCode or res.code or 0
            if res.Success or (code >= 200 and code < 300) then
                return true, res
            end
        end
    end

    return false, "Kein HTTP-Call hat erfolgreich geantwortet."
end

-- Zufallsseed
type(math).randomseed = math.randomseed
math.randomseed(os.time())

-- Services
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")

-- Konfiguration
local gameId         = 85896571713843
local baseUrl        = "https://games.roblox.com/v1/games/"..gameId.."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
local serverFile     = "server_ids.txt"
local cooldownFile   = "server_refresh_time.txt"
local refreshCooldown= 60
local maxAttempts    = 5

-- Funktion, die einen HTTP-Request mit Retry-Logik ausführt
local function fetchWithRetry(url)
    local maxRetries = 5
    local retries   = 0

    while retries <= maxRetries do
        local ok, res = safeRequest({
            Url     = url,
            Method  = "GET",
            Headers = { ["Content-Type"] = "application/json" },
        })
        if ok and res then
            local code = res.StatusCode or res.code
            if code == 200 then
                return res.Body
            elseif code == 429 then
                retries = retries + 1
                local waitTime = 5 * retries
                warn("❗ Rate-Limit, warte "..waitTime.."s ("..retries.."/"..maxRetries..")")
                wait(waitTime)
            else
                warn("❗ HTTP-Error "..tostring(code))
                return nil
            end
        else
            retries = retries + 1
            wait(2)
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
            url = baseUrl.."&cursor="..data.nextPageCursor
        else
            url = nil
        end
        wait(1)
    end

    if #allIds == 0 then
        error("❗ Keine öffentlichen Server gefunden.")
    end

    writefile(serverFile, table.concat(allIds, "\n"))
    writefile(cooldownFile, tostring(os.time() + refreshCooldown))
    print("✔️ Serverliste aktualisiert ("..#allIds.." IDs).")
end

-- Lädt gespeicherte IDs\ nlocal function loadServerIds()
    if not isfile(serverFile) then return {} end
    local t = {}
    for line in readfile(serverFile):gmatch("[^\r\n]+") do
        table.insert(t, line)
    end
    return t
end

-- Hoppt zufällig durch bis Erfolg
local function tryHopServers(serverIds)
    local attempts = 0
    local startId  = game.JobId

    while #serverIds > 0 and attempts < maxAttempts do
        attempts = attempts + 1

        local idx      = math.random(1, #serverIds)
        local serverId = serverIds[idx]
        table.remove(serverIds, idx)
        writefile(serverFile, table.concat(serverIds, "\n"))

        print("🚀 Versuch #"..attempts..": Teleport zu "..serverId)
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(gameId, serverId, Players.LocalPlayer)
        end)
        if not ok then
            warn("❗ Teleport-Error: "..tostring(err))
            wait(2)
        else
            wait(8)
            if game.JobId ~= startId then
                print("✅ Erfolgreich bei "..serverId)
                return
            else
                warn("❗ Noch derselbe Server, neuer Versuch...")
                wait(2)
            end
        end
    end

    warn("❗ Max Attempts erreicht, kein neuer Server gefunden.")
end

-- Hauptfunktion
local function main()
    local need = true
    if isfile(cooldownFile) then
        local t = tonumber(readfile(cooldownFile))
        if t and os.time() < t then need = false end
    end
    if need then
        refreshServerIds()
    end

    local ids = loadServerIds()
    if #ids == 0 then
        warn("❗ Keine Server-IDs verfügbar.")
        return
    end

    tryHopServers(ids)
end

-- Start
main()