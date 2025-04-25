--[[
  Server-Hop-Skript
  Wechselt in einen anderen, nicht vollen öffentlichen Server desselben Spiels.
  Voraussetzungen: Exploit-Executor mit game:HttpGet oder syn.request.
--]]

local HttpService      = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer
local PlaceId         = game.PlaceId
local JobId           = game.JobId  -- aktuelle Server-Instanz

-- Ruft eine Seite der öffentlichen Serverliste ab
local function fetchServerPage(cursor)
    local baseUrl = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PlaceId)
    local url = cursor and (baseUrl .. "&cursor=" .. cursor) or baseUrl
    local response = game:HttpGet(url)
    return HttpService:JSONDecode(response)
end

-- Sammelt alle Server, die nicht voll sind und nicht die aktuelle Instanz haben
local function getAvailableServers()
    local servers = {}
    local cursor
    repeat
        local data = fetchServerPage(cursor)
        for _, srv in ipairs(data.data or {}) do
            if srv.playing < srv.maxPlayers and srv.id ~= JobId then
                table.insert(servers, srv)
            end
        end
        cursor = data.nextPageCursor
    until not cursor
    return servers
end

-- Hauptfunktion: wählt zufällig einen verfügbaren Server und teleportiert dich dorthin
local function serverHop()
    local list = getAvailableServers()
    if #list == 0 then
        warn("Server-Hop: Keine freien Server gefunden!")
        return
    end
    local target = list[math.random(1, #list)]
    TeleportService:TeleportToPlaceInstance(PlaceId, target.id, LocalPlayer)
end

-- Optional: Automatisches Neustarten des Skripts nach jedem Teleport
--(nur wenn dein Executor queue_on_teleport unterstützt)
local serialized = [[
-- hier den kompletten obigen Code einfügen (oder als Pastebin-URL laden)
]]

if syn and syn.queue_on_teleport then
    syn.queue_on_teleport(serialized)
elseif queue_on_teleport then
    queue_on_teleport(serialized)
end

-- Starte den Server-Hop
serverHop()
