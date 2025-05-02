-- EggCheck.lua

local HttpService = game:GetService("HttpService")
local requestFunc = (syn and syn.request) or (http and http.request) or (request) or (fluxus and fluxus.request)

-- Konfiguration
local cfg = shared.config or {
    webhookUrl = shared.webhookUrl,
    eggNames = shared.eggNames,
    requiredLuck = shared.requiredLuck,
    minTime = shared.minTime,
}

-- Validierung
if not cfg.requiredLuck or not cfg.eggNames or not cfg.webhookUrl then
    warn("⚠️ Fehlende Konfiguration in shared.config!")
    shared.eggCheckFinished = true
    return
end

-- HTTP POST Wrapper
local function httpPost(url, body)
    local headers = { ["Content-Type"] = "application/json" }
    if requestFunc then
        return requestFunc({ Url = url, Method = "POST", Headers = headers, Body = body })
    else
        return HttpService:RequestAsync({ Url = url, Method = "POST", Headers = headers, Body = body })
    end
end

-- Webhook senden
local function sendWebhookEmbed(eggName, luck, timeText, height, jobId, placeId)
    local isManEgg = eggName:lower() == "silly-egg"
    local color = isManEgg and 0x9B59B6 or 0x2ECC71
    local mention = isManEgg and "<@palkins7>" or ""
    local serverLink = ("roblox://experiences/start?placeId=%d&gameInstanceId=%s"):format(placeId, jobId)

    local payload = {
        content = mention,
        embeds = {{
            title = "🥚 Ei gefunden!",
            url = serverLink,
            color = color,
            fields = {
                { name="🐣 Egg", value=eggName, inline=true },
                { name="💥 Luck", value=tostring(luck), inline=true },
                { name="⏳ Zeit", value=timeText or "N/A", inline=true },
                { name="📏 Höhe", value=string.format("%.2f", height or 0), inline=true },
                { name="🔗 Server Link", value=serverLink, inline=false },
            },
            footer = { text = ("🧭 Server: %s | Spiel: %d"):format(jobId, placeId) },
        }},
    }
    local data = HttpService:JSONEncode(payload)
    local ok, response = pcall(httpPost, cfg.webhookUrl, data)
    if not ok then
        warn("❌ Webhook-Request fehlgeschlagen:", response)
        return
    end
    local status = response.StatusCode or response.status
    local success = response.Success or (status >=200 and status <300)
    warn(("📬 Webhook Status %d (Success=%s)"):format(status, tostring(success)))
    if response.Body then warn("📑 Body:", response.Body) end
end

-- Hilfsfunktionen
local function getEggStats(folder)
    local gui = folder:FindFirstChild("Display") and folder.Display:FindFirstChildWhichIsA("SurfaceGui")
    if not gui then return end
    local luckText = gui:FindFirstChild("Icon") and gui.Icon:FindFirstChild("Luck")
    local timer = gui:FindFirstChild("Timer") or gui:FindFirstChildWhichIsA("TextLabel")
    return tonumber(luckText and luckText.Text:match("%d+")), timer and timer.Text
end

-- Rifts prüfen
local rifts = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then warn("❌ Rifts nicht gefunden."); shared.eggCheckFinished=true; return end

-- Kandidaten sammeln
local candidates = {}
for _, egg in ipairs(rifts:GetChildren()) do
    if table.find(cfg.eggNames, egg.Name) then
        table.insert(candidates, egg)
    end
end
if #candidates == 0 then
    warn("❌ Keine Eggs der Namen: "..table.concat(cfg.eggNames, ", "))
    shared.eggCheckFinished = true
    return
end

-- Bestes Egg finden
local bestEgg, bestLuck, bestTime = nil, -1, nil
for _, egg in ipairs(candidates) do
    local luck, timeText = getEggStats(egg)
    if luck and luck > bestLuck then
        bestEgg, bestLuck, bestTime = egg, luck, timeText
    end
end
if not bestEgg then warn("❌ Kein Luck-Wert ermittelt."); shared.eggCheckFinished=true; return end

-- Zeit parsen
local function parseTime(txt)
    if not txt then return nil end
    local m, s = txt:match("^(%d+):(%d+)$")
    if m and s then return tonumber(m)*60 + tonumber(s) end
    local n = tonumber(txt:match("(%d+)"))
    if n then return n end
    return nil
end
local numericTime = parseTime(bestTime)

local ok = bestLuck >= cfg.requiredLuck and numericTime and numericTime >= cfg.minTime
local icon = ok and "✅" or "❌"
local comp = ok and "≥" or "<"
local yPos = bestEgg:FindFirstChild("Output") and bestEgg.Output.Position.Y or 0

local output = ("%s '%s': Luck %d %s %d | Zeit: %s | Y=%.2f")
    :format(icon, bestEgg.Name, bestLuck, comp, cfg.requiredLuck, bestTime or "N/A", yPos)
if ok then
    print(output)
    print("📡 Sende Webhook...")
    sendWebhookEmbed(bestEgg.Name, bestLuck, bestTime, yPos, game.JobId, game.PlaceId)
    shared.foundEgg = true
else
    warn(output)
end

shared.eggCheckFinished = true