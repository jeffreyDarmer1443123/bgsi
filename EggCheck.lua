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
