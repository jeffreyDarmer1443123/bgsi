-- Script: EggLuckAndTimeCheck mit Discord-Webhook (Server-Skript)
-- Platziere dieses Script in ServerScriptService in deinem Roblox-Game.
-- ► Stelle sicher, dass unter Game Settings -> Security -> "Enable Studio Access to API Services" aktiviert ist.

local requiredLuck = 25
local eggNames = {"void-egg","rainbow-egg","easter3-egg"}

local HttpService = game:GetService("HttpService")
local webhookUrl = _G.webhookUrl or error("Keine Webhook-URL in _G.webhookUrl definiert!")

-- Hilfsfunktion: Webhook senden via HttpService (nur in Server-Skripten erlaubt)
local function sendToWebhook(msg)
    local data = { content = msg }
    local body = HttpService:JSONEncode(data)
    -- HttpService:PostAsync funktioniert nur in ServerScriptService
    HttpService:PostAsync(webhookUrl, body, Enum.HttpContentType.ApplicationJson)
end

local function formatServerLink()
    return ("https://www.roblox.com/games/%d/server/%s"):format(game.PlaceId, game.JobId)
end

local function getEggStats(folder)
    local disp = folder:FindFirstChild("Display")
    if not disp then return nil,nil end
    local gui = disp:FindFirstChildWhichIsA("SurfaceGui")
    if not gui then return nil,nil end
    local luckLbl = gui:FindFirstChild("Icon") and gui.Icon:FindFirstChild("Luck")
    local luck = luckLbl and tonumber(luckLbl.Text:match("%d+")) or nil
    local timerLbl = gui:FindFirstChild("Timer")
    if not timerLbl then
        for _,c in ipairs(gui:GetDescendants()) do
            if c:IsA("TextLabel") and c.Name:lower()=="timer" then timerLbl=c break end
        end
    end
    local timeTxt = timerLbl and timerLbl.Text or "n/A"
    return luck, timeTxt
end

-- Haupt: Rifts-Ordner
local rifts = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")

-- Funktion: prüft und sendet für ein einzelnes Egg
local function processEgg(folder, displayName)
    local luck, timeTxt = getEggStats(folder)
    if not luck then return end
    local out = folder:FindFirstChild("Output")
    local y = out and out.Position.Y or 0
    local msg = ("%s Egg %dx %s Height: %.2f Time: %s"):format(
        displayName, luck, formatServerLink(), y, timeTxt
    )
    sendToWebhook(msg)
    print("✅ Webhook gesendet:", msg)
end

-- 1) Aura-Egg
local aura = rifts:FindFirstChild("aura")
if aura then
    processEgg(aura, "Aura")
else
    warn("ℹ️ Kein Aura-Egg gefunden.")
end

-- 2) Weitere Eggs
for _,name in ipairs(eggNames) do
    local folder = rifts:FindFirstChild(name)
    if folder then
        local displayName = name:gsub("%-"," "):gsub("^%l",string.upper)
        processEgg(folder, displayName)
    end
end
