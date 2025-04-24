-- Universal Server Hopper v4.1
-- Kompatibel mit Synapse, KRNL, Fluxus, AWP und anderen Executoren

local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local PlaceID         = game.PlaceId
local CurrentServerId = game.JobId

local Config = {
    MinPlayers         = 2,  -- Mindestanzahl an Spielern im Zielserver
    RequiredFreeSlots  = 2,  -- Benötigte freie Plätze
    BaseDelay          = 3,  -- Basis-Wartezeit zwischen Versuchen
    MaxRetries         = 5,  -- Maximale Versuche
    RateLimitThreshold = 3   -- Maximale Rate-Limit Fehler
}

local AttemptCount   = 0
local RateLimitCount = 0

local function debugLog(...)
    local args    = {...}
    local message = table.concat(args, " ")
    print(os.date("[%H:%M:%S]") .. " [ServerHopper] " .. message)
end

local function handleHttpRequest(url)
    -- Universal HTTP-Handler für alle Executoren
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"
    -- AWP-spezifische Behandlung
    if executor:find("awp") then
        local success, response = pcall(function()
            return game:HttpGet(url)
        end)
        if success then return response end
    end
    -- Standard-Executor-Behandlung
    local methods = {
        ["synapse"] = function() return syn.request({Url = url}) end,
        ["krnl"]    = function() return http.request(url) end,
        ["fluxus"]  = function() return fluxus.request(url) end,
        ["electron"]= function() return request(url) end,
    }
    if methods[executor] then
        local success, response = pcall(methods[executor])
        if success then return response.Body or response end
    end
    error("HTTP nicht unterstützt für " .. executor)
end

local function fetchServers()
    local url = "https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"
    local raw = handleHttpRequest(url)
    if not raw then
        RateLimitCount += 1
        return nil
    end
    local ok, result = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok and result and result.data then
        return result.data
    end
    RateLimitCount += 1
    return nil
end


local function filterServers(servers)
    local valid = {}
    for _, server in pairs(servers) do
        -- Füge Überprüfung auf private Server hinzu
        if server.id ~= CurrentServerId
        and server.playing >= Config.MinPlayers
        and (server.maxPlayers - server.playing) >= Config.RequiredFreeSlots
        and not server.vip
        then
            table.insert(valid, server.id)
        end
    end
    return valid
end

local function calculateDelay()
    local delay = Config.BaseDelay * (AttemptCount + 1)
    return math.min(delay, 30)  -- Maximal 30 Sekunden Wartezeit
end

local function attemptTeleport()
    local servers = fetchServers()
    if not servers then return false end

    local validServers = filterServers(servers)
    if #validServers == 0 then return false end

    local target = validServers[math.random(#validServers)]
    debugLog("Versuche Teleport zu:", target)
    pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, target)
    end)
    return true
end

local function main()
    while AttemptCount < Config.MaxRetries and RateLimitCount < Config.RateLimitThreshold do
        AttemptCount += 1
        if attemptTeleport() then
            debugLog("Teleport initiiert")
            return
        end
        local delay = calculateDelay()
        debugLog("Warte", delay .. "s (" .. AttemptCount .. "/" .. Config.MaxRetries .. ")")
        task.wait(delay)
    end
    debugLog("Fallback zu normalem Teleport...")
    TeleportService:Teleport(PlaceID)
end

-- Ausführung
debugLog("Starte ServerHopper für PlaceID:", PlaceID)
main()
