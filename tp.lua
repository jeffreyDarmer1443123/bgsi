-- tp.lua: Vollständig synchronisiertes Server-Hopping mit Atomic-Locks und Sharding

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

-- Konfiguration
local gameId = 85896571713843
local baseUrl = "https://games.roblox.com/v1/games/"..gameId.."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
local dataFile = "server_data.json"
local lockFile = "server_lock.json"
local username = Players.LocalPlayer.Name

-- Shared Config
local config = {
    refreshCooldown = shared.refreshCooldown or 300,
    maxAttempts = shared.maxAttempts or 5,
    maxServerIds = shared.maxServerIds or 200,
    maxAccounts = 5  -- Anpassen an tatsächliche Account-Anzahl
}

-- 🔧 Atomic Lock Management
local function acquireLock()
    local lockData = {
        owner = username,
        timestamp = os.time(),
        version = (readfile(lockFile) and HttpService:JSONDecode(readfile(lockFile)).version or 0
    }
    
    writefile(lockFile, HttpService:JSONEncode(lockData))
    return lockData
end

local function checkLock()
    if not isfile(lockFile) then return false end
    local success, data = pcall(function()
        return HttpService:JSONDecode(readfile(lockFile))
    end)
    return success and data or false
end

-- 🔄 Datenmanagement
local function loadServerData()
    if not isfile(dataFile) then
        return {serverIds = {}, lastUpdated = 0}
    end
    return HttpService:JSONDecode(readfile(dataFile))
end

local function saveServerData(data)
    writefile(dataFile, HttpService:JSONEncode(data))
end

-- 🌐 Verbesserte HTTP-Funktionen
local function safeRequest(url)
    local methods = {syn.request, fluxus.request, http.request, request, http_request}
    for _, method in ipairs(methods) do
        if method then
            local ok, response = pcall(method, {
                Url = url,
                Method = "GET",
                Headers = {["Content-Type"] = "application/json"}
            })
            if ok and response.StatusCode == 200 then
                return response.Body
            end
        end
    end
    error("Alle HTTP-Methoden fehlgeschlagen")
end

local function fetchPaginatedServers()
    local servers = {}
    local cursor
    repeat
        local url = cursor and (baseUrl.."&cursor="..cursor) or baseUrl
        local body = safeRequest(url)
        local data = HttpService:JSONDecode(body)
        
        for _, server in ipairs(data.data) do
            if not server.vipServerId then
                table.insert(servers, server.id)
            end
        end
        cursor = data.nextPageCursor
    until not cursor or #servers >= config.maxServerIds
    
    return servers
end

-- 🔄 Synchronisierte Serveraktualisierung
local function refreshServerList()
    local lock = checkLock()
    if lock and os.time() - lock.timestamp < 60 then
        local waitTime = math.random(5, 15)
        warn(username.." ⏳ Warte auf bestehenden Refresh ("..lock.owner..") - "..waitTime.."s")
        task.wait(waitTime)
        return false
    end

    acquireLock()
    local servers = fetchPaginatedServers()
    
    local serverData = {
        serverIds = servers,
        lastUpdated = os.time(),
        cooldown = os.time() + config.refreshCooldown
    }
    
    saveServerData(serverData)
    delfile(lockFile)
    return true
end

-- 🎯 Sharded Server-Hopping
local function getShardSlice(servers)
    local total = #servers
    local shard = (tonumber(string.match(username, "%d+")) or 1) % config.maxAccounts
    local sliceSize = math.ceil(total / config.maxAccounts)
    
    local start = (shard * sliceSize) + 1
    local finish = math.min(start + sliceSize - 1, total)
    
    return {table.unpack(servers, start, finish)}
end

local function teleportWithRetry(serverId)
    for attempt = 1, config.maxAttempts do
        local success = pcall(function()
            TeleportService:TeleportToPlaceInstance(gameId, serverId)
        end)
        
        if success then
            task.wait(20)
            return true
        end
        
        local delay = math.pow(2, attempt) + math.random()
        warn(username.." 🔄 Teleport-Versuch "..attempt.."/"..config.maxAttempts.." fehlgeschlagen - Warte "..delay.."s")
        task.wait(delay)
    end
    return false
end

local function tryHopServers()
    local serverData = loadServerData()
    if os.time() < serverData.cooldown then
        warn(username.." ⏸️ Cooldown aktiv ("..(serverData.cooldown - os.time()).."s verbleibend)")
        return
    end

    local servers = getShardSlice(serverData.serverIds)
    if #servers == 0 then
        error(username.." ❗ Keine Server im Slice verfügbar")
    end

    for _, serverId in ipairs(servers) do
        if teleportWithRetry(serverId) then
            return
        end
    end
    
    error(username.." ❗ Alle Shard-Server versucht")
end

-- 🚀 Hauptsteuerung
local function main()
    math.randomseed(os.time() * #username:byte(1))
    
    if not refreshServerList() then
        tryHopServers()
    end
end

-- ▶️ Ausführung
while true do
    local success, err = pcall(main)
    if not success then
        warn(username.." ❗ Kritischer Fehler: "..err)
        task.wait(60)
    end
    task.wait(5)
end