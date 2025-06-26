local oxmysql = exports.oxmysql

local vaultBalance = 0.0
local inflationRate = 1.0
local dailyWashedByBusiness = {} -- Tabela para rastrear o limite diário de lavagem

--[[
    Função central de logging para a economia.
]]
function Log(category, message)
    if not Config.Logging.Enabled then return end
    local logCategoryEnabled = "Log" .. category:sub(1,1):upper() .. category:sub(2):lower() .. "s"
    if category == 'INFLATION' then logCategoryEnabled = "LogInflation"
    elseif category == 'PLAYER' then logCategoryEnabled = "LogPlayerActions" end
    if not Config.Logging[logCategoryEnabled] then return end

    local timestamp = os.date('%d/%m/%Y %H:%M:%S')

    if Config.Logging.LogToDatabase then
        oxmysql:execute('INSERT INTO space_economy_logs (category, message) VALUES (?, ?)', { category, message })
    end
    if Config.Logging.LogToFile then
        local logLine = string.format("[%s] [%s] %s\n", timestamp, string.upper(category), message)
        SaveResourceFile(GetCurrentResourceName(), 'logs/economy_logs.txt', logLine, -1)
    end
    if Config.Logging.LogToWebhook and Config.Logging.WebhookURL and Config.Logging.WebhookURL:sub(1, 4) == "http" then
        local embedColor = 15844367
        local categoryColors = {
            ['ADMIN'] = 15105570, ['TREASURY'] = 3066993, ['DEBT'] = 15158332,
            ['TAX'] = 3447003, ['INFLATION'] = 9807270, ['PLAYER'] = 5814783,
        }
        embedColor = categoryColors[string.upper(category)] or embedColor
        local payload = {
            username = "Logs da Economia", avatar_url = "https://i.imgur.com/g4J5v2u.png",
            embeds = {{
                title = "Categoria: " .. string.upper(category),
                description = "```\n" .. message .. "\n```", color = embedColor,
                footer = { text = "Log gerado em " .. timestamp }
            }}
        }
        PerformHttpRequest(Config.Logging.WebhookURL, function(err, text, headers) end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
    end
    print(('[space_economy] [%s] %s'):format(string.upper(category), message))
end

-- Salva o estado atual do cofre e da inflação no banco de dados.
local function UpdateDatabase()
    oxmysql:execute('UPDATE space_economy SET vault = ?, inflation = ? WHERE id = 1', { vaultBalance, inflationRate })
end

-- Altera o saldo do cofre e aplica penalidade de inflação se aplicável.
local function ModifyVaultBalance(changeAmount, reason)
    if not changeAmount then return end
    local originalBalance = vaultBalance
    vaultBalance = vaultBalance + changeAmount
    if Config.Inflation.AdminInjectionPenalty and changeAmount > 0 and originalBalance > 0 then
        local inflationPenalty = (changeAmount / originalBalance) * Config.Inflation.InjectionMultiplier
        inflationRate = inflationRate + inflationPenalty
        Log('INFLATION', string.format("Dinheiro 'impresso' por admin! A taxa de inflação aumentou em %.4f por causa da injeção de $%s.", inflationPenalty, changeAmount))
    end
    Log('TREASURY', reason .. string.format("\nValor: $%.2f\nSaldo Anterior: $%.2f\nNovo Saldo: $%.2f", changeAmount, originalBalance, vaultBalance))
    UpdateDatabase()
end

-- Salva uma dívida para um jogador no banco de dados.
local function SaveDebt(identifier, amount, reason)
    Log('DEBT', string.format("Dívida de $%.2f registrada para o CitizenID %s.\nMotivo: %s", amount, identifier, reason))
    oxmysql:execute('INSERT INTO space_economy_debts (citizenid, amount, reason) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount), reason = VALUES(reason)', {
        identifier, amount, reason
    })
end

-- Export para calcular um imposto e notificar o jogador.
function CalculateTax(identifier, amount, reason)
    local tax = Config.CalculateProgressiveTax(amount)
    local player = exports.qbx_core:GetPlayerByCitizenId(identifier)
    if player then
        TriggerClientEvent('space_economy:openTaxPanel', player.PlayerData.source, amount, tax, reason)
    else
        SaveDebt(identifier, tax, reason or "Taxa offline")
    end
    return amount + tax, tax
end
exports('CalculateTax', CalculateTax)

-- =================================================================
-- EVENTOS DO SERVIDOR
-- =================================================================
RegisterNetEvent('space_economy:payOnlyTax', function(identifier, taxAmount, reason)
    local player = exports.qbx_core:GetPlayerByCitizenId(identifier)
    if not player then return end
    if player.Functions.RemoveMoney('bank', taxAmount, reason or 'Pagamento taxa') then
        ModifyVaultBalance(taxAmount, "Pagamento de taxa única recebido de " .. player.PlayerData.charinfo.firstname .. " (" .. identifier .. ").")
        TriggerClientEvent('space_economy:paymentResult', player.PlayerData.source, true, taxAmount)
    else
        SaveDebt(identifier, taxAmount, reason or 'Falha no pagamento da taxa')
        TriggerClientEvent('space_economy:paymentResult', player.PlayerData.source, false, taxAmount)
    end
end)

RegisterNetEvent('space_economy:taxPaymentResponse', function(paid, identifier, taxAmount, reason)
    local player = exports.qbx_core:GetPlayerByCitizenId(identifier)
    if not player then return end
    if paid then
        if player.Functions.RemoveMoney('bank', taxAmount, 'Pagamento taxa') then
            ModifyVaultBalance(taxAmount, "Pagamento de taxa de transação recebido de " .. player.PlayerData.charinfo.firstname .. " (" .. identifier .. ").")
            TriggerClientEvent('ox_lib:notify', player.PlayerData.source, { title = 'Taxa Paga', description = ('Você pagou $%s de taxa.'):format(taxAmount), type = 'success' })
        else
            SaveDebt(identifier, taxAmount, reason or 'Sem saldo para taxa')
            TriggerClientEvent('ox_lib:notify', player.PlayerData.source, { title = 'Taxa não paga', description = 'Saldo insuficiente. Dívida registrada.', type = 'error' })
        end
    else
        SaveDebt(identifier, taxAmount, reason or 'Recusa em pagar taxa')
        TriggerClientEvent('ox_lib:notify', player.PlayerData.source, { title = 'Dívida registrada', description = 'Você recusou pagar a taxa. Dívida registrada.', type = 'warning' })
    end
    TriggerClientEvent('space_economy:closeTaxMenu', player.PlayerData.source)
end)

RegisterNetEvent('space_economy:server_addCofre', function(amount)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not hasPermission(Player) then return end
    if not amount or amount <= 0 then return notify(src, 'Operação Falhou', 'Valor inválido.', 'error') end
    
    local reason = string.format("Admin %s (%s) adicionou fundos ao cofre.", Player.PlayerData.charinfo.firstname, Player.PlayerData.citizenid)
    ModifyVaultBalance(amount, reason)
    
    notify(src, 'Cofre Atualizado', ('Você adicionou $%s ao cofre. Novo saldo: $%s'):format(amount, vaultBalance), 'success')
end)

RegisterNetEvent('space_economy:server_sacarCofre', function(amount)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not hasPermission(Player) then return end
    if not amount or amount <= 0 then return notify(src, 'Operação Falhou', 'Valor inválido.', 'error') end
    if amount > vaultBalance then return notify(src, 'Operação Falhou', 'Saldo insuficiente no cofre.', 'error') end
    
    local reason = string.format("Admin %s (%s) sacou fundos do cofre.", Player.PlayerData.charinfo.firstname, Player.PlayerData.citizenid)
    ModifyVaultBalance(-amount, reason)
    Player.Functions.AddMoney('cash', amount, 'sacar-cofre-gov')
    
    notify(src, 'Saque Realizado', ('Você sacou $%s do cofre. Novo saldo: $%s'):format(amount, vaultBalance), 'success')
end)

RegisterNetEvent('space_economy:server_debtPaymentResponse', function(didPay)
    local source = source
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    
    exports.oxmysql:fetch('SELECT amount FROM space_economy_debts WHERE citizenid = ?', { citizenid }, function(result)
        if not result or #result == 0 then return end
        local debtAmount = result[1].amount
        if didPay then
            if Player.Functions.RemoveMoney('bank', debtAmount, 'pagamento_divida_gov') then
                exports.oxmysql:execute('DELETE FROM space_economy_debts WHERE citizenid = ?', { citizenid })
                local reason = string.format("Dívida de %s (%s) paga.", Player.PlayerData.charinfo.firstname, citizenid)
                ModifyVaultBalance(debtAmount, reason)
                notify(source, 'Dívida Paga', 'Sua dívida com o governo foi quitada.', 'success')
            else
                notify(source, 'Pagamento Falhou', 'Você não tem saldo. Um mandado de prisão foi emitido.', 'error')
                issueWarrant(Player, citizenid, debtAmount)
                Log('DEBT', string.format("Jogador %s (%s) tentou pagar dívida de $%.2f mas não tinha saldo.", Player.PlayerData.charinfo.firstname, citizenid, debtAmount))
            end
        else
            notify(source, 'Dívida Recusada', 'Você se recusou a pagar. Um mandado de prisão foi emitido.', 'error')
            issueWarrant(Player, citizenid, debtAmount)
            Log('DEBT', string.format("Jogador %s (%s) recusou-se a pagar dívida de $%.2f.", Player.PlayerData.charinfo.firstname, citizenid, debtAmount))
        end
    end)
end)

RegisterNetEvent('space_economy:requestOpenAdminPanel', function()
    local source = source
    local Player = exports.qbx_core:GetPlayer(source)
    if hasPermission(Player) then
        TriggerClientEvent('space_economy:openAdminDashboard', source)
    else
        notify(source, 'Acesso Negado', 'Você não tem permissão para usar este painel.', 'error')
    end
end)

RegisterNetEvent('space_economy:server_requestAdminData', function(dataType, payload)
    local source = source
    if not hasPermission(exports.qbx_core:GetPlayer(source)) then return end

    if dataType == 'vault' then
        TriggerClientEvent('space_economy:openVaultPanel', source, vaultBalance)
    elseif dataType == 'addVault' then
        TriggerClientEvent('space_economy:openAddVaultPanel', source)
    elseif dataType == 'withdrawVault' then
        TriggerClientEvent('space_economy:openWithdrawVaultPanel', source)
    elseif dataType == 'debts' or dataType == 'specific_debt' or dataType == 'collect_debt' then
        local targetCitizenId = payload
        local query, params
        if dataType == 'debts' then
            query = 'SELECT d.citizenid, d.amount, d.reason, p.charinfo FROM space_economy_debts d LEFT JOIN players p ON d.citizenid = p.citizenid ORDER BY d.amount DESC LIMIT 20'
            params = {}
        else
            query = 'SELECT d.citizenid, d.amount, d.reason, p.charinfo FROM space_economy_debts d LEFT JOIN players p ON d.citizenid = p.citizenid WHERE d.citizenid = ?'
            params = { targetCitizenId }
        end
        
        exports.oxmysql:fetch(query, params, function(result)
            if not result or #result == 0 then
                return notify(source, 'Consulta', 'Nenhuma dívida encontrada para os critérios.', 'inform')
            end
            if dataType == 'collect_debt' then
                local targetPlayer = exports.qbx_core:GetPlayerByCitizenId(targetCitizenId)
                if not targetPlayer then return notify(source, 'Cobrança Falhou', 'Jogador não está online.', 'error') end
                TriggerClientEvent('space_economy:promptDebtPayment', targetPlayer.PlayerData.source, result[1].amount)
                notify(source, 'Cobrança Enviada', ('Aviso de cobrança de $%s enviado.'):format(result[1].amount), 'inform')
            else
                for i, debt in ipairs(result) do
                    local playerName = "Não Encontrado"
                    if debt.charinfo then
                        local charInfoTable = json.decode(debt.charinfo)
                        if charInfoTable and charInfoTable.firstname and charInfoTable.lastname then
                            playerName = charInfoTable.firstname .. " " .. charInfoTable.lastname
                        end
                    end
                    result[i].playerName = playerName; result[i].charinfo = nil
                end
                
                if dataType == 'debts' then
                    TriggerClientEvent('space_economy:openDebtListPanel', source, result)
                else
                    TriggerClientEvent('space_economy:openDebtDetails', source, result[1])
                end
            end
        end)
    end
end)

-- =================================================================
-- LÓGICA DE LAVAGEM DE DINHEIRO (VERSÃO FINAL COM PS-BANKING)
-- =================================================================
RegisterNetEvent('space_economy:server_washMoney', function(business_id, amount, fee_percent)
    local source = source
    local Player = exports.qbx_core:GetPlayer(source)
    local front = Config.LaunderingFronts[business_id]

    if not Player or not front then return end

    if Player.PlayerData.job.name ~= front.job_name or Player.PlayerData.job.grade.level < front.min_grade then
        return notify(source, "Erro", "Você não tem permissão para usar esta função.", "error")
    end
    if fee_percent < front.min_fee_percent or fee_percent > front.max_fee_percent then
        return notify(source, "Erro", string.format("A taxa deve ser entre %.1f%% e %.1f%%.", front.min_fee_percent, front.max_fee_percent), "error")
    end
    dailyWashedByBusiness[business_id] = dailyWashedByBusiness[business_id] or 0
    if (dailyWashedByBusiness[business_id] + amount) > front.max_daily_wash then
        return notify(source, "Limite Atingido", "Seu negócio já atingiu o limite de lavagem por hoje.", "error")
    end
    local dirtyMoney = Player.Functions.GetItemByName(Config.DirtyMoneyItem)
    if not dirtyMoney or dirtyMoney.amount < amount then
        return notify(source, "Erro", "Você não possui essa quantidade de dinheiro sujo.", "error")
    end

    Player.Functions.RemoveItem(Config.DirtyMoneyItem, amount)

    local fee_value = math.floor(amount * (fee_percent / 100))
    local clean_amount = amount - fee_value
    
    Player.Functions.AddMoney('bank', clean_amount, 'servico_lavagem_pessoal')
    
    -- CORRIGIDO: Usa o export do ps-banking para depositar a taxa na conta da empresa
    exports['ps-banking']:AddSocietyMoney(front.job_name, fee_value)

    dailyWashedByBusiness[business_id] = dailyWashedByBusiness[business_id] + amount

    notify(source, "Sucesso", string.format("Você lavou $%s. Recebeu $%s limpos em sua conta e a empresa lucrou $%s de taxa.", amount, clean_amount, fee_value), "success")
    Log('PLAYER', string.format(
        "LAVAGEM: Jogador %s (%s) lavou $%s de '%s' através do negócio '%s'.\n- Valor Limpo (Pessoal): $%s\n- Taxa (Empresa): $%s",
        Player.PlayerData.charinfo.firstname, Player.PlayerData.citizenid, amount, Config.DirtyMoneyItem, business_id, clean_amount, fee_value
    ))
end)

-- =================================================================
-- FUNÇÕES DE AJUDA E COMANDOS
-- =================================================================
function hasPermission(player)
    if not player or not player.PlayerData then return false end
    local staffGroup = player.PlayerData.metadata and player.PlayerData.metadata.staff
    if staffGroup and type(staffGroup) == 'string' then
        local ace = staffGroup:gsub("group.", "")
        if Config.Permissions[ace] then return true end
    end
    local jobName = player.PlayerData.job and player.PlayerData.job.name and string.lower(player.PlayerData.job.name)
    local jobGrade = player.PlayerData.job and player.PlayerData.job.grade and player.PlayerData.job.grade.level
    if jobName and jobGrade ~= nil and Config.Permissions[jobName] and jobGrade >= Config.Permissions[jobName].min_grade then
        return true
    end
    return false
end

function issueWarrant(player, citizenid, debtAmount)
    local playerName = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname
    local playerPed = GetPlayerPed(player.PlayerData.source)
    local coords = GetEntityCoords(playerPed)
    local dispatchData = { message = ('Mandado de Captura para %s por dívida de $%s.'):format(playerName, debtAmount), codeName = 'GOV_DEBT_WARRANT', code = '10-99', icon = 'fas fa-gavel', priority = 1, coords = coords, jobs = { Config.WarrantAlert.police_job_name } }
    TriggerEvent('ps-dispatch:server:notify', dispatchData)
    local incidentTitle = "Evasão de Dívida Governamental"
    local incidentDetails = ('O indivíduo foi notificado sobre uma dívida de $%s e recusou o pagamento, resultando neste mandado. O valor da dívida deve ser adicionado à sentença como multa.'):format(debtAmount)
    local incidentTime = os.time()
    local associatedData = {{ Cid = citizenid, Warrant = true, Guilty = true, Processed = false, Isassociated = true, Charges = { "Evasão de Dívida Governamental" }, Fine = debtAmount, Sentence = Config.WarrantCharge.jail_time, recfine = debtAmount, recsentence = Config.WarrantCharge.jail_time, Time = incidentTime }}
    TriggerEvent('mdt:server:saveIncident', 0, incidentTitle, incidentDetails, {"dívida"}, {{ name = "Sistema Central de Dívidas", cid = "GOV001" }}, {{ name = playerName, cid = citizenid }}, {}, associatedData, incidentTime)
    local description = (Config.WarrantAlert.description):format(playerName, citizenid, debtAmount)
    TriggerClientEvent('space_economy:issueWarrantAlert', -1, Config.WarrantAlert.title, description)
end

function notify(source, title, description, type)
    TriggerClientEvent('ox_lib:notify', source, { title = title, description = description, type = type or 'inform' })
end

-- Comandos de chat para administradores (Comandos de cofre foram removidos)
RegisterCommand('vercofre', function(source)
    if hasPermission(exports.qbx_core:GetPlayer(source)) then
        notify(source, 'Saldo do Cofre', ('O saldo atual do cofre central é de $%s.'):format(vaultBalance), 'inform')
    else
        notify(source, 'Permissão Negada', 'Você não tem autorização.', 'error')
    end
end, false)
RegisterCommand('verdividas', function(source, args) if hasPermission(exports.qbx_core:GetPlayer(source)) then TriggerEvent('space_economy:server_requestAdminData', 'debts', args[1]) else notify(source, 'Permissão Negada', 'Você não tem autorização.', 'error') end end, false)
RegisterCommand('verdivida', function(source, args) if hasPermission(exports.qbx_core:GetPlayer(source)) and args[1] then TriggerEvent('space_economy:server_requestAdminData', 'specific_debt', args[1]) else notify(source, 'Argumento Inválido', 'Uso: /verdivida [citizenid]', 'error') end end, false)
RegisterCommand('cobrardivida', function(source, args) if hasPermission(exports.qbx_core:GetPlayer(source)) and args[1] then TriggerEvent('space_economy:server_requestAdminData', 'collect_debt', args[1]) else notify(source, 'Argumento Inválido', 'Uso: /cobrardivida [citizenid]', 'error') end end, false)

-- =================================================================
-- THREADS E OUVINTES GLOBAIS
-- =================================================================
CreateThread(function() -- Thread de Inflação
    if not Config.Inflation.Enabled then return end
    while true do
        Wait(Config.Inflation.UpdateInterval * 60 * 1000)
        local newRate = math.random(Config.Inflation.MinRate * 100, Config.Inflation.MaxRate * 100) / 100
        inflationRate = newRate
        local message = ('A taxa de inflação da cidade foi atualizada para %.2f.'):format(inflationRate)
        Log('INFLATION', message)
        notify(-1, 'Economia da Cidade', message, 'inform')
        TriggerClientEvent('space_economy:client_updateInflation', -1, inflationRate)
        UpdateDatabase()
    end
end)

CreateThread(function() -- Thread de Inicialização
    Wait(1000)
    local result = oxmysql:executeSync('SELECT * FROM space_economy WHERE id = 1')
    if result and result[1] then
        vaultBalance = result[1].vault
        inflationRate = result[1].inflation
        Log("SYSTEM", "Script de Economia iniciado. Cofre e Inflação carregados.")
    else
        Log("SYSTEM", "Nenhuma configuração encontrada. Criando nova entrada no banco.")
        oxmysql:execute('INSERT INTO space_economy (id, vault, inflation) VALUES (1, 0, 1.0)')
    end
end)

CreateThread(function() -- Thread de Limpeza de Logs
    if not Config.Logging.LogToDatabase or not Config.Logging.LogPruning.Enabled then return end
    while true do
        Wait(24 * 60 * 60 * 1000)
        local days = Config.Logging.LogPruning.PruneOlderThanDays
        Log('SYSTEM', string.format("Iniciando limpeza automática de logs mais antigos que %d dias.", days))
        oxmysql:execute('DELETE FROM `space_economy_logs` WHERE `timestamp` < (NOW() - INTERVAL ? DAY)', { days }, function(affectedRows)
            if affectedRows > 0 then
                Log('SYSTEM', string.format("Limpeza concluída. %d registros apagados.", affectedRows))
            else
                Log('SYSTEM', "Nenhum log antigo para apagar.")
            end
        end)
    end
end)

RegisterNetEvent('QBCore:Server:OnMoneyChange', function(source, moneyType, amount, operation, reason) -- Ouvinte Global
    if not Config.Logging.Enabled or not Config.Logging.LogGlobalMoneyChanges then return end
    if reason and Config.Logging.IgnoredReasons[reason] then return end
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return end
    local actionText = operation == 'add' and "RECEBEU" or "PERDEU"
    local playerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    local citizenid = Player.PlayerData.citizenid
    local moneyTypeText = moneyType == 'bank' and "no banco" or (moneyType == 'cash' and "em espécie" or "em crypto")
    local reasonText = reason or "MOTIVO NÃO ESPECIFICADO"
    local message = string.format("Jogador: %s (%s) %s $%s %s.\nMotivo: %s", playerName, citizenid, actionText, amount, moneyTypeText, reasonText)
    Log('PLAYER', message)
end)

CreateThread(function() -- Thread de Reset do Limite de Lavagem
    while true do
        Wait(12 * 60 * 60 * 1000) -- Zera a cada 12 horas
        dailyWashedByBusiness = {}
        Log("SYSTEM", "Limites diários de lavagem de dinheiro foram zerados.")
    end
end)

-- Adicionar no final do server/sv_main.lua

RegisterNetEvent('space_economy:server:getTaxCalculation', function(amount)
    local source = source
    if not amount or amount <= 0 then return end
    
    -- Reutiliza a função de cálculo que já existe na sua config.
    local tax = Config.CalculateProgressiveTax(amount)
    local total = amount + tax

    -- Envia os dados de volta para o cliente que pediu.
    TriggerClientEvent('space_economy:client:showTaxCalculation', source, amount, tax, total)
end)

-- Adicionar NO FINAL do server/main.lua

-- Escuta o evento oficial do ox_inventory quando um item é usado
RegisterNetEvent('ox_inventory:useItem', function(source, item)
    -- Verifica se o nome do item é a nossa calculadora
    if item.name == 'tax_calculator' then
        -- Se for, manda o cliente específico que usou o item abrir o painel da calculadora
        TriggerClientEvent('space_economy:client:openCalculator', source)
    end
end)