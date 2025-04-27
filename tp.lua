-- ServerHop.lua (Korrigierte Version mit erweitertem Error-Handling)

-- Services
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Konfiguration
local PLACE_ID = game.PlaceId
local CACHE_FILE = "ServerCache.txt"
local CACHE_DURATION = 30
local MIN_FREE_SLOTS = 3
local MAX_ATTEMPTS = 5
local RETRY_DELAY = 2

-- Hilfsfunktionen
local function log(message, isWarning)
    local prefix = isWarning and "WARN" or "INFO"
    warn("["..prefix.."] ServerHop: "..message)
end

local function readCache()
    if not pcall(function() return isfile(CACHE_FILE) end) or not isfile(CACHE_FILE) then 
        return nil 
    end
    
    local success, content = pcall(readfile, CACHE_FILE)
    if not success then return nil end
    
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    if #lines < 2 then return nil end
    
    return {
        nextRefresh = tonumber(lines[1]),
        servers = pcall(HttpService.JSONDecode, HttpService, lines[2]) and HttpService:JSONDecode(lines[2]) or nil
    }
end

local function writeCache(servers)
    local data = {
        os.time() + CACHE_DURATION,
        HttpService:JSONEncode(servers or {})
    }
    pcall(writefile, CACHE_FILE, table.concat(data, "\n"))
end

-- Serverabfrage mit verbessertem Error-Handling
local function fetchServers(cursor)
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?limit=100%s",
        PLACE_ID,
        cursor and "&cursor="..cursor or ""
    )
    
    for i = 1, MAX_ATTEMPTS do
        local success, response = pcall(function()
            return game:HttpGet(url, true)
        end)
        
        if success then
            local decodeSuccess, decoded = pcall(function()
                return HttpService:JSONDecode(response)
            end)
            
            if decodeSuccess and type(decoded) == "table" then
                return decoded
            end
        end
        
        task.wait(RETRY_DELAY * i)
    end
    return nil
end

local function getValidServers()
    local cache = readCache()
    if cache and os.time() < cache.nextRefresh then
        return cache.servers
    end

    local validServers = {}
    local cursor = nil
    
    for _ = 1, 3 do
        local data = fetchServers(cursor)
        if not data or not data.data then
            log("Ungültige Serverdaten erhalten", true)
            break
        end
        
        for _, server in ipairs(data.data) do
            if server.id and server.id ~= game.JobId then
                local playing = tonumber(server.playing) or 0
                local capacity = tonumber(server.maxPlayers) or 0
                
                if not server.vipServer 
                    and capacity > 0 
                    and (capacity - playing) >= MIN_FREE_SLOTS 
                then
                    table.insert(validServers, {
                        id = server.id,
                        free = capacity - playing,
                        capacity = capacity
                    })
                end
            end
        end
        
        cursor = data.nextPageCursor or nil
        if not cursor then break end
        task.wait(0.5)
    end
    
    if #validServers > 0 then
        writeCache(validServers)
    end
    
    return validServers or {}
end

-- Teleportlogik
local function attemptTeleport(servers)
    if #servers == 0 then return false end
    
    table.sort(servers, function(a,b)
        return (a.free / a.capacity) > (b.free / b.capacity)
    end)

    for _, server in ipairs(servers) do
        local success = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, server.id, player)
        end)
        
        if success then
            log("Verbunden mit Server: "..server.id)
            return true
        else
            log("Fehler bei Server "..server.id, true)
        end
        
        task.wait(1)
    end
    return false
end

-- Hauptsteuerung
while true do
    local servers = getValidServers()
    
    if servers and #servers > 0 then
        if not attemptTeleport(servers) then
            writeCache(servers) -- Cache aktualisieren
            task.wait(CACHE_DURATION)
        end
    else
        log("Keine Server verfügbar - Fallback", true)
        pcall(TeleportService.Teleport, TeleportService, PLACE_ID)
        task.wait(CACHE_DURATION)
    end
    
    task.wait(5)
end