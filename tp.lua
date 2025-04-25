-- tp.lua
--==================================================================
-- Einmaliger, robuster Server-Hop
--==================================================================

local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")

local PlaceID         = game.PlaceId
local CurrentJobId    = game.JobId

--===============
-- 1) TeleportInitFailed-Handler
--===============  
-- Wenn Roblox den Teleport abbricht, kicken wir uns selbst und rejoinen
TeleportService.TeleportInitFailed:Connect(function(errCode, errMsg)
    warn("[ServerHop] TeleportInitFailed:", errCode, errMsg, "→ Kick & Rejoin")
    pcall(function()
        Players.LocalPlayer:Kick("Auto-Rejoin…")
    end)
    task.wait(1)
    TeleportService:Teleport(PlaceID)
end)

--===============
-- 2) Simpler interner Teleport
--===============  
-- Wir verzichten komplett auf HTTP-Rate-Limits
task.wait(0.5)  -- kurz warten, falls TeleportService noch in „IsTeleporting“ steckt
pcall(function()
    TeleportService:Teleport(PlaceID)
end)
