-- Script: EggLuckAndTimeCheck mit Discord-Webhook (Exploit-kompatibel)
-- Platziere dieses Script z.B. in deinem Auto-Execute-Ordner.
-- ► Webhook-URL im Loader (_G.webhookUrl) definieren

local requiredLuck = 25

-- Gewünschte Egg-Namen (ohne 'aura')
local eggNames = {"void-egg","rainbow-egg","easter3-egg"}

-- Services
local HttpService = game:GetService("HttpService")

-- Webhook-URL vom Loader
local webhookUrl = _G.webhookUrl or error("Keine Webhook-URL in _G.webhookUrl definiert!")

-- Universeller HTTP-Request, unterstützt syn, http_request, request
local function sendToWebhook(msg)
    local body = HttpService:JSONEncode({ content = msg })
    -- exploit-spezifisch
    if syn and syn.request then
        syn.request({Url=webhookUrl,Method="POST",Headers={["Content-Type"]="application/json"},Body=body})
    elseif http_request then
        http_request({Url=webhookUrl,Method="POST",Headers={["Content-Type"]="application/json"},Body=body})
    elseif http and http.request then
        http.request({Url=webhookUrl,Method="POST",Headers={["Content-Type"]="application/json"},Body=body})
    elseif request then
        request({Url=webhookUrl,Method="POST",Headers={["Content-Type"]="application/json"},Body=body})
    else
        -- falls Server-Script mit HttpService
        HttpService:PostAsync(webhookUrl, body, Enum.HttpContentType.ApplicationJson)
    end
end

-- Hilfsfunktion: Server-Link erstellen
local function formatServerLink()
    return ("https://www.roblox.com/games/%d/server/%s"):format(game.PlaceId, game.JobId)
end

-- Stats eines Eggs ermitteln
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
        for _,c in ipairs(gui:GetDescendants()) do if c:IsA("TextLabel") and c.Name:lower()=="timer" then timerLbl=c break end end
    end
    local timeTxt = timerLbl and timerLbl.Text or nil
    return luck, timeTxt
end

-- Haupt: Rifts-Ordner
local rifts = workspace.Rendered and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then error("Rifts-Ordner nicht gefunden") end

-- 1) Prüfe Aura-Egg
local aura = rifts:FindFirstChild("aura")
if aura then
    local luck,timeTxt = getEggStats(aura)
    local out = aura:FindFirstChild("Output")
    local y = out and out.Position.Y or 0
    local msg = ("Aura Egg %dx %s Height: %.2f Time: %s"):format(luck or 0,formatServerLink(),y,timeTxt or "n/A")
    pcall(sendToWebhook,msg)
    print("✅ Aura gefunden:",msg)
else
    warn("ℹ️ Kein Aura-Egg gefunden.")
end

-- 2) Weitere Eggs prüfen
for _,name in ipairs(eggNames) do
    local egg = rifts:FindFirstChild(name)
    if egg then
        local luck,timeTxt = getEggStats(egg)
        if luck then
            local out = egg:FindFirstChild("Output")
            local y = out and out.Position.Y or 0
            local dispName = name:gsub("%-"," "):gsub("^%l",string.upper)
            local msg = ("%s Egg %dx %s Height: %.2f Time: %s"):format(dispName,luck,formatServerLink(),y,timeTxt or "n/A")
            pcall(sendToWebhook,msg)
            print("✅ Egg gefunden:",msg)
        end
    end
end

-- 3) Optional: Bestes Egg
local best,bl,bt
for _,ef in ipairs(rifts:GetChildren()) do
    if ef.Name~="aura" and table.find(eggNames,ef.Name) then
        local luck,timeTxt = getEggStats(ef)
        if luck and (not bl or luck>bl) then best,bl,bt=ef,luck,timeTxt end
    end
end
if best and bl>=requiredLuck then
    local out = best:FindFirstChild("Output")
    local y = out and out.Position.Y or 0
    local msg = ("Best Egg %s %dx %s Height: %.2f Time: %s"):format(best.Name,bl,formatServerLink(),y,bt or "n/A")
    pcall(sendToWebhook,msg)
    print("✅ Bestes Egg:",msg)
end
