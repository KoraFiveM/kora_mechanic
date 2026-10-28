fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'kora_mechanic'
-- Keep the legacy resource name resolvable for exports['qbmechanic'] callers.
provide 'qbmechanic'
author 'qbcore2'
version '1.0.0'
description 'Job-gated vehicle repairs, roadside assistance, bodyshop cosmetics, and configurable vehicle wear.'

dependencies {
    'kora_lib',
    'kora_core',
    'kora_target'
}

shared_script '@kora_lib/init.lua'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/actions.lua',
    'client/damage.lua'
}

server_scripts {
    'server/actions.lua'
}
