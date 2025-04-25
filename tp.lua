--// Roblox Server-Hop Skript: Wechselt einmalig auf einen anderen öffentlichen Server desselben Spiels.

-- Services abrufen
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

-- Wichtige Kennungen des aktuellen Spiels/Servers
local placeId = game.PlaceId              -- ID des Spiels (Place), bleibt gleich für alle Server dieses Spiels
local currentJobId = game.JobId           -- eindeutige ID des aktuellen Server-Instances (JobId)

-- Roblox Public Server API URL vorbereiten:
-- Diese API liefert eine Liste öffentlicher Server für den gegebenen Place. Wir limitieren auf 100 Server pro Abfrage.
local serversApiUrl = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
-- Hinweis: sortOrder=Asc liefert i.d.R. die am wenigsten bevölkerten Server zuerst&#8203;:contentReference[oaicite:6]{index=6}. 
-- Man könnte auch "Desc" verwenden, um vollere Server zuerst zu erhalten – beide Ansätze vermeiden volle Server, da wir das selbst prüfen.

-- Funktion, um Serverliste abzurufen (mit optionalem Cursor für Folgeseiten)
local function getServerPage(cursor)
    local url = serversApiUrl
    if cursor then
        url = url .. "&cursor=" .. cursor  -- Cursor anhängen, um die nächste Seite der Serverliste abzurufen&#8203;:contentReference[oaicite:7]{index=7} 
    end
    -- HTTP-GET Anfrage senden (nutzt Exploit-Funktion game:HttpGet, kein HttpEnabled nötig bei Exploits)
    local success, response = pcall(function()
        return game:HttpGet(url)
    end)
    if not success then
        return nil, "HTTP request failed"
    end
    -- JSON-Antwort parsen
    local success2, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)
    if not success2 then
        return nil, "JSON decode failed"
    end
    return data, nil
end

-- Suche nach einem geeigneten Server und Teleport durchführen
local foundNewServer = false
local nextPageCursor = nil  -- für die Seitennavigation der Serverliste

repeat
    local serverData, err = getServerPage(nextPageCursor)
    if not serverData then
        warn("[ServerHop] Konnte Serverliste nicht abrufen: " .. tostring(err))
        break  -- Abbrechen, falls die Serverliste gar nicht geladen werden kann
    end

    -- Durchlaufe die Server-Daten dieser Seite
    for _, server in ipairs(serverData.data) do
        -- Überprüfen, ob Server geeignet ist:
        -- 1. Nicht der aktuelle Server (vergleiche JobId)&#8203;:contentReference[oaicite:8]{index=8}
        -- 2. Nicht voll (playing < maxPlayers bedeutet es gibt freie Plätze)&#8203;:contentReference[oaicite:9]{index=9}
        if server.id ~= currentJobId and server.playing < server.maxPlayers then
            warn(string.format("[ServerHop] Wechsle zu Server %s (%d/%d Spieler)", server.id, server.playing, server.maxPlayers))
            -- Teleport zum gefundenen Server ausführen
            local teleportSuccess, teleportError = pcall(function()
                TeleportService:TeleportToPlaceInstance(placeId, server.id, Players.LocalPlayer)
            end)
            if teleportSuccess then
                foundNewServer = true  -- Teleport wurde angestoßen
                break  -- aus der Server-Schleife ausbrechen
            else
                warn("[ServerHop] Teleport fehlgeschlagen: " .. tostring(teleportError))
                -- Falls dieser Teleportversuch fehlschlug, nächsten Server probieren (falls vorhanden)
            end
        end
    end

    -- Wenn ein Server gefunden wurde (Teleport angestoßen), muss nicht weiter gesucht werden
    if foundNewServer then
        break  -- bricht die repeat-Schleife
    end

    -- Falls es eine Folgeseite gibt und wir noch keinen Server gefunden haben, Cursor setzen und nächste Seite laden
    nextPageCursor = serverData.nextPageCursor
until not nextPageCursor  -- Schleife wiederholen, solange ein nextPageCursor existiert und noch kein Server gefunden wurde

-- Fallback: Wenn kein passender Server gefunden oder Teleport nicht erfolgreich war
if not foundNewServer then
    warn("[ServerHop] Kein geeigneter Server gefunden oder Teleport fehlgeschlagen. Versuche Standard-Teleport...")
    pcall(function()
        -- Standard-Teleport zum selben Place (Roblox entscheidet den Server):
        TeleportService:Teleport(placeId, Players.LocalPlayer)
        -- Hinweis: Teleport(placeId) ohne explizite Instance kann ggf. ebenfalls einen neuen Server instanziieren,
        -- falls kein geeigneter freier Server vorhanden ist.
    end)
end
