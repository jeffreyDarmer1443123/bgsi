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
local cacheMaxAge = 120  -- max. 120 Sekunden (2 Minuten) Cache-Gültigkeit

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
        if success2 and type(cacheTable) == "table" and cacheTable.timestamp and cacheTable.data then
            local age = os.time() - tonumber(cacheTable.timestamp)
            if age < cacheMaxAge then
                -- Cache ist jünger als 2 Minuten, wir verwenden diese Daten
                serverData = cacheTable.data
                useCache = true
            else
                -- Cache ist zu alt
                -- (Kein Fehler, wir holen gleich frische Daten. Kein Notify nötig.)
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
            if ok2 and type(data)=="table" and data.data then
                serverData = data.data  -- 'data.data' enthält die Serverliste (Array)
                httpSuccess = true
                -- Im Erfolgsfall die Schleife abbrechen
                break
            else
                -- JSON-Parse-Fehler (z.B. API hat ungültige Antwort geliefert)
                warn("Server-Hop", "Fehler: Serverliste unverständlich (Versuch "..attempt.." von 5)", 5)
            end
        else
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

--// Schritt 3: Serverliste filtern und geeigneten Server auswählen
-- Falls API zusätzliche Seiten hatte, könnten weitere Anfragen nötig sein. In diesem Skript betrachten wir die erste erhaltene Seite.
local validServers = {}
if type(serverData) == "table" then
    for _, server in ipairs(serverData) do
        -- Prüfe, ob Server gültig (nicht voll, kein VIP, nicht aktueller Server)
        local playing = server.playing or 0
        local maxPlayers = server.maxPlayers or 0
        local isVIP = server.vipServerId ~= nil and server.vipServerId ~= "" and server.vipServerId ~= 0
        if (maxPlayers == 0 or playing < maxPlayers)  -- nicht voll besetzt
           and not isVIP                              -- kein VIP/Privatserver
           and server.id ~= currentJobId              -- nicht der aktuelle Server
        then
            table.insert(validServers, server.id)
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
            
            if game.JobId != currentJobId then
                teleported = true
                break  -- Teleport erfolgreich initiiert; Schleife verlassen
            end
        else
            -- Teleport fehlgeschlagen, Fehler abfangen und melden
            warn("Server-Hop", "Teleport fehlgeschlagen (Versuch "..attempt.." von 5)", 5)
            wait(1)  -- kurze Wartezeit vor dem nächsten Versuch
        end
    end
end

--// Schritt 5: Ergebnis prüfen und ggf. Abbruchmeldung
if not teleported then
    if #validServers >= 5 then
        -- 5 Versuche wurden unternommen (weil mindestens 5 Server zur Verfügung standen)
        warn("Server-Hop", "Serverwechsel abgebrochen nach 5 Fehlversuchen.", 5)
    else
        -- Weniger als 5 mögliche Server insgesamt und alle fehlgeschlagen
        warn("Server-Hop", "Serverwechsel abgebrochen - kein erfolgreicher Wechsel möglich.", 5)
    end
end
