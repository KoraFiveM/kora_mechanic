local function notify(message, kind)
    Kora.notify.send({ title = 'Vehicle service', message = message, type = kind or 'info' })
end

local function playerJob()
    local ok, job = pcall(function() return exports.kora_core:getPlayerData({ 'job' }) end)
    return ok and job or nil
end

local function isOnDuty(job)
    return job and (not Config.roles.requireOnDuty or job.onduty)
end

local function canRepair()
    local job = playerJob()
    return isOnDuty(job) and (job.name == Config.roles.fullRepairJob or job.type == Config.roles.automotiveType)
end

local function canFullRepair()
    local job = playerJob()
    return canRepair() and not Config.roles.roadsideJobs[job.name]
end

local function canUseBodyshop()
    local job = playerJob()
    return isOnDuty(job) and (Config.roles.bodyshopJobs[job.name] or Config.roles.bodyshopTypes[job.type])
end

local function servicePayload(action, vehicle)
    if action == 'paint' then
        local primary, secondary = GetVehicleColours(vehicle)
        local response = Kora.nui.openInputDialog({
            { id = 'primary', label = 'Primary paint index', type = 'number', default = primary, min = Config.cosmetics.paintColourMin, max = Config.cosmetics.paintColourMax, required = true },
            { id = 'secondary', label = 'Secondary paint index', type = 'number', default = secondary, min = Config.cosmetics.paintColourMin, max = Config.cosmetics.paintColourMax, required = true },
        }, 'Respray vehicle', 'GTA palette indices; both colours are applied after the service.')
        if not response or response.cancelled then return nil end
        return { primary = math.floor(response.values.primary), secondary = math.floor(response.values.secondary) }
    end
    if action == 'bumpers' then
        SetVehicleModKit(vehicle, 0)
        local front, rear = GetVehicleMod(vehicle, 1), GetVehicleMod(vehicle, 2)
        local response = Kora.nui.openInputDialog({
            { id = 'front', label = 'Front bumper variation (-1 stock)', type = 'number', default = front, min = -1, max = Config.cosmetics.bumperModMax, required = true },
            { id = 'rear', label = 'Rear bumper variation (-1 stock)', type = 'number', default = rear, min = -1, max = Config.cosmetics.bumperModMax, required = true },
        }, 'Customise bumpers', 'Values are clamped to variations supported by this vehicle.')
        if not response or response.cancelled then return nil end
        return { front = math.floor(response.values.front), rear = math.floor(response.values.rear) }
    end
    return {}
end

local function durationFor(action)
    if action == 'fullRepair' then return Config.fullRepair.duration end
    if action == 'roadsideRepair' then return Config.roadsideRepair.duration end
    return Config.cosmetics.duration
end

local function labelFor(action)
    if action == 'fullRepair' then return Config.fullRepair.label end
    if action == 'roadsideRepair' then return Config.roadsideRepair.label end
    if action == 'paint' then return 'Respraying vehicle' end
    return 'Fitting bumper components'
end

local function beginService(action, vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local payload = servicePayload(action, vehicle)
    if payload == nil then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then return notify('This vehicle is not networked and cannot be serviced.', 'error') end

    local allowed, permitOrReason = Kora.callback.trigger('qbmechanic:permit', action, netId)
    if not allowed then return notify(permitOrReason or 'Service could not be authorised.', 'error') end

    local completed = Kora.progressbar.start({
        label = labelFor(action), duration = durationFor(action), canCancel = true,
        scenario = { name = 'WORLD_HUMAN_VEHICLE_MECHANIC' }, disable = { move = true, combat = true },
    })
    if not completed then return notify('Service cancelled.', 'warning') end
    TriggerServerEvent('qbmechanic:server:completeService', permitOrReason, payload)
end

local function fixOneTyre(vehicle)
    for index = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
        if IsVehicleTyreBurst(vehicle, index, false) then
            SetVehicleTyreFixed(vehicle, index)
            return true
        end
    end
    return false
end

RegisterNetEvent('qbmechanic:client:applyService', function(action, netId, payload)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)
        or not Kora.entities.requestControl(vehicle, 2000) then
        return notify('Could not obtain control of the vehicle. Try again.', 'error')
    end

    if action == 'fullRepair' then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleUndriveable(vehicle, false)
        notify('Full repair completed.', 'success')
    elseif action == 'roadsideRepair' then
        SetVehicleEngineHealth(vehicle, math.max(GetVehicleEngineHealth(vehicle), Config.roadsideRepair.engineHealthFloor))
        SetVehicleBodyHealth(vehicle, math.max(GetVehicleBodyHealth(vehicle), Config.roadsideRepair.bodyHealthFloor))
        if Config.roadsideRepair.repairOneTyre then fixOneTyre(vehicle) end
        SetVehicleUndriveable(vehicle, false)
        notify('Vehicle stabilised. It still needs a full garage repair.', 'success')
    elseif action == 'paint' then
        SetVehicleColours(vehicle, payload.primary, payload.secondary)
        notify('Respray completed.', 'success')
    elseif action == 'bumpers' then
        SetVehicleModKit(vehicle, 0)
        for _, entry in ipairs({ { type = 1, value = payload.front }, { type = 2, value = payload.rear } }) do
            local count = GetNumVehicleMods(vehicle, entry.type)
            local value = math.min(entry.value, count - 1)
            SetVehicleMod(vehicle, entry.type, value >= 0 and value or -1, false)
        end
        notify('Bumper customisation completed.', 'success')
    end
end)

exports['qb-target']:AddGlobalVehicle({ options = {
    -- kora_target invokes legacy `action` handlers inside a protected dispatch;
    -- start a fresh coroutine because dialogs, callbacks and progress bars all
    -- yield while the player works.
    { icon = 'fas fa-wrench', label = 'Full garage repair', action = function(entity) CreateThread(function() beginService('fullRepair', entity) end) end, canInteract = canFullRepair, distance = Config.interaction.distance },
    { icon = 'fas fa-truck-pickup', label = 'Roadside stabilisation', action = function(entity) CreateThread(function() beginService('roadsideRepair', entity) end) end, canInteract = canRepair, distance = Config.interaction.distance },
    { icon = 'fas fa-paint-roller', label = 'Respray vehicle', action = function(entity) CreateThread(function() beginService('paint', entity) end) end, canInteract = canUseBodyshop, distance = Config.interaction.distance },
    { icon = 'fas fa-car', label = 'Customise bumpers', action = function(entity) CreateThread(function() beginService('bumpers', entity) end) end, canInteract = canUseBodyshop, distance = Config.interaction.distance },
} })
