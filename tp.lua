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
    return nil
end

local function saveToCache(data)
    if typeof(writefile) == "function" then
        pcall(function()
            writefile(cacheFile, HttpService:JSONEncode({ timestamp = os.time(), data = data }))
        end)
    end
end

--// Serverliste abrufen (Cache + Fallback auf HttpGet)
local function fetchServerList()
    -- 1) Aus Cache
    local cached = loadFromCache()
    if cached then
        return cached
    end

    -- 2) Online holen mit Retries
    for attempt = 1, 5 do
        local ok, response = pcall(function()
            -- HttpGet statt GetAsync, um Blacklist zu umgehen
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
if not servers then
    return
end

-- Filtere aktuelle Server und solche mit weniger als 3 freien Plätzen aus
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
    warnMsg("Keine passenden Server gefunden (mindestens 3 freie Plätze erforderlich).")
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
            -- Absicherung: nach 5 Sekunden prüfen, ob JobId gewechselt
            task.wait(5)
            if game.JobId == oldJobId then
                warnMsg("Absicherung: Serverwechsel gescheitert, bleibe nicht hier. Fallback...")
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
-- Fallback: Kick + Rückfall
pcall(function()
    player:Kick("Server-Hop fehlgeschlagen")
end)
task.wait(1)
TeleportService:Teleport(placeId)
