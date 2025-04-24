-- Script: EggLuckAndTimeCheck
-- Platziere dieses Script z.B. in ServerScriptService.
-- ► Nur hier anpassen:
local requiredLuck = 25

-- Liste mit allen gewünschten Egg-Namen (ohne man-egg)
local eggNames = {
    "void-egg",
    "rainbow-egg",
    "easter3-egg",
    -- weitere Namen hier ergänzen ...
}

local webhookUrl = _G.webhookUrl or error("Keine Webhook-URL in _G.webhookUrl definiert!")

local function sendWebhookEmbed(eggName, luck, time, height, jobId, placeId)
	local HttpService = game:GetService("HttpService")

	local isManEgg = eggName:lower() == "man-egg"
	local embedColor = isManEgg and 0x9B59B6 or 0x2ECC71 -- Lila oder Grün
	local mention = isManEgg and "<@palkins7>" or ""

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
			syn.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData })
		elseif string.find(executor, "krnl") then
			http.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData })
		elseif string.find(executor, "fluxus") then
			fluxus.request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData })
		elseif string.find(executor, "awp") then
			request({ Url = webhookUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = jsonData })
		else
			game:GetService("HttpService"):PostAsync(webhookUrl, jsonData)
		end
	end)

	if not success then warn("❌ Webhook fehlgeschlagen:", err) end
end



-- ► Funktion: Liest Luck-Wert und verbleibende Zeit eines Egg-Folders
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

-- ► 2) Man-Egg immer ausgeben, falls vorhanden
local manEgg = rifts:FindFirstChild("man-egg")
if manEgg then
    local luck, timeText = getEggStats(manEgg)
    local yInfo = ""
    local outputPart = manEgg:FindFirstChild("Output")
    if outputPart and outputPart:IsA("BasePart") then
        yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
    end
    local timeInfo = timeText and (" | Zeit übrig: " .. timeText) or ""
    -- Immer als erfolgreich markieren
    print(("✅ 'man-egg': Luck %s%s%s"):format(luck or "n/A", timeInfo, yInfo))
else
    warn("ℹ️ Kein 'man-egg' gefunden.")
end

-- ► 3) Suche übrige Eggs aus eggNames
local candidates = {}
for _, eggFolder in ipairs(rifts:GetChildren()) do
    if eggFolder.Name ~= "man-egg" and table.find(eggNames, eggFolder.Name) then
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
        bestEgg = ef
        bestLuck = luck
        bestTime = timeText
    end
end
if not bestEgg then
    error(("❌ Luck-Wert für Eggs %s konnte nicht ermittelt werden."):format(table.concat(eggNames, ", ")))
    return
end

-- ► 5) Y-Position des besten Eggs
local yInfo = ""
local outputPart = bestEgg:FindFirstChild("Output")
if outputPart and outputPart:IsA("BasePart") then
    yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
end

-- ► 6) Ausgabe für das beste Egg
local ok = bestLuck >= requiredLuck
local icon = ok and "✅" or "❌"
local comp = ok and "≥" or "<"
local timeInfo = bestTime and (" | Zeit übrig: " .. bestTime) or ""
local message = ("%s '%s': Luck %d %s %d%s%s")
    :format(icon, bestEgg.Name, bestLuck, comp, requiredLuck, timeInfo, yInfo)
if ok then
    print(message)
    sendWebhookEmbed(eggName, luck, time, height, jobId, placeId)
else
    error(message)
end
