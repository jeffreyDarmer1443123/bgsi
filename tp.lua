wait(4)
--==================================================================
-- tp.lua – Einmaliger, zuverlässiger Server-Hop (Client/Executor-kompatibel)
-- Läuft komplett im LocalScript/Executor (Synapse, KRNL, Fluxus, AWP u.a.)
--==================================================================

local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")

local PlaceID      = game.PlaceId
local CurrentJobId = game.JobId

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
        warn("[ServerHop] Rate-Limit erkannt: Warte 10 Sekunden")
        task.wait(10)
        return nil
    end

    return data.data
end

--==================================================================
-- 4) Wähle eine zufällige, andere Instanz aus der Liste und teleportiere
--==================================================================
task.wait(1)  -- kurz warten, damit TeleportService bereit ist
local servers = fetchServers()
if servers then
    local valid = {}
    for _, srv in ipairs(servers) do
        if srv.id ~= CurrentJobId and (srv.maxPlayers - srv.playing) > 0 then
            table.insert(valid, srv.id)
        end
    end
    if #valid > 0 then
        local targetId = valid[math.random(#valid)]
        warn("[ServerHop] Versuche TeleportToPlaceInstance →", targetId)

        local ok, err = pcall(function()
            -- TeleportToPlaceInstance ist oft server-only; kann client-seitig no-op sein
            TeleportService:TeleportToPlaceInstance(PlaceID, targetId)
        end)

        -- Fallback-Mechanismus: Wenn nach 5 Sekunden kein Serverwechsel passiert, kicken/teleporten
        task.delay(5, function()
            if game.JobId == CurrentJobId then
                warn("[ServerHop] TeleportToPlaceInstance offenbar fehlgeschlagen, Kick & Teleport")
                pcall(function() Players.LocalPlayer:Kick("Auto-Rejoin…") end)
                task.wait(1)
                TeleportService:Teleport(PlaceID)
            end
        end)

        return
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
