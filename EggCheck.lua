local requiredLuck = shared.requiredLuck or error("Kein Luck in requiredLuck definiert!")

local eggNames = shared.eggNames or error("Keine EggNames in shared.eggNames definiert!")

local webhookUrl = shared.webhookUrl or error("Keine Webhook-URL in shared.webhookUrl definiert!")
local foundEgg = shared.foundEgg

local function sendWebhookEmbed(eggName, luck, time, height, jobId, placeId)
	local HttpService = game:GetService("HttpService")

	local isManEgg = eggName:lower() == "aura"
	local embedColor = isManEgg and 0x9B59B6 or 0x2ECC71
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



local function getEggStats(eggFolder)
    local gui = eggFolder:FindFirstChild("Display"):FindFirstChildWhichIsA("SurfaceGui")
    if not gui then return nil, nil end

    local luckText = gui:FindFirstChild("Icon") and gui.Icon:FindFirstChild("Luck")
    local timer = gui:FindFirstChild("Timer") or gui:FindFirstChildWhichIsA("TextLabel")
    
    local luckValue = luckText and tonumber(luckText.Text:match("%d+")) or nil
    local timeText = timer and timer.Text or nil
    return luckValue, timeText
end


local rifts = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then
    error("Ordner Workspace.Rendered.Rifts nicht gefunden.")
end

local manEgg = rifts:FindFirstChild("aura")
if manEgg then
    local luck, timeText = getEggStats(manEgg)
    local yInfo = ""
    local outputPart = manEgg:FindFirstChild("Output")
    if outputPart and outputPart:IsA("BasePart") then
        yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
    end
    local timeInfo = timeText and (" | Zeit übrig: " .. timeText) or ""
    print(("✅ 'aura': Luck %s%s%s"):format(luck or "n/A", timeInfo, yInfo))
else
    print("ℹ️ Kein 'aura' gefunden.")
end

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

local yInfo = ""
local outputPart = bestEgg:FindFirstChild("Output")
if outputPart and outputPart:IsA("BasePart") then
    yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
end

local ok = bestLuck >= requiredLuck
local icon = ok and "✅" or "❌"
local comp = ok and "≥" or "<"
local timeInfo = bestTime and (" | Zeit übrig: " .. bestTime) or ""
local message = ("%s '%s': Luck %d %s %d%s%s")
    :format(icon, bestEgg.Name, bestLuck, comp, requiredLuck, timeInfo, yInfo)
if ok then
    print(message)
    print("📡 DEBUG: Sende Webhook jetzt...")

    sendWebhookEmbed(
        bestEgg.Name,
        bestLuck,
        bestTime,
        outputPart and outputPart.Position.Y or 0,
        game.JobId,
        game.PlaceId
    )

    print("✅ DEBUG: sendWebhookEmbed wurde aufgerufen.")
    shared.foundEgg = True
else
    error(message)
end
