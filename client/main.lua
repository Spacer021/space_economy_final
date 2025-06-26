local amountToPay, taxAmount, reasonData
local citizenid = nil
local currentInflation = 1.0

-- Função para fechar a interface NUI e devolver o foco ao jogador.
local function closeNUI()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- Thread para obter o citizenid do jogador assim que ele estiver disponível.
CreateThread(function()
    while not citizenid do
        Wait(500)
        local player = exports.qbx_core:GetPlayerData()
        if player and player.citizenid then
            citizenid = player.citizenid
        end
    end
end)

-- Evento que recebe a taxa de inflação do servidor e armazena localmente.
RegisterNetEvent('space_economy:client_updateInflation', function(rate)
    currentInflation = rate
end)

-- Abre o painel para o jogador decidir sobre o pagamento de uma taxa.
RegisterNetEvent('space_economy:openTaxPanel', function(amount, tax, reason)
    amountToPay = amount
    taxAmount = tax
    reasonData = reason
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        tax = tax,
        reason = reason or 'Sem motivo informado'
    })
end)

-- Processa o resultado de um pagamento de taxa vindo do servidor.
RegisterNetEvent('space_economy:paymentResult', function(success, paidAmount)
    if success then
        SendNUIMessage({
            action = 'paymentSuccess',
            tax = paidAmount
        })
    else
        closeNUI()
        exports.ox_lib:notify({
            title = 'Falha no Pagamento',
            description = 'Você não tem saldo suficiente para pagar a taxa.',
            type = 'error'
        })
    end
end)

-- Callbacks da NUI para o jogador
RegisterNUICallback('payTax', function(data, cb)
    if not citizenid then cb('erro'); return end
    TriggerServerEvent('space_economy:payOnlyTax', citizenid, taxAmount, reasonData)
    cb('ok')
end)

RegisterNUICallback('refuseTax', function(data, cb)
    if not citizenid then cb('erro'); return end
    TriggerServerEvent('space_economy:taxPaymentResponse', false, citizenid, taxAmount, reasonData)
    closeNUI() 
    cb('ok')
end)

RegisterNUICallback('debtResponse', function(data, cb)
    TriggerServerEvent('space_economy:server_debtPaymentResponse', data.paid)
    cb('ok')
end)

-- Eventos para abrir os painéis (jogador e admin)
RegisterNetEvent('space_economy:openVaultPanel', function(balance)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openVaultPanel', balance = balance })
end)

RegisterNetEvent('space_economy:openAddVaultPanel', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openAddVaultPanel' })
end)

RegisterNetEvent('space_economy:openWithdrawVaultPanel', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openWithdrawVaultPanel' })
end)

RegisterNetEvent('space_economy:openDebtListPanel', function(debts)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showDebtList', debts = debts })
end)

RegisterNetEvent('space_economy:openDebtDetails', function(debtInfo)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showDebtDetails', debt = debtInfo })
end)

RegisterNetEvent('space_economy:promptDebtPayment', function(debtAmount)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openDebtCollectPrompt',
        amount = debtAmount
    })
end)

RegisterNetEvent('space_economy:openAdminDashboard', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openAdminDashboard' })
end)

-- Exibe a notificação de mandado de prisão apenas para a polícia.
RegisterNetEvent('space_economy:issueWarrantAlert', function(title, description)
    local player = exports.qbx_core:GetPlayerData()
    if player.job.name == Config.WarrantAlert.police_job_name then
        exports.ox_lib:notify({
            title = title,
            description = description,
            type = 'error',
            duration = 15000
        })
    end
end)

-- Callbacks da NUI para ações administrativas
RegisterNUICallback('forceClose', function(data, cb)
    closeNUI()
    cb('ok')
end)

RegisterNUICallback('admin_addCofre', function(data, cb)
    TriggerServerEvent('space_economy:server_addCofre', tonumber(data.amount))
    cb('ok')
end)

RegisterNUICallback('admin_sacarCofre', function(data, cb)
    TriggerServerEvent('space_economy:server_sacarCofre', tonumber(data.amount))
    cb('ok')
end)

RegisterNUICallback('admin_requestData', function(data, cb)
    TriggerServerEvent('space_economy:server_requestAdminData', data.dataType, data.payload)
    cb('ok')
end)

-- =================================================================
-- LÓGICA DO PAINEL FÍSICO DE ADMIN
-- =================================================================
CreateThread(function()
    if not Config.AdminPanel or not Config.AdminPanel.Location then return end
    local blipSettings = Config.AdminPanel.Blip
    local blip = AddBlipForCoord(Config.AdminPanel.Location)
    SetBlipSprite(blip, blipSettings.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipSettings.scale)
    SetBlipColour(blip, blipSettings.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(blipSettings.text)
    EndTextCommandSetBlipName(blip)

    while true do
        local wait = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        local distance = #(playerCoords - Config.AdminPanel.Location)

        if distance < Config.AdminPanel.InteractionDistance then
            wait = 5
            exports.ox_lib:showTextUI('[E] - Abrir Painel de Controle')
            if IsControlJustReleased(0, 38) then
                TriggerServerEvent('space_economy:requestOpenAdminPanel')
            end
        end
        Wait(wait)
    end
end)

-- =================================================================
-- LÓGICA DO CLIENTE PARA FRENTES DE LAVAGEM DE DINHEIRO
-- =================================================================
CreateThread(function()
    if not Config.LaunderingFronts then return end

    -- Cria um blip para cada ponto de lavagem
    for _, front in pairs(Config.LaunderingFronts) do
        local blip = AddBlipForCoord(front.location)
        SetBlipSprite(blip, 108)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.7)
        SetBlipColour(blip, 5) -- Vermelho, indicando atividade ilegal
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(front.label)
        EndTextCommandSetBlipName(blip)
    end
end)

CreateThread(function()
    if not Config.LaunderingFronts then return end
    local isTextUIVisible = false
    
    while true do
        local wait = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        local playerData = exports.qbx_core:GetPlayerData()
        local currentFront = nil
        
        if playerData and playerData.job then
            for business_id, front in pairs(Config.LaunderingFronts) do
                if #(playerCoords - front.location) < 2.5 then
                    wait = 5
                    if playerData.job.name == front.job_name and playerData.job.grade.level >= front.min_grade then
                        currentFront = front
                        currentFront.id = business_id
                    end
                    break
                end
            end
        end

        if currentFront and not isTextUIVisible then
            exports.ox_lib:showTextUI('[E] - Lavar Dinheiro')
            isTextUIVisible = true
        elseif not currentFront and isTextUIVisible then
            exports.ox_lib:hideTextUI()
            isTextUIVisible = false
        end

        if currentFront and IsControlJustReleased(0, 38) then -- Tecla E
            TriggerEvent('space_economy:client:openLaunderingPanel', currentFront.id)
        end
        
        Wait(wait)
    end
end)

-- Evento para abrir o painel de lavagem
RegisterNetEvent('space_economy:client:openLaunderingPanel', function(businessId)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openLaunderingPanel',
        businessId = businessId
    })
end)

-- Callback que recebe os dados do painel de lavagem (script.js)
RegisterNUICallback('washMoney', function(data, cb)
    TriggerServerEvent('space_economy:server_washMoney', data.businessId, data.amount, data.fee_percent)
    cb('ok')
end)

-- =================================================================
-- LÓGICA DA CALCULADORA DE TAXAS (CORRIGIDO)
-- =================================================================

-- BLOCO 1: Recebe o comando do servidor para abrir o painel da calculadora
RegisterNetEvent('space_economy:client:openCalculator', function()
    -- Abre o nosso painel customizado da NUI
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openCalculator' })
end)

-- BLOCO 2: Recebe o resultado do cálculo e exibe na tela
RegisterNetEvent('space_economy:client:showTaxCalculation', function(originalAmount, tax, totalAmount)
    -- Fecha o painel da calculadora antes de mostrar o resultado
    closeNUI()
    -- CORRIGIDO: Substituído o 'showAlert' que causava erro por 'notify'.
    exports.ox_lib:notify({
        title = 'Resultado do Cálculo de Taxa',
        description = string.format('Valor: $%s | Imposto: $%s | Total: $%s', originalAmount, tax, totalAmount),
        type = 'inform'
    })
end)

-- BLOCO 3: Callback que recebe o valor do painel da calculadora e envia ao servidor
RegisterNUICallback('calculateTax', function(data, cb)
    TriggerServerEvent('space_economy:server:getTaxCalculation', tonumber(data.amount))
    cb('ok')
end)