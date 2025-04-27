-- ServerHopper.lua (Robuste Version 2.0)

-- Services
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Konfiguration
local PLACE_ID = game.PlaceId
local CACHE_FILE = "ServerCache.txt"
local BLACKLIST_FILE = "Blacklist.txt"
local CACHE_DURATION = 30
local MIN_FREE_SLOTS = 3
local MAX_API_ATTEMPTS = 3
local BASE_URL = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s"

-- Initialisierung
local serverBlacklist = {}
local lastRefresh = 0

-- Hilfsfunktionen
local function log(message, isWarning)
    warn("["..(isWarning and "WARN" or "INFO").."] ServerHopper: "..message)
end

local function safeReadFile(filename)
    local success, content = pcall(readfile, filename)
    return success and content or nil
end

local function safeWriteFile(filename, content)
    pcall(writefile, filename, content)
end

-- Blacklist Management
local function updateBlacklist()
    local content = safeReadFile(BLACKLIST_FILE)
    serverBlacklist = content and HttpService:JSONDecode(content) or {}
end

local function blacklistServer(serverId)
    serverBlacklist[serverId] = os.time() + 300 -- 5 Minuten Sperre
    safeWriteFile(BLACKLIST_FILE, HttpService:JSONEncode(serverBlacklist))
    log("Server geblockt: "..serverId, true)
end

-- Cache Management
local function readCache()
    local content = safeReadFile(CACHE_FILE)
    if not content then return nil end
    
    local success, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    
    if success and data.timestamp and (os.time() - data.timestamp) < CACHE_DURATION then
        return data.servers
    end
    return nil
end

-- Korrigierte Cache-Verwaltung
local function writeCache(servers)
    if #servers == 0 then return end  -- Leere Serverlisten nicht speichern
    
    local data = {
        timestamp = os.time(),
        servers = servers
    }
    
    -- Erweiterte Fehlerbehandlung
    local jsonSuccess, json = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    
    if jsonSuccess then
        local fileSuccess, err = pcall(function()
            writefile(CACHE_FILE, json)
            log("Cache erfolgreich geschrieben: "..#servers.." Server")
        end)
        
        if not fileSuccess then
            log("Cache-Schreibfehler: "..tostring(err), true)
        end
    else
        log("JSON-Kodierungsfehler: "..tostring(json), true)
    end
end

-- Serverabfrage mit Fehlerbehandlung
local function fetchServers(cursor)
    local url = string.format(BASE_URL, PLACE_ID, cursor and "&cursor="..cursor or "")
    log("API-Anfrage: "..url)
    
    for attempt = 1, MAX_API_ATTEMPTS do
        local success, response = pcall(function()
            return game:HttpGet(url, true)
        end)
        
        if success then
            local decoded = pcall(HttpService.JSONDecode, HttpService, response)
            if decoded and type(decoded) == "table" then
                return decoded
            end
        end
        task.wait(2 ^ attempt) -- Exponentielles Backoff
    end
    return nil
end

-- Serverfilterung
local function filterServers(servers)
    local valid = {}
    updateBlacklist()
    
    for _, server in ipairs(servers) do
        -- Erweiterte Validierung
        if server.id
            and not serverBlacklist[server.id]
            and server.id ~= game.JobId
            and not (server.vipServer or server.accessCode)
            and tonumber(server.playing)
            and tonumber(server.maxPlayers)
        then
            local free = server.maxPlayers - server.playing
            if free >= MIN_FREE_SLOTS then
                table.insert(valid, {
                    id = server.id,
                    free = free,
                    capacity = server.maxPlayers
                })
            end
        end
    end
    
    -- Verbesserte Sortierung
    table.sort(valid, function(a, b)
        return a.free > b.free  -- Sortiere nach absoluten freien Plätzen
    end)
    
    return valid
end

-- Hauptfunktion
local function findBestServer()
    -- Lösche alten Cache bei Neustart
    if readCache() or {} == 0 then
        pcall(writefile, CACHE_FILE, "")
    end

    local allServers = {}
    local cursor = nil
    
    -- Erhöhte Seitenanzahl
    for _ = 1, 5 do  -- Maximal 5 Seiten
        local data = fetchServers(cursor)
        if not data or not data.data then break end
        
        -- Debug-Logging
        log("Verarbeite "..#data.data.." Server von API")
        
        -- Füge alle Rohdaten hinzu
        for _, server in ipairs(data.data) do
            table.insert(allServers, server)
        end
        
        cursor = data.nextPageCursor
        if not cursor then break end
        task.wait(0.3)
    end
    
    -- Erweiterte Filterung
    local validServers = filterServers(allServers)
    
    -- Schreibe nur wenn Server gefunden
    if #validServers > 0 then
        writeCache(validServers)
        log("Gültige Server gefunden: "..#validServers)
    else
        log("Keine gültigen Server für Cache", true)
    end
    
    return validServers
end

-- Teleport-System
local function attemptTeleport()
    local servers = findBestServer() or {}
    
    for _, server in ipairs(servers) do
        local success, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, server.id, player)
        end)
        
        if success then
            log("Erfolgreich verbunden mit: "..server.id)
            return true
        else
            log("Fehler: "..tostring(err), true)
            if tostring(err):find("773") then
                blacklistServer(server.id)
            end
        end
        task.wait(1)
    end
    
    return false
end

-- Hauptsteuerung
while true do
    if os.time() - lastRefresh > CACHE_DURATION then
        lastRefresh = os.time()
        
        if not attemptTeleport() then
            log("Starte Notfall-Teleport...", true)
            pcall(TeleportService.Teleport, TeleportService, PLACE_ID)
            task.wait(10)
        end
    end
    task.wait(5)
end