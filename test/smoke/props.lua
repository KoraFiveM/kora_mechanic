local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path
local h = require('harness')

local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function v3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end

local function encode(value)
    if type(value) ~= 'table' then return tostring(value) end
    local parts = {}
    for k, item in pairs(value) do parts[#parts + 1] = tostring(k) .. '=' .. encode(item) end
    table.sort(parts)
    return '{' .. table.concat(parts, ',') .. '}'
end
_G.json = { encode = encode }

local handlers, saved = {}, {}
local now, job = 100000, { name = 'mechanic', type = 'automotive', onduty = true }
local rows = {
    ['ABC123'] = { plate = 'ABC123', citizenid = 'OWNER', mods = { modSpoilers = 2 } },
    ['FLEET1'] = { plate = 'FLEET1', job = 'police', mods = {} },
}
local citizen = 'OWNER'
local playerPos = v3(0, 0, 0)
local vehicles = { [10] = { plate = ' abc123 ', pos = v3(2, 0, 0) }, [11] = { plate = 'FLEET1', pos = v3(500, 0, 0) } }

_G.GetGameTimer = function() return now end
_G.GetPlayerPed = function() return 1 end
_G.GetEntityCoords = function(e) return e == 1 and playerPos or vehicles[e].pos end
_G.GetAllVehicles = function() return { 10, 11 } end
_G.GetVehicleNumberPlateText = function(e) return vehicles[e].plate end
_G.GetVehicleEngineHealth = function() return 640.5 end
_G.GetVehicleBodyHealth = function() return 5000 end
_G.RegisterNetEvent = function(name, fn) handlers[name] = fn end
_G.AddEventHandler = function() end
_G.source = 7
_G.Config = {
    roles = { requireOnDuty = true, fullRepairJob = 'mechanic', automotiveType = 'automotive', roadsideJobs = { roadside = true } },
    propsSave = { distance = 8.0, maxBytes = 16384, cooldown = 2000 },
}
_G.exports = { kora_core = {
    getJob = function() return job end,
    getPlayerData = function() return citizen end,
    getByPlate = function(_, plate) return rows[plate] end,
    saveVehicleProperties = function(_, plate, props) saved[#saved + 1] = { plate = plate, props = props } return true end,
} }

dofile(repoRoot .. 'server/props.lua')
local save = handlers['qb-mechanicjob:server:SaveVehicleProps']

local function call(props, offset)
    now = now + 5000 + (offset or 0)
    save(props)
    return saved[#saved]
end
local function reset() for i = #saved, 1, -1 do saved[i] = nil end end

h.test('owner saves wear fields only; tuning is dropped and stored mods are kept', function()
    job = { name = 'unemployed', type = 'none', onduty = false }
    local out = call({ plate = 'ABC123', dirtLevel = 7, doorStatus = { ['0'] = true }, modSpoilers = 9, color1 = 3, fakeField = 1 })
    h.assertTrue(out ~= nil, 'saved')
    h.assertEqual(out.props.dirtLevel, 7)
    h.assertEqual(out.props.modSpoilers, 2)
    h.assertEqual(out.props.color1, nil)
    h.assertEqual(out.props.fakeField, nil)
    h.assertEqual(out.props.engineHealth, 640.5)
    h.assertEqual(out.props.bodyHealth, 1000)
end)

h.test('non-owner without a mechanic job is refused', function()
    reset(); citizen = 'STRANGER'
    h.assertEqual(call({ plate = 'ABC123', dirtLevel = 1 }), nil)
    citizen = 'OWNER'
end)

h.test('on-duty mechanic may save tuning; off-duty and roadside may not', function()
    reset(); citizen = 'STRANGER'
    job = { name = 'mechanic', type = 'automotive', onduty = true }
    local out = call({ plate = 'ABC123', modSpoilers = 5, color1 = { r = 1, g = 2, b = 3 }, modEngine = 3 })
    h.assertEqual(out.props.modSpoilers, 5); h.assertEqual(out.props.color1.g, 2); h.assertEqual(out.props.modEngine, 3)
    reset(); job.onduty = false
    h.assertEqual(call({ plate = 'ABC123', modSpoilers = 5 }), nil)
    job = { name = 'roadside', type = 'automotive', onduty = true }
    h.assertEqual(call({ plate = 'ABC123', modSpoilers = 5 }), nil)
    citizen = 'OWNER'
end)

h.test('vehicle must be near the caller', function()
    reset(); job = { name = 'mechanic', type = 'automotive', onduty = true }
    h.assertEqual(call({ plate = 'FLEET1', modSpoilers = 1 }), nil)
    vehicles[11].pos = v3(3, 0, 0)
    h.assertTrue(call({ plate = 'FLEET1', modSpoilers = 1 }) ~= nil)
    vehicles[11].pos = v3(500, 0, 0)
end)

h.test('invalid, oversized and unknown payloads are refused', function()
    reset(); job = { name = 'mechanic', type = 'automotive', onduty = true }
    h.assertEqual(call({ plate = 'ABC123', modSpoilers = 9999 }), nil)
    h.assertEqual(call({ plate = 'ABC123', neonEnabled = { true, false } }), nil)
    h.assertEqual(call({ plate = 'ABC123', color1 = { r = 300, g = 0, b = 0 } }), nil)
    h.assertEqual(call({ plate = 'ABC123', extras = { ['99'] = true } }), nil)
    h.assertEqual(call({ plate = 'ABC123', fakeField = 1 }), nil)
    h.assertEqual(call({ plate = ('X'):rep(40), modSpoilers = 1 }), nil)
    h.assertEqual(call({ plate = 'NOPE00', modSpoilers = 1 }), nil)
    h.assertEqual(call({ modSpoilers = 1 }), nil)
    h.assertEqual(call('x'), nil)
    h.assertEqual(#saved, 0)
end)

h.test('saves are rate limited per player', function()
    reset(); job = { name = 'mechanic', type = 'automotive', onduty = true }
    call({ plate = 'ABC123', modSpoilers = 1 })
    save({ plate = 'ABC123', modSpoilers = 2 })
    h.assertEqual(#saved, 1)
end)

h.report('mechanic props')
