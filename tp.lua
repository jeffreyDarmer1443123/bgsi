-- tp.lua (weiter optimiert mit erweiterter Fehlerbehandlung)

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
local cacheMaxAge = 120 -- Sekunden (länger für schlechte Verbindungen)

--// Utils
local function warnMsg(text)
    warn("[Server-Hop] " .. tostring(text))
end

local function safeDecode(jsonStr)
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, jsonStr)
    return ok and type(decoded) == "table" and decoded or nil
end

local function loadFromCache()
    if not isfile or not isfile(cacheFile) then return end
    
    local ok, content = pcall(readfile, cacheFile)
    if not ok then return end
    
    local cache = safeDecode(content)
    if cache and cache.timestamp and os.time() - cache.timestamp < cacheMaxAge then
        return cache.data
    end
end

local function saveToCache(data)
    if not writefile then return end
    pcall(function()
        writefile(cacheFile, HttpService:JSONEncode({
            timestamp = os.time(),
            data = data
        }))
    end)
end

local function fetchServerList()
    -- Versuche zuerst das Cache mit Notfall-Check
    local cached = loadFromCache()
    if cached and #cached > 0 then
        return cached
    end

    local lastValidResponse
    for attempt = 1, 7 do  -- Erhöhte Anzahl der Versuche
        local ok, response = pcall(function()
            return HttpService:GetAsync(serverListUrl, true) -- Enable throttling
        end)

        if ok then
            local parsed = safeDecode(response)
            if parsed and parsed.data and type(parsed.data) == "table" then
                saveToCache(parsed.data)
                return parsed.data
            else
                warnMsg("Ungültiges API-Format (Versuch "..attempt..")")
                lastValidResponse = parsed -- Fallback für fehlerhafte Struktur
            end
        else
            warnMsg("HTTP Fehler (Versuch "..attempt.."): "..tostring(response))
        end
        
        task.wait(2 + attempt * 1.5) -- Exponentieller Backoff
    end

    -- Notfallfallback: Verwende altes Cache selbst wenn abgelaufen
    local emergencyCache = loadFromCache()
    if emergencyCache then
        warnMsg("Using expired cache as fallback")
        return emergencyCache
    end

    return lastValidResponse and lastValidResponse.data or nil
end

--// Server-Verarbeitung
local function processServers(servers)
    local validServers = {}
    local seen = {}
    
    for _, server in ipairs(servers or {}) do
        if type(server) == "table" and server.id and server.id ~= currentJobId then
            local players = tonumber(server.playing) or 0
            local maxPlayers = tonumber(server.maxPlayers) or 12
            
            if players < maxPlayers and not seen[server.id] then
                table.insert(validServers, {
                    id = server.id,
                    players = players,
                    ping = tonumber(server.ping) or 9999
                })
                seen[server.id] = true
            end
        end
    end
    
    -- Sortiere nach Spielerzahl und Ping
    table.sort(validServers, function(a, b)
        if a.players == b.players then
            return a.ping < b.ping
        end
        return a.players < b.players
    end)
    
    return validServers
end

--// Main
local servers = fetchServerList()
if not servers or #servers == 0 then
    warnMsg("Keine Server-Daten verfügbar")
    player:Kick("Serverliste nicht verfügbar")
    return
end

local validServers = processServers(servers)
if #validServers == 0 then
    warnMsg("Keine passenden Server gefunden")
    TeleportService:Teleport(placeId) -- Vollständiger Reset
    return
end

-- Teleportversuche mit Priorisierung
for i = 1, math.min(7, #validServers) do
    local target = validServers[i]
    local success = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, target.id, player)
        task.wait(2) -- Warte auf Teleport
    end)
    
    if success then
        print(string.format("✅ Erfolgreich verbunden mit Server %s (%d/%d Spieler, %dms)",
            target.id, target.players, target.maxPlayers, target.ping))
        return
    else
        warnMsg("Fehler bei Server "..target.id.." (Versuch "..i..")")
    end
end

-- Alles fehlgeschlagen
warnMsg("Alle Verbindungsversuche fehlgeschlagen")
TeleportService:Teleport(placeId)
