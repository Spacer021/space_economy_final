fx_version 'cerulean'
game 'gta5'

author 'Space Store'
description 'Pagamento de Taxas - Space Economy'
version '1.2.0'

lua54 'yes'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_scripts {
    '@ox_lib/init.lua', 
    'config.lua'
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua'
}

-- CORRIGIDO: Adicionadas dependências cruciais
dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ps-banking'
}