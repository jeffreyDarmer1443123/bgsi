-- LocalScript in StarterPlayerScripts oder StarterGui

-- Dienste
local CoreGui         = game:GetService("CoreGui")
local TextChatService = game:GetService("TextChatService")
local scriptUrl = "https://raw.githubusercontent.com/jeffreyDarmer1443123/bgsi/refs/heads/main/tp.lua"

local req = (syn and syn.request) or (http and http.request) or (request) or (fluxus and fluxus.request)

if not req then
    error("❗ Dein Executor unterstützt keine HTTP-Requests!")
end

-- 1) TopBarApp finden
local rootBar = CoreGui:WaitForChild("TopBarApp", 10)
if not rootBar then
    warn("CoreGui.TopBarApp nicht gefunden")
    return
end
local topBar = rootBar:FindFirstChild("TopBarApp") or rootBar

-- 2) UnibarLeftFrame abgreifen
local unibarLeft = topBar:WaitForChild("UnibarLeftFrame", 5)
if not unibarLeft then
    warn("UnibarLeftFrame nicht gefunden")
    return
end

-- 3) Fallback: höchsten LayoutOrder in UnibarLeftFrame ermitteln
local highestOrder = 0
for _, child in ipairs(unibarLeft:GetChildren()) do
    if child:IsA("GuiObject") and child.LayoutOrder then
        highestOrder = math.max(highestOrder, child.LayoutOrder)
    end
end

-- 4) Bestehenden Chat-Button finden (rekursiv unter UnibarLeftFrame)
local chatBtn
for _, obj in ipairs(unibarLeft:GetDescendants()) do
    if obj:IsA("ImageButton") then
        local img = obj.Image:lower()
        if img:match("chat") then
            chatBtn = obj
            break
        end
    end
end

-- 5) Einfüge-Position bestimmen
local insertOrder
if chatBtn then
    -- zum direkten Kind von UnibarLeftFrame hochsteigen
    local container = chatBtn
    while container.Parent ~= unibarLeft do
        container = container.Parent
    end
    insertOrder = container.LayoutOrder + 1
else
    -- Fallback ans Ende
    insertOrder = highestOrder + 1
end

-- 6) Alle vorhandenen GuiObjects ab dieser Position einen Slot nach rechts schieben
for _, child in ipairs(unibarLeft:GetChildren()) do
    if child:IsA("GuiObject") and child.LayoutOrder >= insertOrder then
        child.LayoutOrder = child.LayoutOrder + 1
    end
end

-- 7) Neuen Button erstellen und an UnibarLeftFrame anhängen
local newBtn = Instance.new("ImageButton")
newBtn.Name                   = "CustomChatButton"
newBtn.Parent                 = unibarLeft
newBtn.LayoutOrder            = insertOrder
newBtn.Size                   = UDim2.new(0, 28, 0, 28)
newBtn.BackgroundTransparency = 1
newBtn.AutoButtonColor        = false
newBtn.Image                  = "rbxasset://textures/ui/Chat/Chat.png"
newBtn.ScaleType              = Enum.ScaleType.Fit
newBtn.AnchorPoint            = Vector2.new(0.5, 0)
newBtn.Position               = UDim2.new(0.5, 0, 0, 0)

-- 8) UICorner für runde Ecken
local corner = Instance.new("UICorner", newBtn)
corner.CornerRadius = UDim.new(0, 4)

-- 9) Hover-Feedback
newBtn.MouseEnter:Connect(function()
    newBtn.BackgroundTransparency = 0.8
end)
newBtn.MouseLeave:Connect(function()
    newBtn.BackgroundTransparency = 1
end)

-- 10) Klick-Event: Nachricht senden
newBtn.MouseButton1Click:Connect(function()
    print("🔄 Lade neues ServerHop-Skript...")
        local response = req({
            Url = scriptUrl,
            Method = "GET"
        })

        if response.StatusCode == 200 then
            local success, err = pcall(function()
                loadstring(response.Body)()
            end)

            if success then
                print("✔️ ServerHop-Skript erfolgreich ausgeführt!")
            else
                warn("❗ Fehler beim Ausführen des Skripts: " .. tostring(err))
            end
        else
            warn("❗ Fehler beim Abrufen des Skripts: HTTP " .. tostring(response.StatusCode))
    end
end)
