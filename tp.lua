-- ServerHopper.lua (Version 2.6 – nutzt Cache & wählt zufällige Server)

-- Services
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local player          = Players.LocalPlayer

-- Konfiguration
local PLACE_ID         = game.PlaceId
local CACHE_FILE       = "ServerCache.txt"
local BLACKLIST_FILE   = "Blacklist.txt"
local CACHE_DURATION   = 30        -- Sekunden, wie lange der Cache gültig bleibt
local MIN_FREE_SLOTS   = 3
local MAX_API_ATTEMPTS = 3
local BASE_URL_FMT     = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100%s"

-- Laufzeit-Variablen
local serverBlacklist = {}
local lastRefresh     = 0

-- Initialisiere den Zufallsgenerator
math.randomseed(os.time())

-- Hilfsfunktionen ----------------------------------------------------------

local function log(msg, isWarn)
    warn(("[%s] ServerHopper: %s"):format(isWarn and "WARN" or "INFO", msg))
end

local function safeReadFile(name)
    local ok, c = pcall(readfile, name)
    return ok and c or nil
end

local function safeWriteFile(name, content)
    pcall(writefile, name, content)
end

-- Blacklist verwalten ------------------------------------------------------

local function loadBlacklist()
    local c = safeReadFile(BLACKLIST_FILE)
    serverBlacklist = c and HttpService:JSONDecode(c) or {}
end

local function saveBlacklist()
    safeWriteFile(BLACKLIST_FILE, HttpService:JSONEncode(serverBlacklist))
end

local function blacklistServer(id)
    serverBlacklist[id] = os.time() + 300  -- 5 Minuten Sperre
    saveBlacklist()
    log("Server geblockt: " .. id, true)
end

-- Cache verwalten ----------------------------------------------------------

local function readCache()
    local c = safeReadFile(CACHE_FILE)
    if not c then return nil end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, c)
    if ok and data.timestamp and (os.time() - data.timestamp) < CACHE_DURATION then
        return data.servers
    end
    return nil
end

local function writeCache(list)
    local payload = {
        timestamp = os.time(),
        servers   = list,
    }
    local ok, json = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then
        log("JSON-Encode Fehler: " .. tostring(json), true)
        return
    end
    local wOk, err = pcall(writefile, CACHE_FILE, json)
    if wOk then
        log("Cache geschrieben: " .. #list .. " Server")
    else
        log("Cache-Write Fehler: " .. tostring(err), true)
    end
end

-- HTTP-Wrapper -------------------------------------------------------------

local function robustHttpGet(url)
    -- 1) syn.request
    if syn and syn.request then
        local ok, res = pcall(function()
            return syn.request({Url = url, Method = "GET"}).Body
        end)
        if ok and type(res) == "string" then
            return res
        end
    end
    -- 2) http.request
    if http and http.request then
        local ok, res = pcall(function()
            return http.request({Url = url}).Body
        end)
        if ok and type(res) == "string" then
            return res
        end
    end
    -- 3) game:HttpGet
    local ok, res = pcall(function()
        return game:HttpGet(url, true)
    end)
    if ok and type(res) == "string" then
        return res
    end
    return nil
end

-- API-Abfrage mit Backoff --------------------------------------------------

local function fetchServers(cursor)
    local cursorParam = cursor and ("&cursor=" .. cursor) or ""
    local url = string.format(BASE_URL_FMT, PLACE_ID, cursorParam)
    log("API-Anfrage: " .. url)
    for attempt = 1, MAX_API_ATTEMPTS do
        local body = robustHttpGet(url)
        if body then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
            if ok and type(data) == "table" then
                return data
            end
        end
        task.wait(2 ^ attempt)
    end
    return nil
end

-- Filter für joinbare, öffentliche Server ----------------------------------

local function filterServers(rawList)
    loadBlacklist()
    local valid = {}

    for _, srv in ipairs(rawList) do
        local id   = srv.id
        local play = tonumber(srv.playing)
        local cap  = tonumber(srv.maxPlayers)
        if not id or id == game.JobId or serverBlacklist[id] then
            -- überspringen
        else
            -- 1) gekaufte Private Server (VIP)
            if tonumber(srv.vipServerId or 0) > 0 then
                -- überspringen
            else
                -- 2) reservierte Instanzen
                local code = srv.accessCode or srv.reservedServerAccessCode or ""
                if code ~= "" and code ~= "00000000-0000-0000-0000-000000000000" then
                    -- überspringen
                else
                    -- 3) freie Slots prüfen
                    if play and cap then
                        local free = cap - play
                        if free >= MIN_FREE_SLOTS then
                            table.insert(valid, { id = id, free = free })
                        end
                    end
                end
            end
        end
    end

    table.sort(valid, function(a, b) return a.free > b.free end)
    return valid
end

-- Beste Server ermitteln (Cache nutzen oder API abrufen) -------------------

local function findBestServer()
    -- 1) versuche Cache
    local cached = readCache()
    if cached and #cached > 0 then
        log("Verwende Cache mit " .. #cached .. " Servern")
        return cached
    end

    -- 2) sonst neuen Fetch & Filter
    local all, cursor = {}, nil
    task.wait(2)  -- kurz warten, damit vorheriger Teleport wirklich durch ist
    for _ = 1, 5 do
        local page = fetchServers(cursor)
        if not page or not page.data then break end
        log("Verarbeite " .. #page.data .. " Server")
        for _, srv in ipairs(page.data) do
            if type(srv) == "table" then
                table.insert(all, srv)
            end
        end
        cursor = page.nextPageCursor
        if not cursor then break end
        task.wait(0.2)
    end

    local valid = filterServers(all)
    if #valid > 0 then
        writeCache(valid)
        log("Gültige Server: " .. #valid)
    else
        log("Keine passenden Server – leerer Cache", true)
        writeCache({})
    end
    return valid
end

-- Utility: mischt eine Liste in-place (Fisher-Yates)
local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

-- Teleport-Versuch ---------------------------------------------------------

local function attemptTeleport()
    local list = findBestServer() or {}
    if #list == 0 then
        return false
    end

    -- mische die Reihenfolge, damit nicht immer derselbe Server gewählt wird
    shuffle(list)

    for _, srv in ipairs(list) do
        log("Teleport init zu: " .. srv.id)
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, srv.id, player)
        end)
        if ok then
            return true
        else
            log("Teleport-Fehler: " .. tostring(err), true)
            if tostring(err):find("773") or tostring(err):find("Unauthorized") then
                blacklistServer(srv.id)
            end
        end
        task.wait(1)
    end
    return false
end

-- Haupt-Loop ---------------------------------------------------------------

while RunService:IsRunning() do
    if os.time() - lastRefresh > CACHE_DURATION then
        lastRefresh = os.time()
        if not attemptTeleport() then
            log("Fallback-Teleport...", true)
            pcall(TeleportService.Teleport, TeleportService, PLACE_ID)
        end
    end
    task.wait(5)
end
