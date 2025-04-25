--=====================================================================
-- Server-Hop v4 (AWP-kompatibel, mit Debug-Logs & korrekter Teleport-Signatur)
--=====================================================================

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")

local LocalPlayer     = Players.LocalPlayer
local PlaceId         = game.PlaceId
local CurrentJobId    = game.JobId
local executor        = (identifyexecutor and identifyexecutor():lower()) or "unknown"

-- Universal HTTP-GET
local function httpGet(url)
    -- AWP-spezifisch
    if executor:find("awp") then
        local ok, res = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and res then
            return res
        end
        -- weiter zu den anderen Varianten
    end

    -- Synapse X
    if syn and syn.request then
        local r = syn.request({ Method = "GET", Url = url })
        return r and r.Body
    end

    -- KRNL / other Exploits
    if http_request then
        local r = http_request({ Url = url, Method = "GET" })
        return r and r.Body
    end

    -- Fallback
    return game:HttpGet(url)
end

-- Sucht die erste freie, öffentliche Instanz
local function findFirstFreeServer()
    local cursor
    repeat
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s")
            :format(PlaceId, cursor and "&cursor="..cursor or "")
        local raw = httpGet(url)
        if not raw then
            warn("Server-Hop: HTTP-Request fehlgeschlagen für URL:", url)
            return nil
        end

        local data = HttpService:JSONDecode(raw)
        for _, srv in ipairs(data.data or {}) do
            if srv.playing < srv.maxPlayers and srv.id ~= CurrentJobId then
                return srv.id
            end
        end
        cursor = data.nextPageCursor
    until not cursor or cursor == ""

    return nil
end

-- Hauptfunktion: Hop ausführen
local function serverHop()
    local targetJobId = findFirstFreeServer()
    if targetJobId then
        warn("Server-Hop: Gefundener freier Server → JobId = "..targetJobId)
        -- Teleport mit korrekter Signatur (Liste von Spielern)
        TeleportService:TeleportToPlaceInstance(PlaceId, targetJobId, { LocalPlayer })
    else
        warn("Server-Hop: Kein freier Public-Server gefunden, nutze Fallback-Teleport.")
        TeleportService:Teleport(PlaceId)
    end
end

-- Optional: Nachladen per queue_on_teleport
local scriptSource = [[
-- kompletten obigen Code hierher kopieren, damit es nach jedem Hop queued wird
]]
if syn and syn.queue_on_teleport then
    syn.queue_on_teleport(scriptSource)
elseif queue_on_teleport then
    queue_on_teleport(scriptSource)
end

-- Starte den Server-Hop
serverHop()
