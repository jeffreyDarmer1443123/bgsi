-- ServerHopper v5.0 (Stabil)
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local PlaceID = 85896571713843  -- Hardcodierte PlaceID

local Config = {
    MaxAttempts = 10,
    BaseDelay = 5,
    RetryExponent = 1.5,
    RateLimitCooldown = 15,
    MinPlayers = 1
}

local function debugLog(...)
    local args = table.concat({...}, " ")
    print(os.date("[%H:%M:%S]").." [HopMaster] "..args)
end

local function safeHttpGet(url)
    for i = 1, 3 do  -- 3 Wiederholungsversuche
        local success, response = pcall(function()
            return game:HttpGetAsync(url, true)
        end)
        if success then return response end
        task.wait(2^i)  -- Exponentielle Backoff
    end
    return nil
end

local function fetchValidServers()
    local response = safeHttpGet(
        "https://games.roblox.com/v1/games/"..PlaceID..
        "/servers/Public?sortOrder=Asc&limit=100"
    )
    
    if not response then
        debugLog("Serverliste nicht verfügbar")
        return {}
    end

    local success, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)
    
    return success and data.data or {}
end

local function selectBestServer(servers)
    local currentJobId = game.JobId
    local valid = {}
    
    for _, server in ipairs(servers) do
        if server.id ~= currentJobId
            and server.playing >= Config.MinPlayers
            and (server.maxPlayers - server.playing) >= 1
        then
            table.insert(valid, server.id)
        end
    end
    
    if #valid > 0 then
        return valid[math.random(#valid)]
    end
end

local function attemptTeleport(target)
    local result = TeleportService:TeleportToPlaceInstance(PlaceID, target)
    return result == Enum.TeleportResult.Success
end

local function mainHop()
    for attempt = 1, Config.MaxAttempts do
        debugLog(("Versuch %d/%d"):format(attempt, Config.MaxAttempts))
        
        local servers = fetchValidServers()
        local target = selectBestServer(servers)
        
        if target then
            debugLog("Gefundener Server: "..target:sub(1, 8).."...")
            if attemptTeleport(target) then
                debugLog("Teleport gestartet")
                task.wait(10)  -- Wartezeit für Teleport
                return true
            end
        end
        
        local delay = math.floor(Config.BaseDelay * (Config.RetryExponent^attempt))
        debugLog(("Nächster Versuch in %ds"):format(delay))
        task.wait(delay)
    end
    
    debugLog("Fallback zu Standard-Teleport")
    TeleportService:Teleport(PlaceID)
end

debugLog("Starte ServerHopper...")
mainHop()
