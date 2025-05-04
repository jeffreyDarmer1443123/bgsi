-- 🔐 LockManager.lua
local HttpService = game:GetService("HttpService")

local LockManager = {}

local lockFile = "lock_data.json"
local defaultTimeout = 60

local function now()
    return os.time()
end

local function readLock()
    if not isfile(lockFile) then
        return {
            refreshInProgress = false,
            lockOwner = nil,
            lockTimestamp = 0,
        }
    end

    local content = readfile(lockFile)
    local ok, result = pcall(HttpService.JSONDecode, HttpService, content)
    if ok and type(result) == "table" then
        return result
    end

    return {
        refreshInProgress = false,
        lockOwner = nil,
        lockTimestamp = 0,
    }
end

local function writeLock(data)
    writefile(lockFile, HttpService:JSONEncode(data))
end

-- 📥 Versucht, den Lock zu übernehmen
function LockManager.Acquire(username, timeout)
    timeout = timeout or defaultTimeout

    local initial = readLock()

    if initial.refreshInProgress then
        local age = now() - (initial.lockTimestamp or 0)
        if age < timeout then
            -- 🔒 Lock ist noch gültig
            return false, "Lock aktiv von "..tostring(initial.lockOwner)
        end

        -- 💤 Warten, um Kollisionen zu vermeiden
        task.wait(math.random(1, 2))

        -- 🔄 Zweiter Check
        local latest = readLock()
        local latestAge = now() - (latest.lockTimestamp or 0)
        if latest.refreshInProgress and latestAge < timeout then
            return false, "Lock wurde übernommen von "..tostring(latest.lockOwner)
        end
    end

    -- 🔏 Setze neuen Lock
    local newLock = {
        refreshInProgress = true,
        lockOwner = username,
        lockTimestamp = now(),
    }
    writeLock(newLock)

    return true
end

-- 📤 Gibt den Lock wieder frei
function LockManager.Release(username)
    local current = readLock()
    if current.lockOwner == username then
        local cleared = {
            refreshInProgress = false,
            lockOwner = nil,
            lockTimestamp = 0,
        }
        writeLock(cleared)
        return true
    end
    return false
end

-- 🧐 Abfrage: Wer hat aktuell den Lock?
function LockManager.Status()
    return readLock()
end

return LockManager
