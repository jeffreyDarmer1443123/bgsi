--=====================================================================
-- Server-Hop v3 (mit AWP-Kompatibilität)
-- Wechselt sofort in den ersten freien Public-Server (ohne Privat/VIP),
-- der nicht voll ist und nicht deine aktuelle Instanz ist.
-- Exploit-Voraussetzungen:
-- • identifyexecutor() oder vergleichbare Funktion
-- • HTTP-Request (game:HttpGet, syn.request, http_request, etc.)
-- • queue_on_teleport zum automatischen Neustart (optional)
--=====================================================================

local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")

local LocalPlayer     = Players.LocalPlayer
local PlaceId         = game.PlaceId
local CurrentJobId    = game.JobId

--======================================
-- Universal HTTP-GET-Funktion
-- berücksichtigt syn.request, http_request, AWP und Fallback
--======================================
local executor = (identifyexecutor and identifyexecutor():lower()) or "unknown"

local function httpGet(url)
    -- AWP-spezifisch
    if executor:find("awp") then
        local ok, res = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and res then
            return res
        end
        -- falls AWP fehlschlägt, weiterprobieren
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

    -- Standard Roblox-API
    return game:HttpGet(url)
end

--======================================
-- Findet die erste freie öffentliche Server-ID
--======================================
local function findFirstFreeServer()
    local cursor

    repeat
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s")
            :format(PlaceId, cursor and "&cursor="..cursor or "")

        local raw = httpGet(url)
        if not raw then
            warn("HTTP-Request fehlgeschlagen: "..url)
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

--======================================
-- Führt den Server-Hop aus
--======================================
local function serverHop()
    local targetJobId = findFirstFreeServer()
    if targetJobId then
        TeleportService:TeleportToPlaceInstance(PlaceId, targetJobId, LocalPlayer)
    else
        warn("Server-Hop: Kein freier Public-Server gefunden.")
    end
end

--======================================
-- Automatisches Nachladen via queue_on_teleport
--======================================
local scriptSource = [[
-- kompletten obigen Code hier erneut einfügen, damit es nach jedem Hop queued wird
]]

if syn and syn.queue_on_teleport then
    syn.queue_on_teleport(scriptSource)
elseif queue_on_teleport then
    queue_on_teleport(scriptSource)
end

-- Starte den Hop
serverHop()
