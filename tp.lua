-- tp.lua (optimiert + robuster)

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
local cacheMaxAge = 60 -- Sekunden (etwas höher gesetzt)

--// Utils
local function warnMsg(text)
    warn("[Server-Hop] " .. tostring(text))
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
    local data = loadFromCache()
    if data then
        return data
    end

    local lastGoodData = nil

    for attempt = 1, 5 do
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
            warnMsg("Fehler beim Abrufen der Serverliste (Versuch " .. attempt .. ")")
        end

        task.wait(2) -- längere Pause (vorher 1 Sekunde)
    end

    warnMsg("Abbruch: Serverliste konnte nicht geladen werden.")
    return loadFromCache() -- Letzter Versuch: verwende altes Cache, wenn möglich
end

--// Main
local servers = fetchServerList()
if not servers then
    warnMsg("Kein Server-Daten verfügbar.")
    return
end

local validServers = {}
for _, server in ipairs(servers) do
    if server.id and server.playing and server.maxPlayers then
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            table.insert(validServers, server.id)
        end
    end
end

if #validServers == 0 then
    warnMsg("Keine passenden Server gefunden.")
    return
end

math.randomseed(os.clock() * 100000)
for i = #validServers, 2, -1 do
    local j = math.random(1, i)
    validServers[i], validServers[j] = validServers[j], validServers[i]
end

for attempt = 1, math.min(5, #validServers) do
    local targetId = validServers[attempt]
    if targetId then
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, targetId, player)
        end)

        if ok then
            print("🔄 Teleportiere zu neuem Server... JobID:", targetId)
            return
        else
            warnMsg("Teleport Fehler (Versuch " .. attempt .. "): " .. tostring(err))
            task.wait(1)
        end
    end
end

warnMsg("Alle Teleportversuche fehlgeschlagen.")

pcall(function()
    player:Kick("Server-Hop fehlgeschlagen")
end)
task.wait(1)
TeleportService:Teleport(placeId)
