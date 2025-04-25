--// EggCheck.lua (vollständig)

-- Konfiguration aus shared holen
local requiredLuck = shared.requiredLuck or error("❌ Kein Luck in shared.requiredLuck definiert!")
local eggNames = shared.eggNames or error("❌ Keine EggNames in shared.eggNames definiert!")
local webhookUrl = shared.webhookUrl or error("❌ Keine Webhook-URL in shared.webhookUrl definiert!")

-- Hilfsfunktion: Sende Discord-Webhook
local function sendWebhookEmbed(eggName, luck, time, height, jobId, placeId)
    local HttpService = game:GetService("HttpService")

    local isAuraEgg = eggName:lower() == "aura"
    local embedColor = isAuraEgg and 0x9B59B6 or 0x2ECC71
    local mention = isAuraEgg and "<@palkins7>" or ""

    local payload = {
        content = mention,
        embeds = {{
            title = "🥚 Ei gefunden!",
            color = embedColor,
            fields = {
                { name = "🐣 Egg", value = eggName, inline = true },
                { name = "💥 Luck", value = tostring(luck), inline = true },
                { name = "⏳ Zeit", value = time or "N/A", inline = true },
                { name = "📏 Höhe", value = string.format("%.2f", height or 0), inline = true },
            },
            footer = {
                text = string.format("🧭 Server: %s | Spiel: %d", jobId, placeId)
            }
        }}
    }

    local jsonData = HttpService:JSONEncode(payload)
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"

    local success, err = pcall(function()
        if string.find(executor, "synapse") then
            syn.request({Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData})
        elseif string.find(executor, "krnl") then
            http.request({Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData})
        elseif string.find(executor, "fluxus") then
            fluxus.request({Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData})
        elseif string.find(executor, "awp") then
            request({Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData})
        else
            HttpService:PostAsync(webhookUrl, jsonData)
        end
    end)

    if not success then
        warn("❌ Webhook fehlgeschlagen:", err)
    end
end

-- Hilfsfunktion: Zeit (MM:SS) in Sekunden umwandeln
local function parseTimeToSeconds(timeText)
    if not timeText then return 0 end
    local minutes, seconds = timeText:match("(%d+):(%d+)")
    minutes, seconds = tonumber(minutes), tonumber(seconds)
    if minutes and seconds then
        return (minutes * 60) + seconds
    end
    return 0
end

-- Hilfsfunktion: Egg-Daten extrahieren
local function getEggStats(eggFolder)
    local gui = eggFolder:FindFirstChild("Display") and eggFolder.Display:FindFirstChildWhichIsA("SurfaceGui")
    if not gui then return nil, nil end

    local luckText = gui:FindFirstChild("Icon") and gui.Icon:FindFirstChild("Luck")
    local timer = gui:FindFirstChild("Timer") or gui:FindFirstChildWhichIsA("TextLabel")

    local luckValue = luckText and tonumber(luckText.Text:match("%d+")) or nil
    local timeText = timer and timer.Text or nil
    return luckValue, timeText
end

-- Hauptlogik beginnt
local rifts = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then
    warn("❌ Ordner Workspace.Rendered.Rifts nicht gefunden.")
    shared.eggCheckFinished = true
    return
end

-- Aura-Egg prüfen
local auraEgg = rifts:FindFirstChild("aura")
local bestEgg, bestLuck, bestTime

if auraEgg then
    bestLuck, bestTime = getEggStats(auraEgg)
    bestEgg = auraEgg
    print(("✅ Aura Egg gefunden: Luck %s | Zeit %s"):format(bestLuck or "n/A", bestTime or "n/A"))
else
    print("ℹ️ Kein Aura Egg gefunden, prüfe andere Eggs...")
    
    -- Andere Eggs sammeln
    local candidates = {}
    for _, eggFolder in ipairs(rifts:GetChildren()) do
        if eggFolder.Name ~= "aura" and table.find(eggNames, eggFolder.Name) then
            local luck, timeText = getEggStats(eggFolder)
            local timeLeft = parseTimeToSeconds(timeText)
            if timeLeft >= 300 then  -- Mindestens 5 Minuten Zeit übrig
                table.insert(candidates, {eggFolder = eggFolder, luck = luck, timeText = timeText})
            else
                print(("⚠️ Ignoriere '%s' wegen zu wenig Zeit (%s)").format(eggFolder.Name, timeText or "N/A"))
            end
        end
    end

    if #candidates == 0 then
        warn(("❌ Kein passendes Egg gefunden (%s) mit >=5 Minuten Zeit."):format(table.concat(eggNames, ", ")))
        shared.eggCheckFinished = true
        return
    end

    -- Bestes Egg (höchstes Luck) auswählen
    for _, data in ipairs(candidates) do
        if data.luck and (not bestLuck or data.luck > bestLuck) then
            bestEgg = data.eggFolder
            bestLuck = data.luck
            bestTime = data.timeText
        end
    end
end

-- Wenn kein Egg ausgewählt werden konnte
if not bestEgg then
    warn("❌ Kein gültiges Egg gefunden.")
    shared.eggCheckFinished = true
    return
end

-- Finaler Check: Luck vergleichen
local eggName = bestEgg.Name
local yInfo = ""
local outputPart = bestEgg:FindFirstChild("Output")
if outputPart and outputPart:IsA("BasePart") then
    yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
end

local ok = bestLuck and bestLuck >= requiredLuck
local icon = ok and "✅" or "❌"
local comp = ok and "≥" or "<"
local timeInfo = bestTime and (" | Zeit übrig: " .. bestTime) or ""
local message = ("%s '%s': Luck %d %s %d%s%s")
    :format(icon, eggName, bestLuck or 0, comp, requiredLuck, timeInfo, yInfo)

print(message)

if ok then
    print("📡 Sende Webhook...")

    sendWebhookEmbed(
        eggName,
        bestLuck,
        bestTime,
        outputPart and outputPart.Position.Y or 0,
        game.JobId,
        game.PlaceId
    )

    print("✅ Webhook gesendet.")

    -- Erfolg setzen
    shared.foundEgg = true
else
    print("❌ Luck reicht nicht, kein Webhook gesendet.")
end

-- EggCheck abgeschlossen, immer setzen!
shared.eggCheckFinished = true
