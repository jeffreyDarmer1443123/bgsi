-- ServerHop.lua (Robuster Server-Hop mit Cache und Auto-Retry)

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

-- Initialisierung
local lastRefresh = 0
local isActive = true
local cooldown = 0

-- Hilfsfunktionen
local function log(message, isWarning)
    local prefix = isWarning and "WARN" or "INFO"
    warn("["..prefix.."] ServerHop: "..message)
end

local function deepCopy(tbl)
    local copy = {}
    for k,v in pairs(tbl) do copy[k] = type(v) == "table" and deepCopy(v) or v end
    return copy
end

-- Cache Management
local function readCache()
    if not isfile(CACHE_FILE) then return nil end
    
    local content = readfile(CACHE_FILE)
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    return {
        nextRefresh = tonumber(lines[1]),
        servers = HttpService:JSONDecode(table.concat(lines, "", 2))
    }
end

local function writeCache(servers)
    local data = {
        os.time() + CACHE_DURATION,
        HttpService:JSONEncode(servers)
    }
    writefile(CACHE_FILE, table.concat(data, "\n"))
end

-- Serverabfrage
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
            local decoded = pcall(HttpService.JSONDecode, HttpService, response)
            if decoded and decoded.data then
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
    
    for _ = 1, 3 do -- Max 3 Seiten
        local data = fetchServers(cursor)
        if not data then break end
        
        for _,server in ipairs(data.data) do
            if server.id ~= game.JobId
                and not server.vipServer
                and server.playing < server.maxPlayers
                and (server.maxPlayers - server.playing) >= MIN_FREE_SLOTS
            then
                table.insert(validServers, {
                    id = server.id,
                    free = server.maxPlayers - server.playing,
                    players = server.playing,
                    capacity = server.maxPlayers
                })
            end
        end
        
        cursor = data.nextPageCursor
        if not cursor then break end
        task.wait(0.5)
    end
    
    if #validServers > 0 then
        writeCache(validServers)
    elseif cache then
        validServers = deepCopy(cache.servers)
    end
    
    return validServers
end

-- Teleportlogik
local function attemptTeleport(servers)
    table.sort(servers, function(a,b)
        return (a.free / a.capacity) > (b.free / b.capacity)
    end)

    for _,server in ipairs(servers) do
        local success, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, server.id, player)
        end)
        
        if success then
            log("Erfolgreich verbunden mit Server: "..server.id)
            return true
        else
            log("Fehler bei "..server.id..": "..tostring(err), true)
        end
        
        task.wait(1)
    end
    return false
end

-- Hauptsteuerung
local function mainCycle()
    while isActive do
        if os.time() > cooldown then
            local servers = getValidServers()
            
            if servers and #servers > 0 then
                if not attemptTeleport(servers) then
                    cooldown = os.time() + CACHE_DURATION
                end
            else
                log("Keine Server verfügbar - Fallback", true)
                TeleportService:Teleport(PLACE_ID)
                cooldown = os.time() + 10
            end
        end
        
        task.wait(5)
    end
end

-- Start
task.spawn(mainCycle)

-- Notfall-Cleanup
game:GetService("UserInputService").WindowFocused:Connect(function()
    isActive = false
    writeCache({}) -- Cache leeren
end)