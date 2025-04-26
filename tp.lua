-- tp.lua (robustes Server-Hop mit Cache, HttpGet-Fallback und Absicherungs-Check)

--// Services
wait(4)
local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Players          = game:GetService("Players")
local player           = Players.LocalPlayer

--// Config
local placeId         = game.PlaceId
local currentJobId    = game.JobId
local serverListUrl   = string.format(
    "https://games.roblox.com/v1/games/%d/servers/Public?excludeFullGames=true&limit=100",
    placeId
)

--// Cache
local cacheFile       = "awp_servercache.txt"
local cacheMaxAge     = 30  -- Sekunden

--// Utility-Funktionen
local function warnMsg(msg)
    warn("[Server-Hop] " .. tostring(msg))
end

local function safeDecode(jsonStr)
    local ok, result = pcall(function()
        return HttpService:JSONDecode(jsonStr)
    end)
    if ok and type(result) == "table" then
        return result
    end
    return nil
end

-- Liest den Cache und prüft anhand der ersten Zeile den NextRefresh-Timestamp
local function loadFromCache()
    if typeof(isfile) == "function" and isfile(cacheFile) then
        local ok, content = pcall(readfile, cacheFile)
        if ok and content then
            local lines = {}
            for line in content:gmatch("([^\n]+)") do
                table.insert(lines, line)
            end
            local nextRefresh = tonumber(lines[1])
            if nextRefresh and os.time() < nextRefresh then
                local jsonStr = table.concat({select(2, table.unpack(lines))}, "\n")
                local cache = safeDecode(jsonStr)
                if cache and cache.data then
                    return cache.data
                end
            end
        end
    end
    return nil
end

-- Speichert den Cache mit NextRefresh als erste Zeile
local function saveToCache(data)
    if typeof(writefile) == "function" then
        pcall(function()
            local nextRefresh = os.time() + cacheMaxAge
            local payload = HttpService:JSONEncode({ timestamp = os.time(), data = data })
            local toWrite = tostring(nextRefresh) .. "\n" .. payload
            writefile(cacheFile, toWrite)
        end)
    end
end

--// Serverliste abrufen (Cache + Fallback auf HttpGet)
local function fetchServerList()
    local cached = loadFromCache()
    if cached then
        return cached
    end
    for attempt = 1, 5 do
        local ok, response = pcall(function()
            return game:HttpGet(serverListUrl)
        end)
        if ok and response then
            local parsed = safeDecode(response)
            if parsed and type(parsed.data) == "table" then
                saveToCache(parsed.data)
                return parsed.data
            else
                warnMsg("Fehler beim Parsen der Serverdaten (Versuch " .. attempt .. ")")
            end
        else
            warnMsg("Fehler beim Abrufen der Serverdaten (Versuch " .. attempt .. ")")
        end
        task.wait(1)
    end
    warnMsg("Abbruch: Serverdaten konnten nicht geladen werden.")
    return nil
end

--// Hauptlogik
local oldJobId = currentJobId
local servers = fetchServerList()
if not servers then return end

-- Filter: Nur Server mit mindestens 3 freien Plätzen und nicht aktueller
local validServers = {}
for _, srv in ipairs(servers) do
    if srv.id and srv.playing and srv.maxPlayers then
        local freeSlots = srv.maxPlayers - srv.playing
        if srv.id ~= oldJobId and freeSlots >= 3 then
            table.insert(validServers, srv.id)
        end
    end
end

if #validServers == 0 then
    warnMsg("Keine passenden Server mit mindestens 3 freien Plätzen gefunden.")
    return
end

-- Mische Liste
math.randomseed(os.clock() * 100000)
for i = #validServers, 2, -1 do
    local j = math.random(1, i)
    validServers[i], validServers[j] = validServers[j], validServers[i]
end

-- Teleport-Loop mit Retries und Absicherung
for attempt = 1, math.min(5, #validServers) do
    local target = validServers[attempt]
    if target then
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, target, player)
        end)
        if ok then
            print("🔄 Teleportiere zu neuem Server... JobID:", target)
            task.wait(5)
            if game.JobId == oldJobId then
                warnMsg("Absicherung: Serverwechsel gescheitert, Fallback...")
                TeleportService:Teleport(placeId)
            end
            return
        else
            warnMsg("Teleport Fehler (Versuch " .. attempt .. "): " .. tostring(err))
            task.wait(1)
        end
    end
end

warnMsg("Alle Teleportversuche fehlgeschlagen.")
pcall(function() player:Kick("Server-Hop fehlgeschlagen") end)
task.wait(1)
TeleportService:Teleport(placeId)
