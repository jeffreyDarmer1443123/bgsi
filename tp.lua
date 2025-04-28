-- Kompatibilität für verschiedene Exploiter
local req = (syn and syn.request) or (http and http.request) or (request) or (fluxus and fluxus.request)

if not req then
    error("❗ Dein Executor unterstützt keine HTTP-Requests!")
end

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local gameId = 85896571713843 -- Game ID hier eintragen
local baseUrl = "https://games.roblox.com/v1/games/" .. gameId .. "/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
local PLACE_ID = game.PlaceId

local serverFile = "server_ids.txt"
local cooldownFile = "server_refresh_time.txt"
local refreshCooldown = 60 -- in Sekunden (10 Minuten bevor neue Server geladen werden)

-- Funktion, die einen HTTP-Request mit Retry-Logik ausführt
local function fetchWithRetry(url)
    local maxRetries = 5
    local retryCount = 0

    while retryCount <= maxRetries do
        local response = req({
            Url = url,
            Method = "GET",
            Headers = {
                ["Content-Type"] = "application/json"
            }
        })

        if response.StatusCode == 200 then
            return response.Body
        elseif response.StatusCode == 429 then
            retryCount = retryCount + 1
            local waitTime = 5 * retryCount
            warn("❗ Rate Limit erreicht, warte " .. waitTime .. " Sekunden und versuche erneut (" .. retryCount .. "/" .. maxRetries .. ")...")
            wait(waitTime)
        else
            warn("❗ Fehler beim Abrufen: HTTP-Status " .. tostring(response.StatusCode))
            return nil
        end
    end

    error("❗ Zu viele fehlgeschlagene Versuche, Abbruch.")
end

-- Server-IDs aktualisieren und speichern
local function refreshServerIds()
    local allServerIds = {}
    local url = baseUrl

    while url and #allServerIds < 200 do
        local body = fetchWithRetry(url)

        if body then
            local data = HttpService:JSONDecode(body)

            for _, server in ipairs(data.data) do
                if #allServerIds < 200 then
                    table.insert(allServerIds, server.id)
                else
                    break
                end
            end

            if data.nextPageCursor and #allServerIds < 200 then
                url = baseUrl .. "&cursor=" .. data.nextPageCursor
            else
                url = nil
            end

            wait(1)
        else
            break
        end
    end

    -- Speichern der IDs
    local idsString = table.concat(allServerIds, "\n")
    writefile(serverFile, idsString)

    -- Neue Refresh-Zeit speichern
    local nextRefreshTime = os.time() + refreshCooldown
    writefile(cooldownFile, tostring(nextRefreshTime))

    print("✔️ Serverliste aktualisiert mit " .. tostring(#allServerIds) .. " Servern.")
end

-- Lade Server-IDs aus Datei
local function loadServerIds()
    if not isfile(serverFile) then
        return {}
    end

    local content = readfile(serverFile)
    local ids = {}
    for line in string.gmatch(content, "[^\r\n]+") do
        table.insert(ids, line)
    end
    return ids
end

-- Hauptlogik starten
local function main()
    -- Prüfen ob Refresh notwendig ist
    local needRefresh = true

    if isfile(cooldownFile) then
        local refreshTime = tonumber(readfile(cooldownFile))
        if refreshTime and os.time() < refreshTime then
            needRefresh = false
        end
    end

    if needRefresh then
        refreshServerIds()
    end

    local serverIds = loadServerIds()

    if #serverIds == 0 then
        warn("❗ Keine Server-IDs verfügbar!")
        return
    end

    -- Zufällige Server-ID wählen
    local randomIndex = math.random(1, #serverIds)
    local serverId = serverIds[randomIndex]

    -- Server-ID aus Liste entfernen und neu speichern (damit nicht 2x gehüpft wird)
    table.remove(serverIds, randomIndex)
    local updatedContent = table.concat(serverIds, "\n")
    writefile(serverFile, updatedContent)

    -- Jetzt hoppen!
    print("🚀 Hoppe zu Server: " .. serverId)
    TeleportService:TeleportToPlaceInstance(gameId, serverId, Players.LocalPlayer)
    wait(5)
    local serverIdNow = game.PlaceId
    if serverId == serverIdNow then
        TeleportService:Teleport(PLACE_ID)
end

-- Script starten
main()
