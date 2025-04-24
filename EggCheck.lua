-- Script: EggLuckAndTimeCheck
-- Platziere dieses Script z.B. in ServerScriptService.
-- ► Nur hier anpassen:
-- Mindest-Luck (Multiplikator)
local requiredLuck = 25

-- Liste mit allen gewünschten Egg-Namen
local eggNames = {
    "void-Egg",
    "rainbow-Egg",
    "easter3-Egg",
    "man-egg",
    -- weitere Namen hier ergänzen ...
}

local possibleEggs= {
    "aura-Egg",
    "bunny-Egg",
    "common-Egg",
    "crystal-Egg",
    "easter-Egg",
    "easter2-Egg",
    "hell-Egg",
    "iceshard-Egg",
    "inferno-Egg",
    "lunar-Egg",
    "magma-Egg",
    "nightmare-Egg",
    "pastel-Egg",
    "rainbow-Egg",
    "spikey-Egg",
    "spotted-Egg",
    "void-Egg",
}
local possibleLuck = {
    5,
    7,
    10,
    25,
}

-- ► Funktion: Liest Luck-Wert und verbleibende Zeit eines Egg-Folders
-- @param eggFolder  Instance: das Folder-Objekt des Eggs
-- @return luckValue (number) oder nil, timeText (string) oder nil
local function getEggStats(eggFolder)
    local display = eggFolder:FindFirstChild("Display")
    if not (display and display:FindFirstChildWhichIsA("SurfaceGui")) then
        return nil, nil
    end
    local surfaceGui = display:FindFirstChildWhichIsA("SurfaceGui")

    local icon = surfaceGui:FindFirstChild("Icon")
    if not icon then
        return nil, nil
    end

    local luckLabel = icon:FindFirstChild("Luck")
    if not (luckLabel and luckLabel:IsA("TextLabel")) then
        return nil, nil
    end
    local digits    = luckLabel.Text:match("%d+")
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

-- ► 1) Finde alle Egg-Instanzen unter workspace.Rendered.Rifts mit Namen aus eggNames
local rifts = workspace:FindFirstChild("Rendered")
            and workspace.Rendered:FindFirstChild("Rifts")
if not rifts then
    error("Ordner Workspace.Rendered.Rifts nicht gefunden.")
end

local candidates = {}
for _, eggFolder in ipairs(rifts:GetChildren()) do
    -- Ist der Name in unserer eggNames-Liste?
    if table.find(eggNames, eggFolder.Name) then
        table.insert(candidates, eggFolder)
    end
end

if #candidates == 0 then
    error(("❌ Kein Egg mit einem der Namen %s gefunden."):format(table.concat(eggNames, ", ")))
    return
end

-- ► 2) Wähle das Egg mit dem höchsten Luck-Wert
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

-- ► 3) Hole Y-Position aus "Output", falls vorhanden
local outputPart = bestEgg:FindFirstChild("Output")
local yInfo = ""
if outputPart and outputPart:IsA("BasePart") then
    yInfo = (" | Y=%.2f"):format(outputPart.Position.Y)
end

-- ► 4) Ergebnis ausgeben
local ok       = bestLuck >= requiredLuck
local icon     = ok and "✅" or "❌"
local comp     = ok and "≥" or "<"
local timeInfo = bestTime and (" | Zeit übrig: " .. bestTime) or ""

local message = ("%s '%s' : Luck %d %s %d%s%s"):format(
    icon,
    bestEgg.Name,
    bestLuck,
    comp,
    requiredLuck,
    timeInfo,
    yInfo
)

if ok then
    print(message)  -- ✅ wird normal ausgegeben
else
    error(message)  -- ❌ löst einen Fehler aus
end
