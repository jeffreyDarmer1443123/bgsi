-- button.lua (LocalScript)

-- Dienste
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then
    warn("❗ PlayerGui nicht gefunden")
    return
end

-- Konfiguration via getgenv
local scriptUrl = getgenv().tpUrl or "https://raw.githubusercontent.com/jeffreyDarmer1443123/bgsi/main/tp.lua"

-- HTTP-Request-Funktion
local req = (syn and syn.request) or (http and http.request) or (request) or (fluxus and fluxus.request)
if not req then
    error("❗ Dein Executor unterstützt keine HTTP-Requests!")
end

-- GUI Parent
local CoreGui = game:GetService("CoreGui")
local root = CoreGui:FindFirstChild("TopBarApp")
if not root then
    warn("CoreGui.TopBarApp nicht gefunden")
    return
end
local unibarLeft = root:FindFirstChild("UnibarLeftFrame", true) or root:WaitForChild("UnibarLeftFrame",5)
if not unibarLeft then
    warn("UnibarLeftFrame nicht gefunden")
    return
end

-- Alte Buttons entfernen
if unibarLeft:FindFirstChild("CustomHopButton") then
    unibarLeft.CustomHopButton:Destroy()
end

-- Beste LayoutOrder bestimmen
local highestOrder = 0
for _, child in ipairs(unibarLeft:GetChildren()) do
    if child:IsA("GuiObject") and child.LayoutOrder then
        highestOrder = math.max(highestOrder, child.LayoutOrder)
    end
end
local insertOrder = highestOrder + 1

-- Buttons nach rechts schieben
for _, child in ipairs(unibarLeft:GetChildren()) do
    if child:IsA("GuiObject") and child.LayoutOrder >= insertOrder then
        child.LayoutOrder += 1
    end
end

-- Neuen Button erstellen
local newBtn = Instance.new("ImageButton")
newBtn.Name = "CustomHopButton"
newBtn.Parent = unibarLeft
newBtn.LayoutOrder = insertOrder
newBtn.Size = UDim2.new(0, 28, 0, 28)
newBtn.BackgroundTransparency = 1
newBtn.AutoButtonColor = false
newBtn.Image = "rbxasset://textures/ui/Chat/Chat.png"
newBtn.ScaleType = Enum.ScaleType.Fit
newBtn.AnchorPoint = Vector2.new(0.5, 0)
newBtn.Position = UDim2.new(0.5, 0, 0, 0)

-- Optische Anpassungen
local corner = Instance.new("UICorner", newBtn)
corner.CornerRadius = UDim.new(0, 4)
newBtn.MouseEnter:Connect(function() newBtn.BackgroundTransparency = 0.8 end)
newBtn.MouseLeave:Connect(function() newBtn.BackgroundTransparency = 1 end)

-- Klick-Event
newBtn.MouseButton1Click:Connect(function()
    print("🔄 Lade ServerHop-Skript...")
    local response = req({ Url = scriptUrl, Method = "GET" })
    if response and response.StatusCode == 200 then
        local fn, err = loadstring(response.Body)
        if not fn then
            return warn("❗ Compile-Fehler: " .. tostring(err))
        end
        local success, runErr = pcall(fn)
        if success then
            print("✔️ ServerHop-Skript erfolgreich ausgeführt!")
        else
            warn("❗ Fehler beim Ausführen: " .. tostring(runErr))
        end
    else
        warn("❗ HTTP-Fehler beim Abrufen des Skripts:", response and response.StatusCode or "Keine Antwort")
    end
end)