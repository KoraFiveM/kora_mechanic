local lastSave = {}

local TUNING = {
    color1 = 'colour', color2 = 'colour', pearlescentColor = 'colourId', wheelColor = 'colourId',
    dashboardColor = 'colourId', interiorColor = 'colourId', wheels = { 0, 13 }, wheelSize = 'float', wheelWidth = 'float',
    windowTint = { -1, 6 }, plateIndex = { 0, 5 }, neonEnabled = 'bools4', neonColor = 'rgb', tyreSmokeColor = 'rgb',
    xenonColor = 'xenon', extras = 'extras', modSmokeEnabled = 'bool', modXenon = 'bool', modTurbo = 'bool',
    modCustomTiresF = 'bool', modCustomTiresR = 'bool', modLivery = { -1, 200 }, liveryRoof = { -1, 200 },
}
local WEAR = {
    dirtLevel = 'level', oilLevel = 'level', tankHealth = 'health', tireHealth = 'tyreMap',
    tireBurstState = 'tyreFlags', tireBurstCompletely = 'tyreFlags', windowStatus = 'statusMap', doorStatus = 'statusMap',
}

local function int(value, min, max)
    if type(value) ~= 'number' or value % 1 ~= 0 or value < min or value > max then return nil end
    return value
end

local function num(value, min, max)
    if type(value) ~= 'number' or value ~= value or value < min or value > max then return nil end
    return value
end

local function rgb(value)
    if type(value) ~= 'table' then return nil end
    local out = {}
    for index, key in ipairs({ 'r', 'g', 'b' }) do
        local channel = int(value[key] or value[index], 0, 255)
        if channel == nil then return nil end
        out[key] = channel
    end
    return out
end

local function keyedMap(value, validate, maxKeys)
    if type(value) ~= 'table' then return nil end
    local out, count = {}, 0
    for key, item in pairs(value) do
        local index = tonumber(key)
        count = count + 1
        if not index or index % 1 ~= 0 or index < 0 or index > 20 or count > maxKeys then return nil end
        local checked = validate(item)
        if checked == nil then return nil end
        out[tostring(index)] = checked
    end
    return out
end

local KINDS = {
    bool = function(v) if type(v) == 'boolean' then return v end end,
    colourId = function(v) return int(v, 0, 255) end,
    colour = function(v) if type(v) == 'table' then return rgb(v) end return int(v, 0, 255) end,
    rgb = rgb,
    xenon = function(v) if type(v) == 'table' then return rgb(v) end return int(v, -1, 12) end,
    float = function(v) return num(v, 0, 10) end,
    level = function(v) return num(v, 0, 15) end,
    health = function(v) return num(v, 0, 1000) end,
    bools4 = function(v)
        if type(v) ~= 'table' then return nil end
        local out = {}
        for index = 1, 4 do
            if type(v[index]) ~= 'boolean' then return nil end
            out[index] = v[index]
        end
        return out
    end,
    extras = function(v) return keyedMap(v, function(x) if type(x) == 'boolean' then return x end end, 21) end,
    tyreMap = function(v) return keyedMap(v, function(x) return num(x, 0, 1000) end, 10) end,
    tyreFlags = function(v) return keyedMap(v, function(x) if type(x) == 'boolean' then return x end end, 10) end,
    statusMap = function(v) return keyedMap(v, function(x) if type(x) == 'boolean' then return x end end, 10) end,
}

local function checkField(rule, value)
    if type(rule) == 'table' then return int(value, rule[1], rule[2]) end
    return KINDS[rule](value)
end

local function sanitizeProps(props, tuning)
    if type(props) ~= 'table' then return nil, 'invalid properties' end
    local out, count = {}, 0
    for key, value in pairs(props) do
        count = count + 1
        if type(key) ~= 'string' or count > 160 then return nil, 'invalid properties' end
        local rule = WEAR[key] or (tuning and (TUNING[key] or (key:match('^mod%u%w*$') and { -1, 200 })))
        if rule then
            local checked = checkField(rule, value)
            if checked == nil then return nil, ('invalid value for %s'):format(key) end
            out[key] = checked
        end
    end
    if next(out) == nil then return nil, 'nothing to save' end
    if #json.encode(out) > Config.propsSave.maxBytes then return nil, 'properties too large' end
    return out
end

local function normalisePlate(plate)
    if type(plate) ~= 'string' or #plate > 12 then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    return plate ~= '' and plate or nil
end

local function vehicleNear(src, plate)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local origin, limit = GetEntityCoords(ped), Config.propsSave.distance
    for _, vehicle in ipairs(GetAllVehicles()) do
        if normalisePlate(GetVehicleNumberPlateText(vehicle)) == plate and #(GetEntityCoords(vehicle) - origin) <= limit then
            return vehicle
        end
    end
end

local function isMechanic(src)
    local job = exports.kora_core:getJob(src)
    return job ~= nil and (not Config.roles.requireOnDuty or job.onduty) and Config.roles.roadsideJobs[job.name] ~= true
        and (job.name == Config.roles.fullRepairJob or job.type == Config.roles.automotiveType)
end

local function saveProps(src, props)
    if type(src) ~= 'number' or src < 1 or type(props) ~= 'table' then return false end
    local now = GetGameTimer()
    if lastSave[src] and now - lastSave[src] < Config.propsSave.cooldown then return false end
    lastSave[src] = now

    local plate = normalisePlate(props.plate)
    if not plate then return false end
    local citizenid = exports.kora_core:getPlayerData(src, { 'citizenid' })
    if type(citizenid) ~= 'string' then return false end
    local row = exports.kora_core:getByPlate(plate)
    if not row then return false end
    local mechanic = isMechanic(src)
    if not mechanic and row.citizenid ~= citizenid then return false end
    local vehicle = vehicleNear(src, plate)
    if not vehicle then return false end

    local sanitized = sanitizeProps(props, mechanic)
    if not sanitized then return false end
    local merged = {}
    for key, value in pairs(type(row.mods) == 'table' and row.mods or {}) do merged[key] = value end
    for key, value in pairs(sanitized) do merged[key] = value end
    merged.engineHealth = math.max(0, math.min(1000, GetVehicleEngineHealth(vehicle)))
    merged.bodyHealth = math.max(0, math.min(1000, GetVehicleBodyHealth(vehicle)))
    return exports.kora_core:saveVehicleProperties(row.plate, merged) == true
end

RegisterNetEvent('qb-mechanicjob:server:SaveVehicleProps', function(props)
    saveProps(source, props)
end)

AddEventHandler('playerDropped', function() lastSave[source] = nil end)
