-- tp.lua

-- HTTP-Funktion
local req = (syn and syn.request) or (http and http.request) or (request) or (fluxus and fluxus.request)
assert(req, "❗ Dein Executor unterstützt keine HTTP-Requests!")

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gameId = 85896571713843
local baseUrl = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"):format(gameId)

local serverFile = "server_ids.txt"
local cooldownFile = "server_refresh_time.txt"
local refreshCooldown = 60
local maxAttempts = 5

local function fetchWithRetry(url)
    local retries = 0
    while retries < 5 do
        local res = req({ Url = url, Method = "GET", Headers = { ["Content-Type"]="application/json" }})
        if res.StatusCode == 200 then return res.Body end
        if res.StatusCode == 429 then
            retries += 1
            local waitTime = 5 * retries
            warn("❗ Rate Limit, warte "..waitTime.."s ("..retries.."/5)")
            task.wait(waitTime)
        else
            warn("❗ Fehler HTTP "..res.StatusCode)
            return nil
        end
    end
    error("❗ Zu viele Versuche")
end

local function refreshServerIds()
    local ids = {}
    local url = baseUrl
    while url and #ids < 200 do
        local body = fetchWithRetry(url)
        if not body then break end
        local data = HttpService:JSONDecode(body)
        for _, srv in ipairs(data.data) do
            if not srv.vipServerId then table.insert(ids, srv.id) end
        end
        url = data.nextPageCursor and (baseUrl.."&cursor="..data.nextPageCursor) or nil
        task.wait(1)
    end
    if #ids == 0 then error("❗ Keine Server IDs") end
    writefile(serverFile, table.concat(ids, "
"))
    writefile(cooldownFile, tostring(os.time() + refreshCooldown))
    print("✔️ Serverliste aktualisiert:", #ids)
end

local function loadServerIds()
    local ok, content = pcall(readfile, serverFile)
    if not ok then return {} end
    local t = {}
    for line in content:gmatch("[^
]+") do t[#t+1] = line end
    return t
end

local function tryHop(servers)
    local initial = game.JobId
    for i = 1, maxAttempts do
        if #servers == 0 then break end
        local idx = math.random(#servers)
        local srv = table.remove(servers, idx)
        writefile(serverFile, table.concat(servers, "
"))
        print(("🚀 Versuch #%d: Teleport zu %s (%d übrig)"):format(i, srv, #servers))
        local suc, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(gameId, srv, player)
        end)
        if not suc then
            warn("❗ Teleport-Fehler:", err)
            task.wait(2)
        else
            task.wait(8)
            if game.JobId ~= initial then
                print("✅ Neuer Server betreten")
                return
            else
                warn("❗ Immer noch selbes Spiel, nächster Versuch")
                task.wait(2)
            end
        end
    end
    warn("❗ Max Versuche erreicht")
end

-- Hauptlogik
local function main()
    local needRefresh = true
    local ok, nextTime = pcall(function() return tonumber(readfile(cooldownFile)) end)
    if ok and nextTime and os.time() < nextTime then
        needRefresh = false
    end
    if needRefresh then
        refreshServerIds()
    end
    local servers = loadServerIds()
    if #servers == 0 then
        warn("❗ Keine Server IDs")
        return
    end
    tryHop(servers)
end

main()