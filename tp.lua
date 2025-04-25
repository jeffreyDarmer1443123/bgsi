wait(2)
--============================================================================== 
-- Robust Server-Hop v6 
-- Einmaliger Wechsel in einen öffentlichen, nicht vollen Server. 
-- Vermeidet JSON-/HTTP-Abstürze und fällt sauber auf Teleport() zurück. 
--============================================================================== 

local TeleportService   = game:GetService("TeleportService") 
local HttpService       = game:GetService("HttpService") 

local PlaceID           = game.PlaceId 
local CurrentServerId   = game.JobId 

--================================================================= 
-- Universelle HTTP-GET-Funktion (Synapse, KRNL, Fluxus, AWP, Fallback) 
--================================================================= 
local function httpGet(url) 
    if syn and syn.request then 
        return syn.request({ Url = url, Method = "GET" }).Body 
    elseif http_request then 
        return http_request({ Url = url, Method = "GET" }).Body 
    elseif request then 
        return request({ Url = url, Method = "GET" }).Body 
    else 
        return game:HttpGet(url) 
    end 
end 

--================================================================= 
-- Versucht, die erste Seite der Public-Server-API abzurufen und zu parsen 
-- Liefert eine Liste von Server-Tables oder nil bei Fehlern 
--================================================================= 
local function fetchServers() 
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PlaceID) 
    local ok, body = pcall(httpGet, url) 
    if not ok or type(body) ~= "string" then 
        warn("[ServerHop] HTTP-Request fehlgeschlagen:", tostring(body)) 
        return nil 
    end 

    -- Schnelle Prüfung, ob das überhaupt JSON sein könnte 
    if not body:match("^%s*{") then 
        warn("[ServerHop] Antwort kein JSON, raw:") 
        warn(body) 
        return nil 
    end 

    local success, data = pcall(HttpService.JSONDecode, HttpService, body) 
    if not success or type(data) ~= "table" or type(data.data) ~= "table" then 
        warn("[ServerHop] JSON-Parsing fehlgeschlagen, raw:") 
        warn(body) 
        return nil 
    end 

    return data.data 
end 

--================================================================= 
-- Filtert nur Server mit mindestens einem freien Slot und 
-- schließt die aktuelle Instanz aus 
--================================================================= 
local function filterServers(servers) 
    local valid = {} 
    for _, srv in ipairs(servers) do 
        local free = srv.maxPlayers - srv.playing 
        if srv.id ~= CurrentServerId and free > 0 then 
            table.insert(valid, srv.id) 
        end 
    end 
    return valid 
end 

--================================================================= 
-- Hauptlogik: 
-- 1) Serverliste abrufen 
-- 2) filtern 
-- 3) einmalig teleportieren oder fallback 
--================================================================= 
local servers = fetchServers() 
if servers then 
    local valid = filterServers(servers) 
    if #valid > 0 then 
        local targetId = valid[ math.random(#valid) ] 
        print("[ServerHop] Teleport zu:", targetId) 
        local ok = pcall(function() 
            TeleportService:TeleportToPlaceInstance(PlaceID, targetId) 
        end) 
        if ok then return end 
        warn("[ServerHop] TeleportToPlaceInstance fehlgeschlagen, fallback Teleport()") 
    else 
        warn("[ServerHop] Kein freier Public-Server gefunden") 
    end 
else 
    warn("[ServerHop] fetchServers() fehlgeschlagen, fallback Teleport()") 
end 

-- Fallback: einfacher Rejoin/Teleport, der intern auch nur freie Public-Server wählt 
pcall(function() 
    TeleportService:Teleport(PlaceID) 
end) 
