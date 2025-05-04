--// Verbesserte EggCheck.lua

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Sicherstellen, dass shared-Variablen existieren
local requiredLuck = shared.requiredLuck
local eggNames = shared.eggNames
local PrioEgg = shared.PrioEgg

local webhookUrl = shared.webhookUrl
local username = Players.LocalPlayer and Players.LocalPlayer.Name or "Unbekannt"

if not requiredLuck then
    warn(username .. " ⚠️ Kein Luck in shared.requiredLuck definiert!")
    shared.eggCheckFinished = true
    return
end
if not eggNames then
    warn(username .. " ⚠️ Keine EggNames in shared.eggNames definiert!")
    shared.eggCheckFinished = true
    return
end
if not webhookUrl then
    warn(username .. " ⚠️ Keine Webhook-URL in shared.webhookUrl definiert!")
    shared.eggCheckFinished = true
    return
end

-- Versucht nacheinander alle gängigen HTTP-Funktionen in einer pcall-Hülle
local function safeRequest(opts)
    local methods = {}
    if syn and syn.request then table.insert(methods, syn.request) end
    if fluxus and fluxus.request then table.insert(methods, fluxus.request) end
    if http and http.request then table.insert(methods, http.request) end
    if request then table.insert(methods, request) end
    if http_request then table.insert(methods, http_request) end
    -- Fallback HttpService
    table.insert(methods, function(o)
        return HttpService:RequestAsync({
            Url     = o.Url,
            Method  = o.Method,
            Headers = o.Headers,
            Body    = o.Body,
        })
    end)

    for _, fn in ipairs(methods) do
        local ok, res = pcall(fn, opts)
        if ok and type(res) == "table" then
            local code = res.StatusCode or res.code or 0
            if (res.Success ~= false) and (code >= 200 and code < 300) then
                return true, res
            end
        end
    end
    return false, "Kein HTTP-Call hat erfolgreich geantwortet"
end

-- Webhook Funktion
-- Anpassen der sendWebhookEmbed-Funktion
local function sendWebhookEmbed(eggName, luck, timeText, height, jobId, placeId)
    local isSilly = (eggName:lower() == "silly-egg")
    local color   = isSilly and 0x9B59B6 or 0x2ECC71
    local mention = isSilly and "<@palkins7>" or ""

    local serverLink = ("https://jeffreydarmer1443123.github.io/?placeId=%d&gameInstanceId=%s")
                      :format(placeId, jobId)

    local payload = {
        content = mention,
        embeds  = {{
            title  = "🥚 Ei gefunden!",
            color  = color,
            fields = {
                { name = "🐣 Egg",  value = eggName,       inline = true },
                { name = "💥 Luck", value = tostring(luck), inline = true },
                { name = "⏳ Zeit", value = timeText or "N/A", inline = true },
                { name = "📏 Höhe", value = string.format("%.2f", height), inline = true },
                { name = "🔗 Server Link",
                  value = "[Join Link](" .. serverLink .. ")", inline = false },
            },
        }},
    }

    local jsonData = HttpService:JSONEncode(payload)
    local requestArgs = {
        Url     = webhookUrl,
        Method  = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body    = jsonData,
    }

    local success, res = safeRequest(requestArgs)
    if not success then
        warn(username .. " ❌ Webhook fehlgeschlagen: " .. tostring(res or "Keine Antwort"))
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
    warn(username .. " ❌ Ordner Workspace.Rendered.Rifts nicht gefunden.")
    shared.eggCheckFinished = true
    return
end

local MillEgg = rifts:FindFirstChild(PrioEgg)
if MillEgg then
    local luck, timeText = getEggStats(MillEgg)
    local outputPart = MillEgg:FindFirstChild("Output")
    local height = outputPart and outputPart.Position.Y or 0

    sendWebhookEmbed(
        MillEgg.Name,
        luck or 0,
        timeText or "N/A",
        height,
        game.JobId,
        game.PlaceId
    )

    shared.foundEgg = true
    shared.eggCheckFinished = true
    print((username or "?") .. " 🟣 MillEgg gefunden! Luck: "..tostring(luck or "?")..", Zeit: "..tostring(timeText or "?"))
    return -- sofort beenden, da MillEgg priorisiert wird
end



-- Suche nach passenden Eiern
local candidates = {}
for _, eggFolder in ipairs(rifts:GetChildren()) do
    if eggFolder.Name ~= "silly-egg" and table.find(eggNames, eggFolder.Name) then
        table.insert(candidates, eggFolder)
    end
end

if #candidates == 0 then
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

local numericTime = parseTimeString(bestTime)
local ok = bestLuck >= requiredLuck and numericTime and numericTime >= shared.minTime
local icon = ok and "✅" or "❌"
local comp = ok and "≥" or "<"
local timeInfo = bestTime and (" | Zeit übrig: " .. bestTime) or ""
local message = ("%s '%s': Luck %d %s %d%s%s")
    :format(icon, bestEgg.Name, bestLuck, comp, requiredLuck, timeInfo, yInfo)

if ok then
    sendWebhookEmbed(
        bestEgg.Name,
        bestLuck,
        bestTime,
        outputPart and outputPart.Position.Y or 0,
        game.JobId,
        game.PlaceId
    )
    shared.foundEgg = false
    shared.eggCheckFinished = true
    print(username .. " ✅ Egg gefunden und gemeldet!")
else
    shared.eggCheckFinished = true
end
