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
local cacheMaxAge = 120

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

-- ... (safeDecode, loadFromCache, saveToCache bleiben gleich wie vorher)

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
        
        -- ... (restliche fetchServerList Logik wie vorher)
        
        task.wait(2 + attempt * 1.5)
    end

    -- ... (emergency cache handling)
end

--// Server-Verarbeitung
local function processServers(servers)
    printStatus("Analysiere Server...")
    
    -- ... (existing processing logic)
    
    printStatus(string.format(
        "Gefunden: %d/%d geeignete Server (Mindestspieler: %d, Maximaler Ping: %dms)",
        #validServers,
        #servers,
        math.min(unpack(players)),
        math.max(unpack(pings))
    ))
    
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
        i, formatServerId(s.id), s.players, s.maxPlayers, s.ping))
end

-- Teleportversuche
printStatus("Starte Verbindungsversuche...")
for i = 1, math.min(7, #validServers) do
    local target = validServers[i]
    
    printStatus(string.format(
        "Versuch %d: Verbinde zu [%s] (%d/%d Spieler, %dms)...",
        i, formatServerId(target.id), target.players, target.maxPlayers, target.ping
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

-- Alles fehlgeschlagen
printStatus("⚠️ Alle Verbindungsversuche fehlgeschlagen - Letzter Versuch...")
TeleportService:Teleport(placeId)
