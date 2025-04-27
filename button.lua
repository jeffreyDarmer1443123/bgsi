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
    screenGui.Parent = game:GetService("CoreGui")

    -- Button erstellen
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 200, 0, 50)
    button.Position = UDim2.new(0, 10, 0, 10)
    button.Text = "🌐 Server Hop!"
    button.BackgroundColor3 = Color3.fromRGB(50, 150, 255)
    button.TextColor3 = Color3.new(1,1,1)
    button.TextScaled = true
    button.Parent = screenGui

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
