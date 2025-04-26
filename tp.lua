-- tp.lua (mit detaillierten Statusmeldungen)

--// Services
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

--// Config
local placeId = game.PlaceId
local currentJobId = game.JobId
local serverListUrl = string.format("https://games.roblox.com/v1/games/%d/servers/Public?excludeFullGames=true&limit=100", placeId)

--// Cache
local cacheFile = "awp_servercache.txt"
local cacheMaxAge = 90

--// Utils
local function formatServerId(id)
    return id and string.sub(id, 1, 8).."..." or "UNBEKANNT"
end

local function warnMsg(text)
    warn("[Server-Hop] " .. tostring(text))
end

local function printStatus(text)
    print("[🏠 Server-Hop] " .. text)
end

local function safeDecode(jsonStr)
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(jsonStr)
    end)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

local function loadFromCache()
    if typeof(isfile) == "function" and isfile(cacheFile) then
        local ok, content = pcall(readfile, cacheFile)
        if ok and content then
            local cache = safeDecode(content)
            if cache and cache.timestamp and cache.data then
                if os.time() - cache.timestamp < cacheMaxAge then
                    return cache.data
                end
            end
        end
    end
end

local function saveToCache(data)
    if typeof(writefile) == "function" then
        pcall(function()
            writefile(cacheFile, HttpService:JSONEncode({timestamp = os.time(), data = data}))
        end)
    end
end

local function fetchServerList()
    printStatus("Starte Serverliste-Abruf...")

    local cached = loadFromCache()
    if cached then
        printStatus(string.format("Cache gefunden (%d Server)", #cached))
        return cached
    end

    printStatus("Kein gültiger Cache vorhanden, starte API-Abruf...")

    for attempt = 1, 7 do
        printStatus(string.format("API-Abruf Versuch %d/7...", attempt))

        local ok, response = pcall(function()
            return HttpService:GetAsync(serverListUrl)
        end)

        if ok and response then
            local parsed = safeDecode(response)
            if parsed and parsed.data and type(parsed.data) == "table" then
                saveToCache(parsed.data)
                return parsed.data
            else
                warnMsg("Fehler beim Parsen der Serverliste (Versuch " .. attempt .. ")")
            end
        else
            warnMsg("HTTP Fehler (Versuch " .. attempt .. ")")
        end

        task.wait(2 + attempt * 1.5)
    end

    warnMsg("Abbruch: Serverliste konnte nicht geladen werden.")
    return loadFromCache()
end

local function processServers(servers)
    printStatus("Analysiere Server...")

    local validServers = {}
    for _, server in ipairs(servers) do
        if server.id and server.playing and server.maxPlayers then
            if server.id ~= currentJobId and server.playing < server.maxPlayers then
                table.insert(validServers, server)
            end
        end
    end

    if #validServers > 0 then
        printStatus(string.format("Gefunden: %d passende Server", #validServers))
    end

    return validServers
end

--// Main
printStatus("Initialisiere Server-Hop...")
printStatus("Aktuelle JobID: "..formatServerId(currentJobId))

local servers = fetchServerList()
if not servers or #servers == 0 then
    warnMsg("Keine Server-Daten verfügbar")
    player:Kick("Serverliste nicht verfügbar")
    return
end

local validServers = processServers(servers)
if #validServers == 0 then
    printStatus("Keine passenden Server - Starte Vollreset...")
    TeleportService:Teleport(placeId)
    return
end

printStatus(string.format("Top-Server Auswahl (%d Optionen):", #validServers))
for i = 1, math.min(3, #validServers) do
    local s = validServers[i]
    printStatus(string.format("%d. [%s] %d/%d Spieler | %dms",
        i, formatServerId(s.id), s.playing, s.maxPlayers, s.ping or 0))
end

printStatus("Starte Verbindungsversuche...")
for i = 1, math.min(7, #validServers) do
    local target = validServers[i]

    printStatus(string.format(
        "Versuch %d: Verbinde zu [%s] (%d/%d Spieler, %dms)...",
        i, formatServerId(target.id), target.playing, target.maxPlayers, target.ping or 0
    ))

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, target.id, player)
        task.wait(2)
    end)

    if success then
        printStatus(string.format("✅ Erfolgreich verbunden mit [%s]", formatServerId(target.id)))
        return
    else
        warnMsg(string.format("Fehler bei [%s]: %s", formatServerId(target.id), tostring(err)))
    end
end

printStatus("⚠️ Alle Verbindungsversuche fehlgeschlagen - Letzter Versuch...")
TeleportService:Teleport(placeId)
