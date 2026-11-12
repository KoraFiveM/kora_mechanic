-- Client damage worker: started by kora_lib cache seat/vehicle changes, no idle loop.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path
local h = require('harness')

local threads, listeners, events = {}, {}, {}
local vehicle, driver = 0, 0
local PED = 1

_G.Config = { damage = { enabled = true, interval = 1500, excludedClasses = { [8] = true } } }
_G.CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
_G.Wait = function() coroutine.yield() end
_G.PlayerPedId = function() return PED end
_G.GetVehiclePedIsIn = function() return vehicle end
_G.GetPedInVehicleSeat = function() return driver end
_G.GetVehicleClass = function() return 0 end
_G.DoesEntityExist = function() return true end
_G.SetVehicleEngineTorqueMultiplier = function() end
_G.GetCurrentResourceName = function() return 'kora_mechanic' end
_G.AddEventHandler = function(name, fn) events[name] = fn end
_G.Kora = { cache = { onChange = function(key, fn) listeners[key] = listeners[key] or {}; table.insert(listeners[key], fn) end } }

dofile(repoRoot .. 'client/damage.lua')

local function alive()
    local n = 0
    for _, co in ipairs(threads) do if coroutine.status(co) ~= 'dead' then n = n + 1 end end
    return n
end
local function step() for _, co in ipairs(threads) do if coroutine.status(co) == 'suspended' then assert(coroutine.resume(co)) end end end
local function fire(key) for _, fn in ipairs(listeners[key] or {}) do fn() end end

h.test('no worker runs while on foot', function()
    h.assertEqual(#threads, 0)
    h.assertTrue(listeners.seat ~= nil and listeners.vehicle ~= nil, 'listeners registered')
end)

h.test('worker starts when driving and exits on leaving', function()
    vehicle, driver = 10, PED
    fire('seat'); fire('vehicle')
    step()
    h.assertEqual(alive(), 1)
    vehicle, driver = 0, 0
    step()
    h.assertEqual(alive(), 0)
end)

h.test('kora_lib restart re-registers and seeds without duplicating workers', function()
    vehicle, driver = 10, PED
    events.onClientResourceStart('kora_lib')
    fire('seat'); fire('vehicle')
    step()
    h.assertEqual(alive(), 1)
    vehicle, driver = 0, 0
    step()
end)

h.report('mechanic damage')
