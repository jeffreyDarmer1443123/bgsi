-- tp.lua (robustes Server-Hop mit Cache, HttpGet-Fallback, Paginierung und Absicherungs-Check)

--// Services
wait(4)
local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Players          = game:GetService("Players")
local player           = Players.LocalPlayer

--// Config
local placeId         = game.PlaceId
local currentJobId    = game.JobId
local baseUrl         = string.format(
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

-- Liest Cache mit NextRefresh und JSON payload
local function loadFromCache()
    if typeof(isfile) ~= "function" or not isfile(cacheFile) then
        return nil
    end
    local ok, content = pcall(readfile, cacheFile)
    if not ok or not content then
        return nil
    end
    local lines = {}
    for line in content:gmatch("([^\n]+)") do
        table.insert(lines, line)
    end
    local nextRefresh = tonumber(lines[1])
    if not nextRefresh or os.time() >= nextRefresh then
        return nil
    end
    local jsonStr = table.concat({select(2, table.unpack(lines))}, "\n") -- Syntaxfehler behoben
    local cache = safeDecode(jsonStr)
    return cache and cache.data or nil
end

-- Speichert Cache mit NextRefresh vorangestellt
local function saveToCache(data)
    if typeof(writefile) ~= "function" then
        return
    end
    pcall(function()
        local nextRefresh = os.time() + cacheMaxAge
        local payload = HttpService:JSONEncode({ timestamp = os.time(), data = data })
        local toWrite = tostring(nextRefresh) .. "\n" .. payload
        writefile(cacheFile, toWrite)
    end)
end

-- Holt alle Seiten der Serverliste via Paginierung
local function fetchServerList()
    local cached = loadFromCache()
    if cached then
        return cached
    end

    local allServers = {}
    local cursor = nil
    for page = 1, 5 do  -- max 5 Seiten
        local url = baseUrl
        if cursor then
            url = url .. "&cursor=" .. cursor
        end
        
        -- HTTP-Anfrage mit Fehlerbehandlung
        local ok, response = pcall(function()
            return game:HttpGet(url, true)
        end)
        if not ok or not response then
            warnMsg("Fehler beim Abrufen der Serverliste (Seite "..page..")")
            cursor = nil -- Reset cursor bei Fehlern
            task.wait(0.5)
            goto continue
        end

        -- JSON-Verarbeitung
        local parsed = safeDecode(response)
        if not parsed or type(parsed.data) ~= "table" then
            warnMsg("Fehler beim Parsen der Serverliste (Seite "..page..")")
            cursor = nil
            task.wait(0.5)
            goto continue
        end

        -- Serverdaten sammeln
        for _, srv in ipairs(parsed.data) do
            table.insert(allServers, srv)
        end

        -- Cursor für nächste Seite
        cursor = parsed.nextPageCursor or nil
        if not cursor then break end

        ::continue::
        task.wait(0.3) -- Rate-Limit vermeiden
    end

    if #allServers > 0 then
        saveToCache(allServers)
        return allServers
    end
    return nil
end

--// Hauptlogik
local oldJobId = currentJobId
local servers = fetchServerList()
if not servers then
    warnMsg("Keine Serverdaten verfügbar.")
    return
end

-- Erweiterte Filterung der Server
local valid = {}
for _, srv in ipairs(servers) do
    if srv.id and srv.playing and srv.maxPlayers then
        if type(srv.playing) ~= "number" or type(srv.maxPlayers) ~= "number" then
            goto continue -- Syntax korrigiert
        end
        
        local freeSlots = srv.maxPlayers - srv.playing
        if freeSlots >= 3 
            and srv.id ~= oldJobId 
            and srv.maxPlayers > 0 
            and freeSlots > 0 
        then
            table.insert(valid, { id = srv.id, free = freeSlots })
        end
    end
    ::continue:: -- Label hinzugefügt
end

-- Fallback: Mindestanforderung senken, wenn keine Server gefunden
if #valid == 0 then
    for _, srv in ipairs(servers) do
        if srv.id and srv.playing and srv.maxPlayers then
            local freeSlots = srv.maxPlayers - srv.playing
            if freeSlots >= 1 and srv.id ~= oldJobId then
                table.insert(valid, { id = srv.id, free = freeSlots })
            end
        end
    end
end

if #valid == 0 then
    warnMsg("Keine geeigneten Server gefunden. Starte Fallback-Teleport...")
    TeleportService:Teleport(placeId)
    return
end

-- Sortiere nach freien Plätzen absteigend
table.sort(valid, function(a, b)
    return a.free > b.free
end)

-- Teleportversuche (max. 5)
for i = 1, math.min(5, #valid) do
    local targetId = valid[i].id
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, targetId, player)
    end)
    if ok then
        print("🔄 Teleportiere zu neuem Server... JobID:", targetId)
        -- Absicherung: nach 5 Sekunden prüfen, ob gewechselt wurde
        task.wait(5)
        if game.JobId == oldJobId then
            warnMsg("Absicherung: Serverwechsel gescheitert, Fallback...")
            TeleportService:Teleport(placeId)
        end
        return
    else
        warnMsg("Teleport-Fehler (Versuch "..i.."): " .. tostring(err))
        task.wait(1)
    end
end

-- Finaler Fallback
warnMsg("Alle Teleportversuche fehlgeschlagen.")
TeleportService:Teleport(placeId)