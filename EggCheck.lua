-- Script: EggLuckAndTimeCheck mit Discord-Webhook
-- Platziere dieses Script z.B. in ServerScriptService.
-- ► Du brauchst hier NICHT mehr die Webhook-URL anpassen

local requiredLuck = 25

-- Liste mit allen gewünschten Egg-Namen (ohne man-egg)
local eggNames = {
    "void-egg",
    "rainbow-egg",
    "easter3-egg",
    -- weitere Namen hier ergänzen ...
}

-- Services
local HttpService = game:GetService("HttpService")

-- Hole die Webhook-URL aus dem Loader
local webhookUrl = _G.webhookUrl or error("Keine Webhook-URL in _G.webhookUrl definiert!")

-- Hilfsfunktionen
local function sendToWebhook(msg)
    local payload = HttpService:JSONEncode({ content = msg })
    HttpService:PostAsync(webhookUrl, payload, Enum.HttpContentType.ApplicationJson)
end

local function formatServerLink()
    return ("https://www.roblox.com/games/%d/server/%s"):format(game.PlaceId, game.JobId)
end

local function getEggStats(eggFolder)
    local display = eggFolder:FindFirstChild("Display")
    if not (display and display:FindFirstChildWhichIsA("SurfaceGui")) then
        return nil, nil
    end
    local surfaceGui = display:FindFirstChildWhichIsA("SurfaceGui")
    local icon = surfaceGui:FindFirstChild("Icon")
    if not icon then return nil, nil end
    local luckLabel = icon:FindFirstChild("Luck")
    if not (luckLabel and luckLabel:IsA("TextLabel")) then return nil, nil end
    local digits = luckLabel.Text:match("%d+")
    local luckValue = digits and tonumber(digits) or nil

    local timerLabel = surfaceGui:FindFirstChild("Timer")
    if not timerLabel then
        for _, obj in ipairs(surfaceGui:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Name:lower() == "timer" then
                timerLabel = obj
                break
            end
        end
    end
    local timeText = (timerLabel and timerLabel:IsA("TextLabel")) and timerLabel.Text or nil

    return luckValue, timeText
end

-- Hauptlogik
-- 1) Zugriff auf Rifts-Ordner
local rifts = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then error("Ordner Workspace.Rendered.Rifts nicht gefunden.") end

-- 2) Aura-Egg prüfen
local aura = rifts:FindFirstChild("aura")
if aura then
    local luck, timeText = getEggStats(aura)
    local outputPart = aura:FindFirstChild("Output")
    local yPos = (outputPart and outputPart:IsA("BasePart")) and outputPart.Position.Y or 0
    local msg = ("Aura Egg %dx %s Height: %.2f Time: %s"):format(luck or 0, formatServerLink(), yPos, timeText or "n/A")
    sendToWebhook(msg)
    print("✅ Aura-Egg gefunden und Webhook gesendet:", msg)
else
    warn("ℹ️ Kein 'aura' (Man-Egg) gefunden.")
end

-- 3) Prüfung weiterer Eggs aus eggNames
for _, eggName in ipairs(eggNames) do
    local egg = rifts:FindFirstChild(eggName)
    if egg then
        local luck, timeText = getEggStats(egg)
        if luck then
            local outputPart = egg:FindFirstChild("Output")
            local yPos = (outputPart and outputPart:IsA("BasePart")) and outputPart.Position.Y or 0
            local nameFormatted = egg.Name:gsub("%-", " "):gsub("(%l)(%w+)", function(a,b) return a:upper()..b end)
            local msg = ("%s Egg %dx %s Height: %.2f Time: %s"):format(
                nameFormatted, luck, formatServerLink(), yPos, timeText or "n/A"
            )
            sendToWebhook(msg)
            print("✅ Found and sent webhook for egg:", msg)
        else
            warn("⚠️ Luck-Wert für Egg '"..eggName.."' konnte nicht ermittelt werden.")
        end
    end
end

-- 4) Fallback auf bestEgg, falls du weiterhin die alte Logik nutzen möchtest
-- (Optional, kann entfernt werden wenn nicht mehr benötigt)
local candidates = {}
for _, ef in ipairs(rifts:GetChildren()) do
    if ef.Name ~= "aura" and table.find(eggNames, ef.Name) then table.insert(candidates, ef) end
end
if #candidates == 0 then error("❌ Keine Eggs aus eggNames gefunden.") end
local bestEgg, bestLuck, bestTime
for _, ef in ipairs(candidates) do
    local luck, timeText = getEggStats(ef)
    if luck and (not bestLuck or luck > bestLuck) then
        bestEgg, bestLuck, bestTime = ef, luck, timeText
    end
end
if bestEgg and bestLuck >= requiredLuck then
    local outputPart = bestEgg:FindFirstChild("Output")
    local yPos = (outputPart and outputPart:IsA("BasePart")) and outputPart.Position.Y or 0
    local msg = ("Best Egg %s %dx %s Height: %.2f Time: %s"):format(
        bestEgg.Name, bestLuck, formatServerLink(), yPos, bestTime or "n/A"
    )
    sendToWebhook(msg)
    print("✅ Bestes Egg gefunden und Webhook gesendet:", msg)
end
