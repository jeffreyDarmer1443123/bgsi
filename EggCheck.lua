-- EggCheck.lua
local HttpService = game:GetService("HttpService")

-- Sicherstellen, dass shared-Variablen existieren
local requiredLuck = shared.requiredLuck
local eggNames     = shared.eggNames
local webhookUrl   = shared.webhookUrl

if not requiredLuck then
    warn("⚠️ Kein Luck in shared.requiredLuck definiert!")
    shared.eggCheckFinished = true
    return
end
if not eggNames then
    warn("⚠️ Keine EggNames in shared.eggNames definiert!")
    shared.eggCheckFinished = true
    return
end
if not webhookUrl then
    warn("⚠️ Keine Webhook-URL in shared.webhookUrl definiert!")
    shared.eggCheckFinished = true
    return
end

-- Webhook-Funktion mit Server-Link
local function sendWebhookEmbed(eggName, luck, time, height, jobId, placeId)
    local isManEgg   = eggName:lower() == "silly-egg"
    local embedColor = isManEgg and 0x9B59B6 or 0x2ECC71
    local mention    = isManEgg and "<@palkins7>" or ""
    -- Deep-Link zum aktuellen Server
    local serverLink = ("https://www.roblox.com/games/start?placeId=%d&jobId=%s")
                        :format(placeId, jobId)

    local payload = {
        content = mention,
        embeds = {{
            title = "🥚 Ei gefunden!",
            url   = serverLink,      -- klickbarer Titel
            color = embedColor,
            fields = {
                { name = "🐣 Egg",          value = eggName,        inline = true },
                { name = "💥 Luck",         value = tostring(luck), inline = true },
                { name = "⏳ Zeit",         value = time or "N/A",  inline = true },
                { name = "📏 Höhe",         value = string.format("%.2f", height or 0), inline = true },
                { name = "🔗 Server Link",  value = serverLink,     inline = false },
            },
            footer = {
                text = string.format("🧭 Server: %s | Spiel: %d", jobId, placeId)
            }
        }}
    }

    local jsonData = HttpService:JSONEncode(payload)
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"

    local success, err = pcall(function()
        if executor:find("synapse") then
            syn.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = jsonData })
        elseif executor:find("krnl") then
            http.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = jsonData })
        elseif executor:find("fluxus") then
            fluxus.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = jsonData })
        elseif executor:find("awp") then
            request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = jsonData })
        else
            HttpService:PostAsync(webhookUrl, jsonData)
        end
    end)

    if not success then
        warn("❌ Webhook fehlgeschlagen:", err)
    end
end

-- Hilfsfunktion: Luck und Timer aus Egg lesen
local function getEggStats(eggFolder)
    local gui = eggFolder:FindFirstChild("Display")
                and eggFolder.Display:FindFirstChildWhichIsA("SurfaceGui")
    if not gui then return nil, nil end

    local luckText = gui:FindFirstChild("Icon") and gui.Icon:FindFirstChild("Luck")
    local timer    = gui:FindFirstChild("Timer") or gui:FindFirstChildWhichIsA("TextLabel")
    local luckVal  = luckText and tonumber(luckText.Text:match("%d+")) or nil
    local timeText = timer and timer.Text or nil
    return luckVal, timeText
end

-- Suche nach Eggs
local rifts = workspace:FindFirstChild("Rendered")
             and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then
    warn("❌ Ordner Workspace.Rendered.Rifts nicht gefunden.")
    shared.eggCheckFinished = true
    return
end

-- Optional: Anzeige von silly-egg
local manEgg = rifts:FindFirstChild("silly-egg")
if manEgg then
    local luck, timeText = getEggStats(manEgg)
    local yInfo = ""
    local outputPart = manEgg:FindFirstChild("Output")
    if outputPart and outputPart:IsA("BasePart") then
        yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
    end
    print(("✅ 'silly-egg': Luck %s | Zeit %s%s")
          :format(luck or "n/A", timeText or "N/A", yInfo))
end

-- Filter Kandidaten
local candidates = {}
for _, eggFolder in ipairs(rifts:GetChildren()) do
    if eggFolder.Name ~= "silly-egg"
       and table.find(eggNames, eggFolder.Name) then
        table.insert(candidates, eggFolder)
    end
end

if #candidates == 0 then
    warn(("❌ Kein Egg mit den Namen %s gefunden.")
         :format(table.concat(eggNames, ", ")))
    shared.eggCheckFinished = true
    return
end

-- Bestes Egg auswählen
local bestEgg, bestLuck, bestTime
for _, ef in ipairs(candidates) do
    local luck, timeText = getEggStats(ef)
    if luck and (not bestLuck or luck > bestLuck) then
        bestEgg  = ef
        bestLuck = luck
        bestTime = timeText
    end
end

if not bestEgg then
    warn(("❌ Luck-Wert für Eggs %s konnte nicht ermittelt werden.")
         :format(table.concat(eggNames, ", ")))
    shared.eggCheckFinished = true
    return
end

-- Entscheidung & Webhook
local function parseTimeString(text)
    if not text then return nil end
    local m, s = text:match("^(%d+):(%d+)$")
    if m and s then return tonumber(m)*60 + tonumber(s) end
    return tonumber(text)
end

local numericTime = parseTimeString(bestTime)
local ok = bestLuck >= requiredLuck and numericTime
           and numericTime >= shared.minTime
local icon = ok and "✅" or "❌"
local comp = ok and "≥" or "<"
local timeInfo = bestTime and (" | Zeit übrig: "..bestTime) or ""

local message = ("%s '%s': Luck %d %s %d%s")
                :format(icon, bestEgg.Name,
                        bestLuck, comp, requiredLuck, timeInfo)
if ok then
    print(message)
    sendWebhookEmbed(
        bestEgg.Name,
        bestLuck,
        bestTime,
        bestEgg.Output and bestEgg.Output.Position.Y or 0,
        game.JobId,
        game.PlaceId
    )
    shared.foundEgg = true
else
    warn(message)
end

shared.eggCheckFinished = true
