wait(4)
--==================================================================
-- tp.lua – Einmaliger, zuverlässiger Server-Hop (Client/Executor-kompatibel)
-- • Läuft komplett im LocalScript/Executor (Synapse, KRNL, Fluxus, AWP u.a.)
--==================================================================

local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")

local PlaceID         = game.PlaceId
local CurrentJobId    = game.JobId

--==================================================================
-- 1) TeleportInitFailed-Handler: Kick & Rejoin, falls Teleport blockiert
--==================================================================
TeleportService.TeleportInitFailed:Connect(function(errCode, errMsg)
    warn("[ServerHop] TeleportInitFailed:", errCode, errMsg, "→ Kick & Rejoin")
    pcall(function() Players.LocalPlayer:Kick("Auto-Rejoin…") end)
    task.wait(1)
    TeleportService:Teleport(PlaceID)
end)

--==================================================================
-- 2) Universelle HTTP-GET-Funktion für Exploit-Clients
--==================================================================
local function httpGet(url)
    if syn and syn.request then
        return syn.request({Url = url, Method = "GET"}).Body
    elseif http_request then
        return http_request({Url = url, Method = "GET"}).Body
    elseif request then
        return request({Url = url, Method = "GET"}).Body
    else
        return game:HttpGet(url)
    end
end

-- Alias: safeHttpGet nutzt httpGet
local safeHttpGet = httpGet

--==================================================================
-- 3) Versucht, eine Seite der Public-Server-API zu laden und zu parsen
--==================================================================
local function fetchServers()
    local raw = safeHttpGet(
        ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PlaceID)
    )
    if not raw then
        warn("[ServerHop] HTTP-Fehler oder Rate-Limit")
        return nil
    end

    local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok then
        warn("[ServerHop] JSON-Parsing fehlgeschlagen, raw:\n", raw)
        return nil
    end

    if data.errors then
        -- Rate-Limit erkannt
        warn("[ServerHop] Rate-Limit: Warte 5 Sekunden bevor nächster Versuch")
        task.wait(5)
        return nil
    end

    return data.data
end

--==================================================================
-- 4) Wähle eine zufällige, andere Instanz aus der Liste
--==================================================================
task.wait(0.5)  -- kurz warten, damit TeleportService bereit ist
local servers = fetchServers()
if servers then
    local valid = {}
    for _, srv in ipairs(servers) do
        if srv.id ~= CurrentJobId and srv.playing < srv.maxPlayers then
            table.insert(valid, srv.id)
        end
    end
    if #valid > 0 then
        local targetId = valid[math.random(#valid)]
        warn("[ServerHop] TeleportToPlaceInstance →", targetId)
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(PlaceID, targetId)
        end)
        if ok then return end  -- erfolgreich, Script ist weg
        warn("[ServerHop] TeleportToPlaceInstance fehlgeschlagen, fallback Kick+Teleport")
    else
        warn("[ServerHop] Kein freier Public-Server gefunden")
    end
else
    warn("[ServerHop] fetchServers() fehlgeschlagen")
end

--==================================================================
-- 5) Fallback: Kick & Teleport, garantiert neuer Server
--==================================================================
warn("[ServerHop] Fallback: Kick & Teleport")
pcall(function() Players.LocalPlayer:Kick("Auto-Rejoin…") end)
task.wait(1)
TeleportService:Teleport(PlaceID)
