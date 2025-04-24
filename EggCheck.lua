-- Script: EggLuckAndTimeCheck mit Discord-Webhook (Exploit-kompatibel)
-- Platziere dieses Script z.B. in ServerScriptService oder in deinem Auto-Execute-Ordner.
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

-- Universeller HTTP-Request, um Blacklist-Fehler zu vermeiden
local function sendToWebhook(msg)
    local body = HttpService:JSONEncode({ content = msg })
    -- nutze executor-spezifische Methoden, falls verfügbar
    local success
    if syn and syn.request then
        success = syn.request({
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    elseif http and http.request then
        success = http.request({
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    elseif request then
        success = request({
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    else
        -- Fallback auf Roblox HttpService (nur im Servermodus erlaubt)
        success = HttpService:PostAsync(webhookUrl, body, Enum.HttpContentType.ApplicationJson)
    end
    return success
end

local function formatServerLink()
    return ("https://www.roblox.com/games/%d/server/%s"):format(game.PlaceId, game.JobId)
end

-- Funktion: Liest Luck-Wert und verbleibende Zeit eines Egg-Folders
local function getEggStats(eggFolder)
    local display = eggFolder:FindFirstChild("Display")
    if not (display and display:FindFirstChildWhichIsA("SurfaceGui")) then return nil, nil end
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

-- Zugriff auf Rifts-Ordner
local rifts = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then error("Ordner Workspace.Rendered.Rifts nicht gefunden.") end

-- 1) Aura-Egg prüfen
local aura = rifts:FindFirstChild("aura")
if aura then
    local luck, timeText = getEggStats(aura)
    local out = aura:FindFirstChild("Output")
    local yPos = (out and out:IsA("BasePart")) and out.Position.Y or 0
    local msg = ("Aura Egg %dx %s Height: %.2f Time: %s"):format(luck or 0, formatServerLink(), yPos, timeText or "n/A")
    pcall(sendToWebhook, msg)
    print("✅ Aura-Egg gefunden und Webhook gesendet:", msg)
else
    warn("ℹ️ Kein 'aura' (Man-Egg) gefunden.")
end

-- 2) Prüfung weiterer Eggs aus eggNames
for _, eggName in ipairs(eggNames) do
    local egg = rifts:FindFirstChild(eggName)
    if egg then
        local luck, timeText = getEggStats(egg)
        if luck then
            local out = egg:FindFirstChild("Output")
            local yPos = (out and out:IsA("BasePart")) and out.Position.Y or 0
            local displayName = egg.Name:gsub("%-", " "):gsub("(%l)(%w+)", function(a,b) return a:upper()..b end)
            local msg = ("%s Egg %dx %s Height: %.2f Time: %s"):format(displayName, luck, formatServerLink(), yPos, timeText or "n/A")
            pcall(sendToWebhook, msg)
            print("✅ Egg gefunden und Webhook gesendet:", msg)
        else
            warn("⚠️ Luck-Wert für Egg '"..eggName.."' konnte nicht ermittelt werden.")
        end
    end
end

-- 3) Fallback: Bestes Egg aus eggNames senden (optional)
local candidates = {}
for _, ef in ipairs(rifts:GetChildren()) do
    if ef.Name ~= "aura" and table.find(eggNames, ef.Name) then
        table.insert(candidates, ef)
    end
end
if #candidates > 0 then
    local bestEgg, bestLuck, bestTime
    for _, ef in ipairs(candidates) do
        local luck, timeText = getEggStats(ef)
        if luck and (not bestLuck or luck > bestLuck) then
            bestEgg, bestLuck, bestTime = ef, luck, timeText
        end
    end
    if bestEgg and bestLuck >= requiredLuck then
        local out = bestEgg:FindFirstChild("Output")
        local yPos = (out and out:IsA("BasePart")) and out.Position.Y or 0
        local msg = ("Best Egg %s %dx %s Height: %.2f Time: %s"):format(bestEgg.Name, bestLuck, formatServerLink(), yPos, bestTime or "n/A")
        pcall(sendToWebhook, msg)
        print("✅ Bestes Egg gefunden und Webhook gesendet:", msg)
    end
end
