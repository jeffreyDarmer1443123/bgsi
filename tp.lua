-- tp_ultra.lua

--// Services
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

--// Config
local placeId = game.PlaceId
local currentJobId = game.JobId
local cacheFile = "awp_servercache.txt"
local cacheMaxAge = 60 -- Sekunden

--// Utilities
local function warnMsg(text)
    warn("[Server-Hop] " .. tostring(text))
end

local function notify(title, text, duration)
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5
        })
    end)
end

local function safeDecode(jsonStr)
    local success, result = pcall(function()
        return HttpService:JSONDecode(jsonStr)
    end)
    if success and type(result) == "table" then
        return result
    end
    return nil
end

local function loadCache()
    if typeof(isfile) == "function" and isfile(cacheFile) then
        local success, content = pcall(readfile, cacheFile)
        if success and content then
            local decoded = safeDecode(content)
            if decoded and decoded.timestamp and decoded.data then
                if os.time() - decoded.timestamp < cacheMaxAge then
                    return decoded.data
                end
            end
        end
    end
    return nil
end

local function saveCache(data)
    if typeof(writefile) == "function" then
        pcall(function()
            writefile(cacheFile, HttpService:JSONEncode({ timestamp = os.time(), data = data }))
        end)
    end
end

local function fetchAllServers()
    local servers = {}
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?excludeFullGames=true&limit=100", placeId)
    local cursor = nil

    for page = 1, 5 do -- Maximal 5 Seiten laden
        local queryUrl = url .. (cursor and ("&cursor=" .. cursor) or "")
        local success, response = pcall(function()
            return game:HttpGet(queryUrl)
        end)

        if success and response then
            local data = safeDecode(response)
            if data and data.data then
                for _, server in ipairs(data.data) do
                    table.insert(servers, server)
                end
                cursor = data.nextPageCursor
                if not cursor then
                    break
                end
            else
                warnMsg("Fehler beim Parsen der Serverdaten (Seite "..page..")")
                break
            end
        else
            warnMsg("HTTP Fehler beim Laden der Serverliste (Seite "..page..")")
            break
        end
        task.wait(1)
    end

    if #servers > 0 then
        saveCache(servers)
    end

    return servers
end

local function fetchServers()
    return loadCache() or fetchAllServers()
end

--// Main
local servers = fetchServers()
if not servers or #servers == 0 then
    warnMsg("Keine Serverdaten verfügbar.")
    return
end

-- Filter und sortieren
local validServers = {}
for _, server in ipairs(servers) do
    if server.id and server.playing and server.maxPlayers then
        if server.playing < server.maxPlayers and server.id ~= currentJobId then
            table.insert(validServers, {
                id = server.id,
                playing = server.playing,
                maxPlayers = server.maxPlayers,
                ping = server.ping or math.random(30, 120) -- Fallback falls Ping fehlt
            })
        end
    end
end

if #validServers == 0 then
    warnMsg("Keine passenden Server gefunden.")
    return
end

-- Sortieren nach: wenig Spieler -> niedriger Ping

-- Erst nach Ping
table.sort(validServers, function(a, b)
    return a.ping < b.ping
end)

-- Dann nach Spielerzahl (Priorität auf freie Slots)
table.sort(validServers, function(a, b)
    return a.playing < b.playing
end)

-- Shuffle leicht, damit nicht immer derselbe Server genommen wird
math.randomseed(tick()*1000)
for i = #validServers, 2, -1 do
    local j = math.random(1, i)
    validServers[i], validServers[j] = validServers[j], validServers[i]
end

-- Versuche intelligent zu verbinden
for attempt = 1, math.min(7, #validServers) do
    local target = validServers[attempt]
    if target and target.id then
        print(string.format("🔄 Teleportiere zu Server: %s (%d/%d Spieler, %d ms)", target.id, target.playing, target.maxPlayers, target.ping))
        local success, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, target.id, player)
        end)
        if success then
            notify("Server-Hop", "Teleport zu neuem Server erfolgreich!", 5)
            return
        else
            warnMsg("Teleport Fehler (Versuch "..attempt.."): ".. tostring(err))
            task.wait(1)
        end
    end
end

-- Alles gescheitert
warnMsg("Alle Teleportversuche fehlgeschlagen.")
notify("Server-Hop", "Konnte keinen neuen Server betreten.", 5)
pcall(function()
    player:Kick("Server-Hop fehlgeschlagen")
end)
task.wait(1)
TeleportService:Teleport(placeId)
