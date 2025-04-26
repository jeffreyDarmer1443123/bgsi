--// Services und Variablen initialisieren
wait(4)
local HttpService = game:GetService("HttpService")             -- Dienst für JSON-Verarbeitung
local TeleportService = game:GetService("TeleportService")     -- Dienst zum Teleportieren zwischen Servern
local Players = game:GetService("Players")
local player = Players.LocalPlayer                             -- Der lokale Spieler, der teleportiert wird

--// Konfiguration
local placeId = game.PlaceId   -- ID des aktuellen Spiels (Place)
local currentJobId = game.JobId   -- Server-ID des aktuellen Servers (zum Vergleich, um nicht denselben zu wählen)
local serverListUrl = string.format(
    "https://games.roblox.com/v1/games/%d/servers/Public?excludeFullGames=true&limit=100",
    placeId
)
-- Hinweis: 'excludeFullGames=true' bewirkt, dass volle Server von der API gar nicht erst zurückgegeben werden&#8203;:contentReference[oaicite:9]{index=9}.
-- Sortierung (Asc/Desc) kann bei Bedarf hinzugefügt werden. Standard ist Asc (aufsteigend).

--// Cache-Einstellungen
local cacheFile = "awp_servercache.txt"
local cacheMaxAge = 30  -- max. 120 Sekunden (2 Minuten) Cache-Gültigkeit

--// Hilfsfunktionen für Notifications (Benachrichtigungen)
local function notify(title, text, duration)
    -- Zeigt eine einfache Benachrichtigung am Bildschirmrand an&#8203;:contentReference[oaicite:10]{index=10}.
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {
            Title = title or "Hinweis",
            Text = text or "",
            Duration = duration or 5
        })
    end)
end

--// Schritt 1: Versuche, Serverliste aus Cache zu laden (falls vorhanden und frisch)
local serverData   -- Variable für die Serverliste (Tabelle mit Serverinformationen)
local useCache = false
if typeof(isfile) == "function" and isfile(cacheFile) then
    -- Datei existiert, versuche zu lesen
    local cacheContent
    local success, err = pcall(function()
        cacheContent = readfile(cacheFile)
    end)
    if success and cacheContent then
        -- Versuche, JSON zu parsen
        local success2, cacheTable = pcall(HttpService.JSONDecode, HttpService, cacheContent)
        if success2 and typeof(cacheTable) == "table" and cacheTable.data and typeof(cacheTable.data) == "table" then
            local age = os.time() - (cacheTable.timestamp or 0)
            if age < cacheMaxAge then
                serverData = cacheTable.data
                useCache = true
            else
                warn("🕑 Cache abgelaufen, lade neue Serverliste...")
            end
        else
            warn("⚠️ Cache fehlerhaft oder unverständlich, ignoriere Cache.")
        end

            
        else
            -- Cache-Datei ist korrupt oder kein gültiges JSON
            warn("Server-Hop", "Cache-Daten ungültig, lade Serverliste neu...", 5)
        end
    else
        -- Lesen schlug fehl (z.B. Berechtigung oder unerwarteter Fehler)
        warn("Server-Hop", "Cache konnte nicht gelesen werden, lade neu...", 5)
    end
end

--// Schritt 2: Falls kein gültiger Cache genutzt wird, Serverliste per HTTP von Roblox-API abrufen
if not serverData then
    local httpSuccess = false
    local httpResponse
    for attempt = 1, 5 do
        local ok, result = pcall(game.HttpGet, game, serverListUrl)
        if ok and result then
            -- HTTP-Aufruf erfolgreich, Ergebnis (JSON-Text) liegt in 'result'
            -- Versuche JSON zu dekodieren
            local ok2, data = pcall(HttpService.JSONDecode, HttpService, result)
            if ok2 and typeof(data) == "table" and data.data and typeof(data.data) == "table" then
                serverData = data.data
                httpSuccess = true
                break
            else
                warn("⚠️ Server-Hop Fehler: Serverliste unverständlich (Versuch "..attempt.." von 5)")
            end

            -- HTTP-Fehler (Kein Zugriff oder Timeout etc.)
            warn("Server-Hop", "Fehler: Konnte Serverliste nicht abrufen (Versuch "..attempt.." von 5)", 5)
        end
        wait(1)  -- kurze Pause vor nächstem Versuch (1 Sekunde)
    end
    if not httpSuccess then
        -- Nach 5 Fehlversuchen beim Abruf -> Abbruch
        warn("Server-Hop", "Abbruch: Serverliste konnte nicht geladen werden.", 5)
        return  -- Skript endet hier ohne Teleport
    end

    -- Erfolgreich neue Serverliste erhalten, speichere in Cache-Datei
    if typeof(writefile) == "function" then
        local success, err = pcall(function()
            local cacheTable = {
                timestamp = os.time(),
                data = serverData
            }
            local jsonStr = HttpService:JSONEncode(cacheTable)
            writefile(cacheFile, jsonStr)
        end)
        if not success then
            -- Fehler beim Schreiben des Caches (nicht kritisch, nur Hinweis)
            warn("Server-Hop", "warnung: Konnte Serverliste nicht cachen.", 5)
        end
    end
end

-- // Schritt 3: Serverliste filtern und geeigneten Server auswählen
local validServers = {}
if type(serverData) == "table" then
    for _, server in ipairs(serverData) do
        local playing = server.playing or 0
        local maxPlayers = server.maxPlayers or 0
        local serverId = server.id

        -- Prüfe auf Spielfülle und ob ServerId existiert
        if serverId and (maxPlayers == 0 or playing < 8) then
            -- (Wir ignorieren vipServerId, weil es in deinem JSON nicht existiert)
            if serverId ~= currentJobId then
                table.insert(validServers, serverId)
            end
        end
    end
end


if #validServers == 0 then
    -- Keine passenden Server gefunden
    warn("Server-Hop", "Kein anderer Server verfügbar. Abbruch.", 5)
    return  -- es gibt keinen Zielserver zum Teleportieren
end

-- Optional: Serverliste mischen, um bei wiederholter Nutzung nicht immer denselben Server zu nehmen
math.randomseed(tick() * 1000)
for i = #validServers, 2, -1 do
    local j = math.random(1, i)
    validServers[i], validServers[j] = validServers[j], validServers[i]
end
-- Jetzt ist validServers in zufälliger Reihenfolge

--// Schritt 4: Teleportation - Versuche bis zu 5-mal, einen Server zu teleportieren
local teleported = false
for attempt = 1, math.min(5, #validServers) do
    local targetJobId = validServers[attempt]
    if targetJobId then
        -- Versuche Teleport zum Server mit der ID targetJobId
        local ok, err = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, placeId, targetJobId, player)
        if ok then
            print("Joining", targetJobId)
            wait(5) -- <<< GIB ZEIT ZUM TELEPORTIEREN!!!
            local newcurrentJobId = game.JobId
            if newcurrentJobId ~= currentJobId then
                teleported = true
                break  -- Erfolgreich, raus aus der Schleife
            else
                warn("Serverwechsel fehlgeschlagen, gleicher Server. Versuche nächsten Server...")
            end
        else
            warn("Teleport Fehler (Versuch "..attempt.." von 5):", err)
            wait(1)
        end
    end
end

--// Schritt 5: Ergebnis prüfen und ggf. Abbruchmeldung
if not teleported then
    if #validServers >= 5 then
        -- 5 Versuche wurden unternommen (weil mindestens 5 Server zur Verfügung standen)
        warn("Server-Hop", "Serverwechsel abgebrochen nach 5 Fehlversuchen.", 5)
        pcall(function() Players.LocalPlayer:Kick("") end)
        task.wait(1)
        TeleportService:Teleport(PlaceID)
    else
        -- Weniger als 5 mögliche Server insgesamt und alle fehlgeschlagen
        warn("Server-Hop", "Serverwechsel abgebrochen - kein erfolgreicher Wechsel möglich.", 5)
    end
end
