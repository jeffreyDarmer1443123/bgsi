--==============================================================================
-- Universal Server Hopper v5
-- Kompatibel mit Synapse X, KRNL, Fluxus, AWP und Co.
-- Einmaliger Wechsel in einen öffentlichen, nicht vollen Server.
--==============================================================================

local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")

local PlaceID          = game.PlaceId
local CurrentServerId  = game.JobId

local Config = {
    RequiredFreeSlots = 1,   -- mindestens freie Plätze im Zielserver
    MaxRetries        = 5,   -- wie oft neu versuchen
    RetryDelay        = 2,   -- Sekunden Pause zwischen den Versuchen
}

--=================================================================
-- Universelle HTTP-GET-Funktion, die gängige Executor-APIs nutzt
--=================================================================
local function httpGet(url)
    if syn and syn.request then
        local res = syn.request({ Url = url, Method = "GET" })
        return res and res.Body
    elseif http_request then
        local res = http_request({ Url = url, Method = "GET" })
        return res and res.Body
    elseif request then
        local res = request({ Url = url, Method = "GET" })
        return res and res.Body
    else
        return game:HttpGet(url)
    end
end

--=====================================================
-- Fragt eine Seite der öffentlichen Serverliste ab
--=====================================================
local function fetchServers()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
        :format(PlaceID)
    local ok, body = pcall(httpGet, url)
    if not ok or not body then
        return nil, "HTTP fehlgeschlagen"
    end
    local success, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not success or type(data) ~= "table" or type(data.data) ~= "table" then
        return nil, "JSON-Fehler"
    end
    return data.data, nil
end

--=====================================================
-- Filtert nur Server mit genug freien Slots und
-- schließt den aktuellen Server aus
--=====================================================
local function filterServers(servers)
    local valid = {}
    for _, srv in ipairs(servers) do
        local freeSlots = srv.maxPlayers - srv.playing
        if srv.id ~= CurrentServerId and freeSlots >= Config.RequiredFreeSlots then
            table.insert(valid, srv.id)
        end
    end
    return valid
end

--=====================================================
-- Versuch, einmalig zu einem passenden Server zu hoppen
-- mit optionalem Fallback
--=====================================================
for attempt = 1, Config.MaxRetries do
    local servers, err = fetchServers()
    if servers then
        local valid = filterServers(servers)
        if #valid > 0 then
            local targetId = valid[math.random(#valid)]
            print(("[ServerHopper] Versuch #%d: Teleport zu %s"):format(attempt, targetId))
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(PlaceID, targetId)
            end)
            if ok then
                return
            else
                warn("[ServerHopper] TeleportToPlaceInstance fehlgeschlagen, versuche Teleport()")
                pcall(function()
                    TeleportService:Teleport(PlaceID)
                end)
                return
            end
        else
            warn(("[ServerHopper] Kein passender Server gefunden (Versuch %d/%d)"):format(attempt, Config.MaxRetries))
        end
    else
        warn(("[ServerHopper] fetchServers-Fehler: %s (Versuch %d/%d)"):format(tostring(err), attempt, Config.MaxRetries))
    end

    if attempt < Config.MaxRetries then
        task.wait(Config.RetryDelay)
    end
end

--===========================================================================
-- Alle Versuche gescheitert: Fallback-Teleport, damit du wenigstens reconnected
--===========================================================================
warn("[ServerHopper] Alle Versuche fehlgeschlagen, nutze Teleport() als Fallback")
pcall(function()
    TeleportService:Teleport(PlaceID)
end)
