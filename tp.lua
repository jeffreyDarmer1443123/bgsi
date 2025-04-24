-- ganz oben einreihen, damit nach Teleport automatisch neu gestartet wird
if syn and syn.queue_on_teleport then
  syn.queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/jeffreyDarmer1443123/bgsi/refs/heads/main/tp.lua'))()")
end

local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")
local PlaceID         = game.PlaceId
local CurrentServer  = game.JobId

local Config = {
    MinPlayers        = 2,
    RequiredFreeSlots = 2,
    BaseDelay         = 5,    -- etwas länger
    MaxRetries        = 5,
    RateLimitThreshold= 3,
}

local attemptCount = 0
local rateLimitCount = 0

local function debugLog(...)
    print(os.date("[%H:%M:%S]").." [ServerHopper]", ...)
end

local function safeHttpGet(url)
    -- Fallback immer auf game:HttpGet, um Crash zu vermeiden
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok then return res end
    return nil
end

local function fetchServers()
    if rateLimitCount >= Config.RateLimitThreshold then return nil end
    local raw = safeHttpGet(
      ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PlaceID)
    )
    if not raw then
      rateLimitCount += 1
      debugLog("HTTP fehlgeschlagen, RateLimitCount=", rateLimitCount)
      return nil
    end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok then
      debugLog("JSONDecode-Error")
      return nil
    end
    return data.data
end

local function filterServers(list)
    local out = {}
    for _, s in ipairs(list) do
        if s.id ~= CurrentServer
          and s.playing >= Config.MinPlayers
          and (s.maxPlayers - s.playing) >= Config.RequiredFreeSlots
          and not s.vip
        then
          table.insert(out, s.id)
        end
    end
    return out
end

local function attemptTeleport()
    local servers = fetchServers()
    if not servers then return false end
    local valid = filterServers(servers)
    if #valid == 0 then return false end

    local target = valid[math.random(#valid)]
    debugLog("Teleportiere zu:", target)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceID, target, Players.LocalPlayer)
    end)
    if not ok then
      debugLog("Teleport-Error:", err)
      return false
    end
    return true
end

local function main()
    while attemptCount < Config.MaxRetries do
        attemptCount += 1
        if attemptTeleport() then
            debugLog("Erfolgreich initiiert")
            return
        end
        local delay = math.min(Config.BaseDelay * attemptCount, 30)
        debugLog("Warte", delay.."s ("..attemptCount.."/"..Config.MaxRetries..")")
        task.wait(delay)
    end
    debugLog("MaxRetries erreicht – normal teleportieren")
    TeleportService:Teleport(PlaceID, Players.LocalPlayer)
end

debugLog("Starte ServerHopper für Platz", PlaceID)
main()
