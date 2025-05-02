--// Verbesserte EggCheck.lua

local HttpService = game:GetService("HttpService")

-- Sicherstellen, dass shared-Variablen existieren
local requiredLuck = shared.requiredLuck
local eggNames = shared.eggNames

local webhookUrl = shared.webhookUrl

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

-- Webhook Funktion
-- Anpassen der sendWebhookEmbed-Funktion
local function sendWebhookEmbed(eggName, luck, time, height, jobId, placeId)
    local isManEgg   = eggName:lower() == "silly-egg"
    local embedColor = isManEgg and 0x9B59B6 or 0x2ECC71
    local mention    = isManEgg and "<@palkins7>" or ""

    -- Statt games/start nun home?placeID&gameID
    local serverLink = ("https://www.roblox.com/home?placeID=%d&gameID=%s")
                        :format(placeId, jobId)

    local payload = {
        content = mention,
        embeds = {{
            title = "🥚 Ei gefunden!",
            url   = serverLink,      -- klickbarer Titel
            color = embedColor,
            fields = {
                { name = "🐣 Egg",         value = eggName,       inline = true },
                { name = "💥 Luck",        value = tostring(luck), inline = true },
                { name = "⏳ Zeit",        value = time or "N/A", inline = true },
                { name = "📏 Höhe",        value = string.format("%.2f", height or 0), inline = true },
                { name = "🔗 Server Link", value = serverLink,    inline = false },
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
            syn.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = jsonData })
        elseif string.find(executor, "krnl") then
            http.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = jsonData })
        elseif string.find(executor, "fluxus") then
            fluxus.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = jsonData })
        elseif string.find(executor, "awp") then
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
    local gui = eggFolder:FindFirstChild("Display") and eggFolder.Display:FindFirstChildWhichIsA("SurfaceGui")
    if not gui then return nil, nil end

    local luckText = gui:FindFirstChild("Icon") and gui.Icon:FindFirstChild("Luck")
    local timer = gui:FindFirstChild("Timer") or gui:FindFirstChildWhichIsA("TextLabel")
    
    local luckValue = luckText and tonumber(luckText.Text:match("%d+")) or nil
    local timeText = timer and timer.Text or nil
    return luckValue, timeText
end

-- Suche nach Eggs
local rifts = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then
    warn("❌ Ordner Workspace.Rendered.Rifts nicht gefunden.")
    shared.eggCheckFinished = true
    return
end

local manEgg = rifts:FindFirstChild("silly-egg")
if manEgg then
    local luck, timeText = getEggStats(manEgg)
    local yInfo = ""
    local outputPart = manEgg:FindFirstChild("Output")
    if outputPart and outputPart:IsA("BasePart") then
        yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
    end
    local timeInfo = timeText and (" | Zeit übrig: " .. timeText) or ""
    print(("✅ 'silly-egg': Luck %s%s%s"):format(luck or "n/A", timeInfo, yInfo))
else
    print("ℹ️ Kein 'silly-egg' gefunden.")
end

-- Suche nach passenden Eiern
local candidates = {}
for _, eggFolder in ipairs(rifts:GetChildren()) do
    if eggFolder.Name ~= "silly-egg" and table.find(eggNames, eggFolder.Name) then
        table.insert(candidates, eggFolder)
    end
end

if #candidates == 0 then
    warn(("❌ Kein Egg mit den Namen %s gefunden."):format(table.concat(eggNames, ", ")))
    shared.eggCheckFinished = true
    return
end

-- Bester Egg mit höchstem Luck
local bestEgg, bestLuck, bestTime
for _, ef in ipairs(candidates) do
    local luck, timeText = getEggStats(ef)
    if luck and (not bestLuck or luck > bestLuck) then
        bestEgg = ef
        bestLuck = luck
        bestTime = timeText
    end
end

if not bestEgg then
    warn(("❌ Luck-Wert für Eggs %s konnte nicht ermittelt werden."):format(table.concat(eggNames, ", ")))
    shared.eggCheckFinished = true
    return
end

-- Ausgabe + Webhook
local yInfo = ""
local outputPart = bestEgg:FindFirstChild("Output")
if outputPart and outputPart:IsA("BasePart") then
    yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
end

local function parseTimeString(text)
    if not text then return nil end

    -- Format MM:SS z.B. "04:55"
    local minutes, seconds = text:match("^(%d+):(%d+)$")
    if minutes and seconds then
        return tonumber(minutes) * 60 + tonumber(seconds)
    end

    -- Nur Zahl (z.B. "300")
    local n = tonumber(text)
    if n then return n end

    -- "9 minutes", "3 mins"
    local minOnly = text:match("(%d+)%s*min")
    if minOnly then
        return tonumber(minOnly) * 60
    end

    -- "120 seconds", "120 sec"
    local secOnly = text:match("(%d+)%s*sec")
    if secOnly then
        return tonumber(secOnly)
    end

    return nil
end


local function showFoundGui(message)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggFoundGui"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, 0, 0.15, 0)
    label.Position = UDim2.new(0.2, 0, 0.4, 0)
    label.BackgroundColor3 = Color3.fromRGB(50, 205, 50)
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.Text = message
    label.Parent = screenGui

    game.Debris:AddItem(screenGui, 5)
end

showFoundGui(("🥚 Ei gefunden: %s | Luck: %d"):format(bestEgg.Name, bestLuck))

-- Sound abspielen beim Fund
local function playFoundSound()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://9118823104" -- Beispiel: Zelda-Truhe Sound
    sound.Volume = 1
    sound.Name = "EggFoundSound"
    sound.Parent = workspace
    sound:Play()
    
    game.Debris:AddItem(sound, 5) -- automatisch entfernen
end

playFoundSound()


local numericTime = parseTimeString(bestTime)
local ok = bestLuck >= requiredLuck and numericTime and numericTime >= shared.minTime
local icon = ok and "✅" or "❌"
local comp = ok and "≥" or "<"
local timeInfo = bestTime and (" | Zeit übrig: " .. bestTime) or ""
local message = ("%s '%s': Luck %d %s %d%s%s")
    :format(icon, bestEgg.Name, bestLuck, comp, requiredLuck, timeInfo, yInfo)

if ok then
    print(message)
    print("📡 Sende Webhook...")

    sendWebhookEmbed(
        bestEgg.Name,
        bestLuck,
        bestTime,
        outputPart and outputPart.Position.Y or 0,
        game.JobId,
        game.PlaceId
    )

    -- 🎧 Sound + 🖼 GUI
    playFoundSound()
    showFoundGui(("🥚 Ei gefunden: %s | Luck: %d"):format(bestEgg.Name, bestLuck))

    shared.lastEggName = bestEgg.Name
    shared.lastEggLuck = bestLuck
    shared.statusText = "✅ Ei gefunden!"
    shared.stats.attempts += 1
    shared.stats.foundCount += 1
    table.insert(shared.stats.log, os.date("[%H:%M:%S]") .. " ✔️ FOUND: " .. bestEgg.Name .. " | Luck: " .. bestLuck)



    shared.foundEgg = true
    shared.eggCheckFinished = true
    print("✅ Egg gefunden und gemeldet!")
else
    shared.lastEggName = bestEgg.Name
    shared.lastEggLuck = bestLuck
    shared.statusText = "❌ Nicht gut genug. Hüpfe weiter..."
    shared.stats.attempts += 1
    table.insert(shared.stats.log, os.date("[%H:%M:%S]") .. " ❌ SKIPPED: " .. bestEgg.Name .. " | Luck: " .. bestLuck)


    warn(message)
    shared.eggCheckFinished = true
end