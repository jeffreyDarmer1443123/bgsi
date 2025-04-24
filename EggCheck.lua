-- Script: EggLuckAndTimeCheck mit Executor-kompatibler Webhook-Funktion
-- Läuft komplett im Client/Executor (Synapse, KRNL, Fluxus, AWP u.a.).

-- ► Konfiguration
local requiredLuck = 25
local eggNames = { "void-egg", "rainbow-egg", "easter3-egg" }
local webhookUrl = _G.webhookUrl  -- aus Deinem Executed Script

-- Services
local HttpService = game:GetService("HttpService")

-- Executor-spezifische HTTP-POST-Funktion
-- ► Füge diese Funktion am Anfang des Scripts ein
local function sendWebhook(message)
    if not webhookUrl or webhookUrl == "" then
        warn("Webhook URL nicht gesetzt.")
        return false
    end
    
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"
    local payload = {
        content = message
    }
    
    print("Versende Webhook mit Executor:", executor)
    
    -- Universal HTTP POST für verschiedene Executoren
    local success, result = pcall(function()
        if string.find(executor, "synapse") then
            return syn.request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = game:GetService("HttpService"):JSONEncode(payload)
            })
        elseif string.find(executor, "krnl") then
            return http.request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = game:GetService("HttpService"):JSONEncode(payload)
            })
        elseif string.find(executor, "fluxus") then
            return fluxus.request({
                Url = webhookUrl,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = game:GetService("HttpService"):JSONEncode(payload)
            })
        else
            -- Fallback für andere Executoren
            return game:GetService("HttpService"):PostAsync(
                webhookUrl, 
                game:GetService("HttpService"):JSONEncode(payload)
            )
        end
    end)
    
    if success then
        print("Webhook erfolgreich gesendet!")
        return true
    else
        warn("Webhook-Fehler:", result)
        return false
    end
end

-- ► In der Ausgabe-Sektion (ersetzte den Webhook-Teil):
if ok then
    local serverLink = string.format(
        "https://www.roblox.com/games/%d/?privateServerId=%s",
        game.PlaceId,
        game.JobId
    )
    local height = outputPart and string.format("%.2f", outputPart.Position.Y) or "N/A"
    local webhookMsg = string.format(
        "%s %d %s Height:%s Time:%s",
        bestEgg.Name,
        bestLuck,
        serverLink,
        height,
        bestTime or "N/A"
    )
    
    -- Webhook mit Wiederholungslogik
    local maxRetries = 3
    for attempt = 1, maxRetries do
        if sendWebhook(webhookMsg) then
            break
        else
            task.wait(2)
        end
    end
end

-- Funktion zum Lesen von Luck und Timer
local function getEggStats(eggFolder)
    local display = eggFolder:FindFirstChild("Display")
    if not display then return nil, nil end

    local surfaceGui = display:FindFirstChildWhichIsA("SurfaceGui")
    if not surfaceGui then return nil, nil end

    local luckLabel = surfaceGui:FindFirstChild("Icon")
        and surfaceGui.Icon:FindFirstChild("Luck")
    if not (luckLabel and luckLabel:IsA("TextLabel")) then return nil, nil end

    local luckValue = tonumber(luckLabel.Text:match("%d+"))
    local timerLabel = surfaceGui:FindFirstChild("Timer")
    if not timerLabel then
        for _, d in ipairs(surfaceGui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Name:lower() == "timer" then
                timerLabel = d; break
            end
        end
    end
    local timeText = (timerLabel and timerLabel:IsA("TextLabel")) and timerLabel.Text or "n/A"
    return luckValue, timeText
end

-- Hauptlogik
local rifts = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")

-- Man-Egg ausgeben (falls benötigt)
local manEgg = rifts:FindFirstChild("man-egg")
if manEgg then
    local luck, timeText = getEggStats(manEgg)
    print(("✅ 'man-egg': Luck %s | Time: %s"):format(luck or "n/A", timeText))
end

-- Suche alle gewünschten Eggs
local candidates = {}
for _, folder in ipairs(rifts:GetChildren()) do
    if folder.Name ~= "man-egg" and table.find(eggNames, folder.Name) then
        table.insert(candidates, folder)
    end
end
assert(#candidates > 0, "❌ Kein Egg mit den gewünschten Namen gefunden.")

-- Bestes Egg nach Luck
local bestEgg, bestLuck, bestTime, bestHeight
for _, ef in ipairs(candidates) do
    local luck, timeText = getEggStats(ef)
    if luck and (not bestLuck or luck > bestLuck) then
        bestEgg, bestLuck, bestTime = ef, luck, timeText
        local out = ef:FindFirstChild("Output")
        bestHeight = (out and out:IsA("BasePart")) and out.Position.Y or 0
    end
end
assert(bestEgg, "❌ Luck-Wert konnte nicht gelesen werden.")

-- Nachricht zusammenbauen
local meets = bestLuck >= requiredLuck
local status = meets and "✅" or "❌"
local serverLink = ("https://www.roblox.com/games/%d/?privateServerId=%s"):format(game.PlaceId, game.JobId)
local msg = string.format(
    "%s %s %d Server:%s Height:%.2f Time:%s",
    bestEgg.Name, bestLuck, serverLink, bestHeight, bestTime
)

-- nur bei erreichter Luck schicken
if meets then
    sendWebhook(webhookUrl, { content = msg })
end
