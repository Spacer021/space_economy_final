-- Inicia a tabela principal de configuração. Todas as configurações do script
-- serão armazenadas dentro desta tabela 'Config'.
Config = {}

-- Define as faixas de imposto para o sistema de taxação progressiva.
Config.TaxBrackets = {
    { limit = 1000, rate = 0.01 },
    { limit = 5000, rate = 0.03 },
    { limit = 10000, rate = 0.05 },
    { limit = nil, rate = 0.08 },
}

-- Define as permissões para usar os comandos administrativos do script.
Config.Permissions = {
    ['admin']    = { min_grade = 0 },
    ['police']   = { min_grade = 2 },
    ['governor'] = { min_grade = 0 },
}

-- Em config.lua, dentro da tabela Config.Inflation
Config.Inflation = {
    Enabled = true,
    UpdateInterval = 15,
    MinRate = 0.8,
    MaxRate = 1.2,
    AdminInjectionPenalty = true,
    InjectionMultiplier = 0.5,
}

-- =================================================================
-- SEÇÃO DE LOGS COMPLETA (HÍBRIDA + LIMPEZA)
-- =================================================================
Config.Logging = {
    Enabled = true,
    LogToFile = true,
    LogToWebhook = true,
    LogToDatabase = true,
    WebhookURL = "https://discord.com/api/webhooks/1387497427803574376/gRPHsMRhUvbxm4QWxD-7hqbdFCcYv9rOtLyPqtaHjpFY-wUDT7NSOPp2T9vzqY6fA_CG",
    LogGlobalMoneyChanges = true,
    IgnoredReasons = {
        ['salary'] = true,
        ['pagamento_salario'] = true,
    },
    LogAdminActions = true,
    LogTreasuryChanges = true,
    LogTaxCollection = true,
    LogDebtActions = true,
    LogInflation = true,
    LogPlayerActions = true,
    LogPruning = {
        Enabled = true,
        PruneOlderThanDays = 30
    }
}

-- Função que calcula o valor do imposto progressivo.
Config.CalculateProgressiveTax = function(amount)
    local tax = 0
    local remaining = amount
    for _, bracket in ipairs(Config.TaxBrackets) do
        if bracket.limit == nil or remaining <= bracket.limit then
            tax = tax + (remaining * bracket.rate)
            break
        else
            tax = tax + (bracket.limit * bracket.rate)
            remaining = remaining - bracket.limit
        end
    end
    return math.floor(tax)
end

-- =================================================================
-- SISTEMA MODULAR PARA FRENTES DE LAVAGEM (VERSÃO FINAL)
-- =================================================================
Config.LaunderingFronts = {
    -- Você pode adicionar quantos negócios quiser aqui.
    -- Basta copiar e colar o bloco de um negócio e alterar os valores.
    ['policia'] = {
        job_name = 'police', -- Nome exato do emprego que pode lavar aqui
        min_grade = 2,         -- Nível mínimo do cargo para realizar a lavagem
        location = vector3(-211.8, -1323.5, 30.9),
        label = "Escritório da Benny's",
        
        -- CORRIGIDO: Limites para a taxa de lavagem que o dono define no painel.
        min_fee_percent = 10.0, -- Mínimo de 10% que você pediu.
        max_fee_percent = 40.0, -- Teto máximo para evitar abusos.
        
        max_daily_wash = 100000, -- Limite MÁXIMO que este negócio pode lavar por dia.
    },

    ['burgershot'] = {
        job_name = 'burgershot',
        min_grade = 3,
        location = vector3(-1188.7, -889.2, 13.8),
        label = "Cozinha dos Fundos",

        min_fee_percent = 15.0, -- Você pode ter taxas diferentes por negócio.
        max_fee_percent = 50.0,

        max_daily_wash = 50000,
    },
}

-- O nome exato do item de dinheiro sujo no seu inventário.
Config.DirtyMoneyItem = 'black_money'

-- Configurações para o alerta de mandado policial.
Config.WarrantAlert = {
    title = "ALERTA DE MANDADO",
    description = "Mandado de prisão e apreensão de bens emitido para %s (ID: %s) por dívida governamental não paga no valor de $%s. Todas as unidades, procedam com a captura.",
    police_job_name = 'leo'
}

-- Configurações para a acusação no MDT.
Config.WarrantCharge = {
    charge_code = "evasion_of_debt",
    jail_time = 30,
}

-- Configurações para o painel físico de admin.
Config.AdminPanel = {
    Location = vector3(-531.82, -217.16, 37.65),
    Blip = {
        sprite = 478,
        color = 2,
        scale = 0.8,
        text = "Painel de Controle Econômico"
    },
    InteractionDistance = 2.0
}