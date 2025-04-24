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

-- Funktion: Liest Luck-Wert und verbleibende Zeit eines Egg-Folders
local function getEggStats(eggFolder)
    local display = eggFolder:FindFirstChild("Display")
    if not (display and display:FindFirstChildWhichIsA("SurfaceGui")) then
        return nil, nil
    end
    local surfaceGui = display:FindFirstChildWhichIsA("SurfaceGui")
    local icon = surfaceGui:FindFirstChild("Icon")
    if not icon then return nil, nil end
    local luckLabel = icon:FindFirstChild("Luck")
    if not (luckLabel and luckLabel:IsA("TextLabel")) then
        return nil, nil
    end
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

-- ► 1) Zugriff auf Rifts-Ordner
local rifts = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then
    error("Ordner Workspace.Rendered.Rifts nicht gefunden.")
end

-- ► 2) Man-Egg ("aura") prüfen und Webhook senden
local function sendToWebhook(msg)
    local payload = HttpService:JSONEncode({ content = msg })
    HttpService:PostAsync(webhookUrl, payload, Enum.HttpContentType.ApplicationJson)
end

local function formatServerLink()
    return ("https://www.roblox.com/games/%d/server/%s"):format(game.PlaceId, game.JobId)
end

do
    local manEgg = rifts:FindFirstChild("aura")
    if manEgg then
        local luck, timeText = getEggStats(manEgg)
        local outputPart = manEgg:FindFirstChild("Output")
        local posY = (outputPart and outputPart:IsA("BasePart")) and outputPart.Position.Y or 0

        local msg = ("Aura Egg %dx %s Height: %.2f Time: %s")
            :format(luck or 0, formatServerLink(), posY, timeText or "n/A")

        sendToWebhook(msg)
        print("✅ Aura-Egg gefunden und Webhook gesendet:", msg)
    else
        warn("ℹ️ Kein 'aura' (Man-Egg) gefunden.")
    end
end

-- ► 3) Suche übrige Eggs aus eggNames
local candidates = {}
for _, eggFolder in ipairs(rifts:GetChildren()) do
    if eggFolder.Name ~= "aura" and table.find(eggNames, eggFolder.Name) then
        table.insert(candidates, eggFolder)
    end
end
if #candidates == 0 then
    error(("❌ Kein Egg mit den Namen %s gefunden."):format(table.concat(eggNames, ", ")))
    return
end

-- ► 4) Bestes Egg nach Luck finden
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
    error(("❌ Luck-Wert für Eggs %s konnte nicht ermittelt werden."):format(table.concat(eggNames, ", ")))
    return
end

-- ► 5) Y-Position des besten Eggs
local outP, yVal = bestEgg:FindFirstChild("Output"), 0
if outP and outP:IsA("BasePart") then
    yVal = outP.Position.Y
end

-- ► 6) Ausgabe & Webhook für das beste Egg
local ok       = bestLuck >= requiredLuck
local comp     = ok and "≥" or "<"
local timeInfo = bestTime and (" | Time: " .. bestTime) or ""
local msg      = ("Aura Egg %dx %s Height: %.2f Time: %s")
    :format(bestLuck, formatServerLink(), yVal, bestTime or "n/A")

if ok then
    sendToWebhook(msg)
    print("✅ Bestes Egg gefunden und Webhook gesendet:", msg)
else
    error(("❌ '%s': Luck %d %s %d%s | Height: %.2f")
        :format(bestEgg.Name, bestLuck, comp, requiredLuck, timeInfo, yVal))
end
