-- Kompatibilität für verschiedene Exploiter
local req = (syn and syn.request) or (http and http.request) or (request) or (fluxus and fluxus.request)

if not req then
    error("❗ Dein Executor unterstützt keine HTTP-Requests!")
end

-- Funktion, um Button + Funktionalität zu erstellen
local function createHopButton()
    -- URL deines tp.lua
    local scriptUrl = "https://raw.githubusercontent.com/jeffreyDarmer1443123/bgsi/refs/heads/main/tp.lua"

    -- ScreenGui erstellen
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ServerHopGui"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = game:GetService("CoreGui")

    -- Button erstellen
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 160, 0, 40)
    button.Position = UDim2.new(1, -180, 0, 20) -- Rechts oben (20px Abstand von oben/rechts)
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = "🌐 Server Hop"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextScaled = true
    button.Font = Enum.Font.GothamBold
    button.Parent = screenGui

    -- Abgerundete Ecken
    local uicorner = Instance.new("UICorner")
    uicorner.CornerRadius = UDim.new(0, 8)
    uicorner.Parent = button

    -- Hover-Effekt
    local function onHover()
        button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    end

    local function onUnhover()
        button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    end

    button.MouseEnter:Connect(onHover)
    button.MouseLeave:Connect(onUnhover)

    -- Klick-Funktion
    button.MouseButton1Click:Connect(function()
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
end

-- Funktion jetzt aufrufen
createHopButton()
