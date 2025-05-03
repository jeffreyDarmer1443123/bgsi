-- LocalScript in StarterPlayerScripts

local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")

-- URL zum ServerHop-Skript
local scriptUrl = "https://raw.githubusercontent.com/jeffreyDarmer1443123/bgsi/refs/heads/main/tp.lua"

-- Fallback für HTTP-Requests (Executor-kompatibel)
local req = (syn and syn.request)
         or (http and http.request)
         or request
         or (fluxus and fluxus.request)
\if not req then
    error("❗ Dein Executor unterstützt keine HTTP-Requests!")
end

-- Warte auf PlayerGui
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

-- Neues ScreenGui anlegen
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomButtonGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = gui

-- Button erstellen
local btn = Instance.new("ImageButton")
btn.Name                   = "ServerHopButton"
btn.Size                   = UDim2.new(0, 32, 0, 32)
btn.Position               = UDim2.new(0, 10, 0, 10)
btn.BackgroundTransparency = 1
btn.Image                  = "rbxasset://textures/ui/Chat/Chat.png"
btn.AnchorPoint            = Vector2.new(0, 0)
btn.Parent                 = screenGui

-- Runde Ecken
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent       = btn

-- Hover-Effekt
btn.MouseEnter:Connect(function()
    btn.BackgroundTransparency = 0.8
end)
btn.MouseLeave:Connect(function()
    btn.BackgroundTransparency = 1
end)

-- Klick-Event: lade und führe tp.lua aus
btn.MouseButton1Click:Connect(function()
    print("🔄 Lade ServerHop-Skript...")
    local response = req({ Url = scriptUrl, Method = "GET" })

    if response and response.StatusCode == 200 then
        local ok, err = pcall(loadstring, response.Body)
        if ok then
            print("✔️ ServerHop-Skript erfolgreich ausgeführt!")
        else
            warn("❗ Fehler beim Ausführen des Skripts: " .. tostring(err))
        end
    else
        warn("❗ Fehler beim Abrufen des Skripts: HTTP " .. tostring(response and response.StatusCode))
    end
end)
