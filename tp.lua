-- 🔁 TP.lua (komplett ausführbar über loadstring)
task.spawn(function()
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")

    local username = Players.LocalPlayer.Name
    local gameId = 85896571713843
    local dataFile = "server_data.json"
    local refreshCooldown = shared.refreshCooldown or 60
    local maxAttempts = shared.maxAttempts or 25
    local maxServerIds = shared.maxServerIds or 200
    local baseDelay = shared.baseDelay or 5

    local baseUrl = "https://games.roblox.com/v1/games/"..gameId.."/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"

    -- 🌐 Hole LockManager inline via loadstring
    local LockManager = (function()
        local url = "https://raw.githubusercontent.com/jeffreyDarmer1443123/bgsi/refs/heads/main/LockManager.lua"
        local code = game:HttpGet(url)
        return assert(loadstring(code), "LockManager Fehler")()
    end)()

    -- 🔄 Speichern / Laden
    local function loadData()
        if not isfile(dataFile) then
            return {serverIds = {}, refreshCooldownUntil = 0}
        end
        local success, data = pcall(function()
            return HttpService:JSONDecode(readfile(dataFile))
        end)
        return (success and typeof(data) == "table") and data or {serverIds = {}, refreshCooldownUntil = 0}
    end

    local function saveData(data)
        writefile(dataFile, HttpService:JSONEncode(data))
    end

    -- 🌍 Sichere HTTP-Request Methode
    local function safeRequest(opts)
        local methods = {request, http_request, syn and syn.request, fluxus and fluxus.request}
        table.insert(methods, function(o)
            return HttpService:RequestAsync({
                Url = o.Url,
                Method = o.Method,
                Headers = o.Headers or {},
                Body = o.Body,
            })
        end)

        for _, fn in ipairs(methods) do
            if fn then
                local ok, res = pcall(fn, opts)
                if ok and type(res) == "table" then
                    local code = res.StatusCode or res.code or 0
                    if code >= 200 and code < 300 then
                        return true, {
                            Body = res.Body or res.response,
                            StatusCode = code
                        }
                    end
                    return false, "HTTP-"..tostring(code)
                end
            end
        end
        return false, "HTTP fehlgeschlagen"
    end

    -- 🔄 Serverliste aktualisieren
    local function refreshServers()
        local ok, reason = LockManager.Acquire(username)
        if not ok then
            warn(username.." ⏳ Lock aktiv: "..reason)
            return false
        end

        warn(username.." 🔒 Lock übernommen – aktualisiere Serverliste...")
        local data = loadData()
        local allIds = {}
        local nextCursor = ""

        repeat
            local url = baseUrl .. (nextCursor ~= "" and "&cursor="..nextCursor or "")
            local httpOk, res = safeRequest({Url = url, Method = "GET"})
            if not httpOk then
                LockManager.Release(username)
                error("❌ HTTP fehlgeschlagen: "..res)
            end

            local parsed = HttpService:JSONDecode(res.Body)
            nextCursor = parsed.nextPageCursor or ""

            for _, server in ipairs(parsed.data or {}) do
                if type(server) == "table" and server.id and not server.vipServerId and server.playing < server.maxPlayers then
                    table.insert(allIds, server.id)
                end
            end
        until nextCursor == "" or #allIds >= maxServerIds

        if #allIds > 0 then
            data.serverIds = allIds
            data.refreshCooldownUntil = os.time() + refreshCooldown
            saveData(data)
            warn(username.." ✅ Serverliste aktualisiert: "..#allIds.." Server")
        else
            warn(username.." ⚠️ Keine Server gefunden.")
        end

        LockManager.Release(username)
        return true
    end

    -- 🚀 Teleport Logik
    local function teleportToRandomServer()
        local data = loadData()
        local originalJobId = game.JobId

        for attempt = 1, maxAttempts do
            if #data.serverIds == 0 then break end

            local idx = math.random(1, #data.serverIds)
            local sid = table.remove(data.serverIds, idx)
            saveData(data)

            warn(username.." 🚀 Versuch "..attempt..": "..sid)
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(gameId, sid)
            end)

            if ok then
                task.wait(20)
                if game.JobId ~= originalJobId then return end
            end
        end

        warn(username.." ❗ Alle Versuche fehlgeschlagen.")
    end

    -- 🧠 Hauptlogik
    local function main()
        local retry = 0
        while retry < 3 do
            local data = loadData()
            local now = os.time()

            if now < (data.refreshCooldownUntil or 0) and #data.serverIds > 0 then
                return teleportToRandomServer()
            end

            local success, err = pcall(refreshServers)
            if success then
                return teleportToRandomServer()
            else
                warn(username.." ⚠️ Fehler: "..tostring(err))
                retry += 1
                task.wait(math.random(2, 5))
            end
        end
    end

    local success, err = pcall(main)
    if not success then
        warn(username.." ❌ TP.lua Hauptfehler:", err)
    end
end)
