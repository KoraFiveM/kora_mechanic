local state = { vehicle = 0, coords = nil, speed = 0.0, engineHealth = nil, bodyHealth = nil, nextTyreRoll = 0 }

local function eligible(vehicle)
    return vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
        and not Config.damage.excludedClasses[GetVehicleClass(vehicle)]
end

local function lowerHealth(vehicle, getter, setter, amount)
    if amount <= 0 then return end
    setter(vehicle, math.max(-4000.0, getter(vehicle) - amount))
end

local function reset(vehicle)
    if state.vehicle ~= 0 and DoesEntityExist(state.vehicle) then SetVehicleEngineTorqueMultiplier(state.vehicle, 1.0) end
    state.vehicle, state.coords, state.speed = vehicle or 0, nil, 0.0
    state.engineHealth, state.bodyHealth, state.nextTyreRoll = nil, nil, 0
end

local function rollTyreBurst(vehicle, speed)
    local tyres = Config.damage.tyres
    if not tyres.enabled or speed < tyres.minSpeed or GetVehicleEngineHealth(vehicle) > tyres.minEngineHealth then return end
    local now = GetGameTimer()
    if now < state.nextTyreRoll then return end
    state.nextTyreRoll = now + tyres.checkInterval
    if math.random() >= tyres.chance then return end
    local wheels = GetVehicleNumberOfWheels(vehicle)
    if wheels > 0 then SetVehicleTyreBurst(vehicle, math.random(0, wheels - 1), tyres.burstOnRims, 1000.0) end
end

-- Only runs while the player drives an eligible vehicle: kora_lib's cache
-- 'seat'/'vehicle' change events start it, and it exits once that ends.
local damageWorkerRunning = false

local function startDamageWorker()
    if damageWorkerRunning then return end
    if not eligible(GetVehiclePedIsIn(PlayerPedId(), false)) then return end

    damageWorkerRunning = true
    CreateThread(function()
        while true do
            Wait(Config.damage.interval)
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if not eligible(vehicle) then
                if state.vehicle ~= 0 then reset(0) end
                break
            end
            if not Config.damage.enabled then goto continue end
            if state.vehicle ~= vehicle then reset(vehicle) end

            local coords, speed = GetEntityCoords(vehicle), GetEntitySpeed(vehicle)
            local engineHealth, bodyHealth = GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle)
            if state.coords then
                local distance = #(coords - state.coords)
                if Config.damage.distanceWear.enabled and speed >= Config.damage.distanceWear.minSpeed then
                    local km = distance / 1000.0
                    lowerHealth(vehicle, GetVehicleEngineHealth, SetVehicleEngineHealth, km * Config.damage.distanceWear.enginePerKm)
                    lowerHealth(vehicle, GetVehicleBodyHealth, SetVehicleBodyHealth, km * Config.damage.distanceWear.bodyPerKm)
                end

                local speedLoss = state.speed - speed
                -- Deceleration alone is not evidence of a crash: braking, handbrake
                -- turns and releasing the throttle can all exceed minSpeedLoss.
                -- Native health loss since our previous sample is persistent crash
                -- evidence, unlike HasEntityCollidedWithAnything (current frame only).
                local minHealthLoss = Config.damage.collision.minNativeHealthLoss or 1.0
                local collisionDamage = state.engineHealth and state.bodyHealth
                    and (engineHealth < state.engineHealth - minHealthLoss or bodyHealth < state.bodyHealth - minHealthLoss)
                if Config.damage.collision.enabled and collisionDamage and speedLoss >= Config.damage.collision.minSpeedLoss then
                    lowerHealth(vehicle, GetVehicleEngineHealth, SetVehicleEngineHealth, math.min(Config.damage.collision.maxEngineDamage, speedLoss * Config.damage.collision.engineDamagePerSpeedLoss))
                    lowerHealth(vehicle, GetVehicleBodyHealth, SetVehicleBodyHealth, math.min(Config.damage.collision.maxBodyDamage, speedLoss * Config.damage.collision.bodyDamagePerSpeedLoss))
                end
            end
            rollTyreBurst(vehicle, speed)

            local limp = Config.damage.limpMode
            if limp.enabled and GetVehicleEngineHealth(vehicle) <= limp.engineHealthThreshold then
                SetVehicleEngineTorqueMultiplier(vehicle, limp.torqueMultiplier)
                if speed >= limp.stallMinSpeed and math.random() < limp.stallChance then SetVehicleEngineOn(vehicle, false, true, true) end
            else
                SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
            end
            state.coords, state.speed = coords, speed
            state.engineHealth, state.bodyHealth = GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle)
            ::continue::
        end
        damageWorkerRunning = false
    end)
end

local function watchDriving()
    Kora.cache.onChange('seat', startDamageWorker)
    Kora.cache.onChange('vehicle', startDamageWorker)
    startDamageWorker()
end

watchDriving()
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_lib' then watchDriving() end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then reset(0) end
end)
