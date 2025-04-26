-- tp.lua

--// Services
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

--// Config
local placeId = game.PlaceId
local currentJobId = game.JobId
local serverListUrl = string.format(
    "https://games.roblox.com/v1/games/%d/servers/Public?excludeFullGames=true&limit=100",
    placeId
)

--// Cache
local cacheFile = "awp_servercache.txt"
local cacheMaxAge = 30  -- Sekunden

--// Utilities
local function warnMsg(text)
    warn("[Server-Hop] " .. text)
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

local function fetchServerList()
    local result

    -- 1) Try cache
    if typeof(isfile) == "function" and isfile(cacheFile) then
        local content
        local ok, err = pcall(function()
            content = readfile(cacheFile)
        end)

        if ok and content then
            local cache = safeDecode(content)
            if cache and cache.data and typeof(cache.data) == "table" and cache.timestamp then
                if (os.time() - cache.timestamp) < cacheMaxAge then
                    return cache.data
                end
            end
        end
    end

    -- 2) Fetch online
    for attempt = 1,5 do
        local success, response = pcall(function()
            return game:HttpGet(serverListUrl)
        end)

        if success and response then
            local data = safeDecode(response)
            if data and data.data and typeof(data.data) == "table" then
                -- Save to cache
                if typeof(writefile) == "function" then
                    pcall(function()
                        writefile(cacheFile, HttpService:JSONEncode({timestamp = os.time(), data = data.data}))
                    end)
                end
                return data.data
            else
                warnMsg("Fehler beim Parsen der Serverliste (Versuch "..attempt..")")
            end
        else
            warnMsg("Fehler beim Abrufen der Serverliste (Versuch "..attempt..")")
        end

        task.wait(1)
    end

    warnMsg("Abbruch: Serverliste konnte nicht geladen werden.")
    return nil
end

--// Main
local servers = fetchServerList()
if not servers then
    return
end

-- Filter
local validServers = {}
for _, server in ipairs(servers) do
    if server.id and server.playing and server.maxPlayers then
        if server.playing < server.maxPlayers and server.id ~= currentJobId then
            table.insert(validServers, server.id)
        end
    end
end

if #validServers == 0 then
    warnMsg("Keine passenden Server gefunden.")
    return
end

-- Shuffle Servers
math.randomseed(tick()*1000)
for i = #validServers, 2, -1 do
    local j = math.random(1, i)
    validServers[i], validServers[j] = validServers[j], validServers[i]
end

-- Try teleport
for attempt = 1, math.min(5, #validServers) do
    local targetId = validServers[attempt]
    if targetId then
        local success, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, targetId, player)
        end)
        if success then
            print("🔄 Teleportiere zu neuem Server... JobID:", targetId)
            return
        else
            warnMsg("Teleport Fehler (Versuch "..attempt.."): ".. tostring(err))
            task.wait(1)
        end
    end
end

warnMsg("Alle Teleportversuche fehlgeschlagen.")
notify("Server-Hop", "Konnte keinen neuen Server betreten.", 5)

-- Optional: Kick fallback
pcall(function()
    player:Kick("Server-Hop fehlgeschlagen")
end)
task.wait(1)
TeleportService:Teleport(placeId)
