-- Script: EggLuckAndTimeCheck mit Discord-Webhook (Exploit-kompatibel)
-- Platziere dieses Script in deinem Auto-Execute-Ordner.
-- ► Definiere die Webhook-URL im Loader via _G.webhookUrl

local requiredLuck = 25
local eggNames = {"void-egg","rainbow-egg","easter3-egg"}

-- Hole Webhook-URL aus Loader
local webhookUrl = _G.webhookUrl or error("Keine Webhook-URL in _G.webhookUrl definiert!")

-- Universal HTTP-Handler für Exploits
local function handleHttpRequest(url, method, body)
    method = method or "GET"
    local executor = identifyexecutor and identifyexecutor():lower() or "unknown"
    -- AWP
    if executor:find("awp") then
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok then return res end
    end
    -- Exploit-spezifisch
    local methods = {
        synapse = function()
            return syn.request({Url = url, Method = method, Headers = {["Content-Type"]="application/json"}, Body = body})
        end,
        krnl    = function()
            return http.request({Url = url, Method = method, Headers = {["Content-Type"]="application/json"}, Body = body})
        end,
        fluxus  = function()
            return fluxus.request({Url = url, Method = method, Headers = {["Content-Type"]="application/json"}, Body = body})
        end,
        electron= function()
            return request({Url = url, Method = method, Headers = {["Content-Type"]="application/json"}, Body = body})
        end,
    }
    local fn = methods[executor]
    if fn then
        local ok, res = pcall(fn)
        if ok then
            return (res.Body or res)
        end
    end
    error("HTTP nicht unterstützt für executor: "..executor)
end

-- Erzeuge Discord-Webhook Request
local function sendToWebhook(msg)
    local payload = ({ content = msg })
    local body = game:GetService("HttpService"):JSONEncode(payload)
    handleHttpRequest(webhookUrl, "POST", body)
end

-- Hilfsfunktion zum Link
local function formatServerLink()
    return ("https://www.roblox.com/games/%d/server/%s"):format(game.PlaceId, game.JobId)
end

-- Liest Luck und Timer aus einem Egg
local function getEggStats(folder)
    local disp = folder:FindFirstChild("Display")
    if not disp then return nil,nil end
    local gui = disp:FindFirstChildWhichIsA("SurfaceGui")
    if not gui then return nil,nil end
    local icon = gui:FindFirstChild("Icon")
    local luckLbl = icon and icon:FindFirstChild("Luck")
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

-- Warte auf Rifts
local rifts = workspace:WaitForChild("Rendered"):WaitForChild("Rifts")

-- Verarbeite ein einzelnes Egg
local function processEgg(folder, displayName)
    local luck, timeTxt = getEggStats(folder)
    if not luck then return end
    local out = folder:FindFirstChild("Output")
    local y = out and out.Position.Y or 0
    local msg = ("%s Egg %dx %s Height: %.2f Time: %s"):format(
        displayName, luck, formatServerLink(), y, timeTxt
    )
    pcall(sendToWebhook, msg)
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
