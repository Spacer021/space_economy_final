// =================================================================
// SCRIPT.JS FINAL E COMPLETO
// =================================================================

// Função auxiliar para fechar todos os painéis e a NUI
function closeAllPanels() {
    document.body.style.display = 'none';
    document.querySelectorAll('.card').forEach(card => card.style.display = 'none');
    fetch(`https://${GetParentResourceName()}/forceClose`, { method: "POST" });
}

// Função auxiliar para enviar dados para o Lua
function postData(event, data = {}) {
    fetch(`https://${GetParentResourceName()}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    });
}

// Listener principal de mensagens vindas do client.lua
window.addEventListener('message', function(event) {
    const data = event.data;
    const action = data.action;

    document.querySelectorAll('.card').forEach(card => card.style.display = 'none');
    
    if (action !== 'close') {
        document.body.style.display = 'flex';
    }

    switch (action) {
        // --- PAINÉIS DO JOGADOR ---
        case 'open':
            document.querySelector("#tax-value").textContent = "$" + data.tax;
            document.querySelector("#payment-container .info-value").textContent = data.reason;
            document.getElementById('payment-container').style.display = 'block';
            break;
        case 'paymentSuccess':
            document.getElementById('success-message').textContent = `Sua taxa de $${data.tax} foi paga com sucesso.`;
            document.getElementById('success-container').style.display = 'block';
            break;
        case 'openDebtCollectPrompt':
            document.getElementById('debt-prompt-amount').textContent = '$' + data.amount;
            document.getElementById('debt-collect-prompt-container').style.display = 'block';
            break;

        // --- PAINÉIS ADMINISTRATIVOS ---
        case 'openAdminDashboard':
            document.getElementById('admin-dashboard-container').style.display = 'block';
            break;
        case 'openVaultPanel':
            document.getElementById('vault-balance-value').textContent = '$' + data.balance;
            document.getElementById('vault-view-container').style.display = 'block';
            break;
        case 'openAddVaultPanel':
            document.getElementById('add-amount-input').value = '';
            document.getElementById('vault-add-container').style.display = 'block';
            break;
        case 'openWithdrawVaultPanel':
            document.getElementById('withdraw-amount-input').value = '';
            document.getElementById('vault-withdraw-container').style.display = 'block';
            break;
        case 'showDebtList':
            const tableBody = document.querySelector("#debt-table tbody");
            tableBody.innerHTML = '';
            if (data.debts && data.debts.length > 0) {
                data.debts.forEach(debt => {
                    let row = tableBody.insertRow();
                    row.insertCell(0).textContent = debt.playerName || 'Não encontrado';
                    row.insertCell(1).textContent = debt.citizenid;
                    row.insertCell(2).textContent = '$' + debt.amount;
                    row.insertCell(3).textContent = debt.reason;
                });
            }
            document.getElementById('debt-list-container').style.display = 'block';
            break;
        case 'showDebtDetails':
              document.getElementById('debt-detail-name').textContent = data.debt.playerName || 'Não encontrado';
              document.getElementById('debt-detail-citizenid').textContent = data.debt.citizenid;
              document.getElementById('debt-detail-amount').textContent = '$' + data.debt.amount;
              document.getElementById('debt-detail-reason').textContent = data.debt.reason;
              document.getElementById('debt-detail-container').style.display = 'block';
            break;
        
        case 'openLaunderingPanel':
            const launderingContainer = document.getElementById('laundering-container');
            launderingContainer.dataset.businessId = data.businessId;
            document.getElementById('laundering-amount').value = '';
            document.getElementById('laundering-fee-percent').value = '';
            launderingContainer.style.display = 'block';
            document.getElementById('laundering-amount').focus();
            break;
        
        // ADICIONADO: Case para abrir o novo painel da calculadora
        case 'openCalculator':
            document.getElementById('calculator-input').value = '';
            document.getElementById('calculator-container').style.display = 'block';
            document.getElementById('calculator-input').focus();
            break;
    }
});

// =================================================================
// LISTENERS DE BOTÕES (EVENTOS DE CLIQUE)
// =================================================================

// --- BOTÕES GERAIS E DO JOGADOR ---
document.querySelectorAll('[data-close-button]').forEach(button => button.addEventListener('click', closeAllPanels));
document.getElementById("pay").addEventListener("click", () => postData('payTax'));
document.getElementById("refuse").addEventListener("click", () => { postData('refuseTax'); closeAllPanels(); });
document.getElementById('debt-prompt-pay').addEventListener('click', () => { postData('debtResponse', { paid: true }); closeAllPanels(); });
document.getElementById('debt-prompt-refuse').addEventListener('click', () => { postData('debtResponse', { paid: false }); closeAllPanels(); });

// --- BOTÕES DOS PAINÉIS DE AÇÃO ADMIN ---
document.getElementById('add-vault-confirm').addEventListener('click', () => {
    const amount = document.getElementById('add-amount-input').value;
    if(amount) { postData('admin_addCofre', { amount: amount }); closeAllPanels(); }
});
document.getElementById('withdraw-vault-confirm').addEventListener('click', () => {
    const amount = document.getElementById('withdraw-amount-input').value;
    if(amount) { postData('admin_sacarCofre', { amount: amount }); closeAllPanels(); }
});

// --- LÓGICA DO PAINEL DE DÍVIDAS ---
function requestAdminData(dataType, payload = null) {
    postData('admin_requestData', { dataType, payload });
}
document.querySelector('[data-action="viewVault"]').addEventListener('click', () => requestAdminData('vault'));
document.querySelector('[data-action="addVault"]').addEventListener('click', () => requestAdminData('addVault'));
document.querySelector('[data-action="withdrawVault"]').addEventListener('click', () => requestAdminData('withdrawVault'));
document.querySelector('[data-action="viewDebts"]').addEventListener('click', () => requestAdminData('debts'));

function showDebtInput(action, title) {
    document.getElementById('admin-dashboard-container').style.display = 'none';
    const debtInputContainer = document.getElementById('debt-input-container');
    document.getElementById('debt-input-title').textContent = title;
    document.getElementById('debt-citizenid-input').value = '';
    debtInputContainer.dataset.action = action;
    debtInputContainer.style.display = 'block';
    document.getElementById('debt-citizenid-input').focus();
}

document.querySelector('[data-action="viewSpecificDebt"]').addEventListener('click', () => showDebtInput('specific_debt', 'Buscar Dívida por ID'));
document.querySelector('[data-action="collectDebt"]').addEventListener('click', () => showDebtInput('collect_debt', 'Cobrar Dívida por ID'));

document.getElementById('debt-input-confirm').addEventListener('click', () => {
    const debtInputContainer = document.getElementById('debt-input-container');
    const action = debtInputContainer.dataset.action;
    const citizenId = document.getElementById('debt-citizenid-input').value;
    if (citizenId && citizenId.trim() !== '') {
        requestAdminData(action, citizenId);
        closeAllPanels();
    }
});
document.querySelector('[data-action="backToDashboard"]').addEventListener('click', () => {
    document.getElementById('debt-input-container').style.display = 'none';
    document.getElementById('admin-dashboard-container').style.display = 'block';
});

// Listener do painel de lavagem
document.getElementById('laundering-confirm').addEventListener('click', () => {
    const container = document.getElementById('laundering-container');
    const businessId = container.dataset.businessId;
    const amount = document.getElementById('laundering-amount').value;
    const fee_percent = document.getElementById('laundering-fee-percent').value;

    if (businessId && amount && fee_percent) {
        postData('washMoney', { 
            businessId: businessId,
            amount: parseInt(amount),
            fee_percent: parseFloat(fee_percent)
        });
        closeAllPanels();
    }
});

// ADICIONADO: Listener para o botão de confirmação do painel da calculadora
document.getElementById('calculator-confirm').addEventListener('click', () => {
    const amount = document.getElementById('calculator-input').value;
    if (amount) {
        postData('calculateTax', { amount: amount });
        // O painel não fecha aqui, pois aguardamos o alerta com o resultado.
    }
});


// Listener para fechar a NUI com a tecla ESC
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        closeAllPanels();
    }
});