# kora_mechanic

Vehicle service and damage gameplay for this kora_lib server.

* `mechanic`, and any on-duty `automotive` job, can repair vehicles. The named
  `roadside` job is automotive but is deliberately limited to stabilisation:
  it restores only minimum engine/body condition and one burst tyre.
* Full repairs are mechanic/automotive-only and must be carried out in a
  configured garage bay. Bodyshop roles cannot repair.
* `bodyshop` (or a `bodyshop` job type) can respray vehicles and change front
  and rear bumper variations, but sees no repair options. These options only
  appear on-duty and, while `Config.interaction.requireShopZone` is true
  (default), only for vehicles inside a configured garage bay.
* Damage adds collision wear, low-health limp mode/stalls and configurable
  random tyre bursts. Optional distance wear is disabled by default so normal,
  collision-free driving does not reduce vehicle health. All tuning is in
  `config.lua`.

Every action is authorised by the server before the animation starts and again
when it ends. The server validates duty, role, networked vehicle, range, garage
location and any configured consumable before asking the client that controls
the vehicle to apply the native change.

## qb-mechanicjob compatibility

The resource provides `qb-mechanicjob`. The server event `qb-mechanicjob:server:SaveVehicleProps(props)` (sent by stock qb-garages on deposit) is accepted when the caller is within `Config.propsSave.distance` of a vehicle carrying `props.plate` and either owns that plate or is an on-duty non-roadside automotive worker. Differences from stock:

* Properties are whitelisted and bounded (`Config.propsSave.maxBytes`); unknown keys are dropped and any invalid known value rejects the save.
* Owners persist wear state only (dirt, oil, doors, windows, tyres); tuning fields (`mod*`, colours, neon, extras and so on) are saved only for mechanics, so a forged snapshot cannot give free customisation. Stored tuning is merged, not replaced.
* Engine and body health come from the server's vehicle entity, not the payload.
* Saves are rate limited per player and go through `kora_core:saveVehicleProperties`.

Repair-kit item handlers are not provided.
