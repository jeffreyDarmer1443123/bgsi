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
    local age = now() - (initial.lockTimestamp or 0)

    -- 🧤 Schutz vor zu frühem Zugriff
    if initial.refreshInProgress and age < timeout then
        return false, "Lock aktiv von "..tostring(initial.lockOwner)
    end

    -- 💤 Verzögerung vor Schreibzugriff (Entzerrung)
    task.wait(math.random(1, 3))

    -- 🧪 Nachprüfen, ob sich jemand anderes den Lock geholt hat
    local current = readLock()
    local currentAge = now() - (current.lockTimestamp or 0)

    if current.refreshInProgress and currentAge < timeout then
        return false, "Lock wurde gerade übernommen von "..tostring(current.lockOwner)
    end

    -- 📝 Jetzt sicheren Lock setzen
    local newLock = {
        refreshInProgress = true,
        lockOwner = username,
        lockTimestamp = now(),
    }
    writeLock(newLock)

    -- 🔁 Bestätigen, dass unser Lock wirklich aktiv ist
    local confirm = readLock()
    if confirm.lockOwner == username then
        return true
    else
        return false, "Lockkollision bei Bestätigung"
    end
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
