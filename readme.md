
# Space Economy - Sistema Econômico Dinâmico para QBCore

**Space Economy** é um script avançado e interativo para servidores FiveM que utilizam o framework QBCore. Ele cria um fluxo econômico mais realista, onde as transações dos jogadores geram impostos que alimentam um cofre central do governo. Administradores podem gerenciar esse cofre por meio de painéis NUI modernos.

O sistema também inclui uma mecânica de dívidas para impostos não pagos, com consequências reais integradas a scripts policiais como `ps-dispatch` e `ps-mdt`.

---

## Features

- **Sistema de Imposto Progressivo:** Taxas calculadas com base em faixas de valor, tornando a tributação mais justa (configurável).
- **Tesouro Centralizado:** Impostos arrecadados são depositados em um cofre governamental persistente no banco de dados.
- **Sistema de Dívidas:** Jogadores que não pagam seus impostos acumulam dívidas ativas.
- **Painéis NUI Modernos:** Interfaces intuitivas para jogadores (pagamento de taxas) e administradores (gerenciamento).
- **Gerenciamento Administrativo Completo:** Comandos e painéis NUI para visualizar o cofre, adicionar/remover fundos, ver lista de devedores (com nome do personagem) e cobrar dívidas.
- **Permissões Granulares:** Suporte a permissões por grupo (ACE) e por cargo/grade do QBCore.
- **Integração com Polícia:** Ao cobrar dívidas não pagas, o sistema pode emitir alertas no `ps-dispatch` e criar mandados no `ps-mdt`.
- **Integração com qbx_core:** Captura todas as transações financeiras (`RemoveMoney`) para aplicar a taxação automaticamente.

---

## Instalação

### 1. Instalação Básica

- Baixe o script e coloque a pasta `space_economy` dentro da sua pasta `resources`.
- No seu `server.cfg` (ou `resources.cfg`), adicione:

  ```
  ensure space_economy
  ```

- Coloque essa linha preferencialmente depois das dependências `qbx_core`, `ox_lib` e `oxmysql`.

---

### 2. Banco de Dados (SQL)  DEIXEI TUDO NA PASTA INSTAL INCLUSIVE OS SCRIPTS MODIFICADOS CASO N QUEIRAM MODIFICAR NA MÃO

Execute os seguintes comandos SQL no seu banco de dados para criar as tabelas necessárias. Você pode usar o arquivo `.sql` pronto disponível na pasta `sql`.

```sql
CREATE TABLE IF NOT EXISTS `space_economy` (
  `id` INT NOT NULL PRIMARY KEY,
  `vault` BIGINT NOT NULL DEFAULT 0,
  `inflation` FLOAT NOT NULL DEFAULT 1.0
);

INSERT INTO `space_economy` (`id`, `vault`, `inflation`) VALUES (1, 0, 1.0)
  ON DUPLICATE KEY UPDATE id = id;

CREATE TABLE IF NOT EXISTS `space_economy_debts` (
  `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
  `amount` BIGINT NOT NULL,
  `reason` VARCHAR(255) DEFAULT NULL
);
```

---

### 3. Modificação Essencial no qbx_core

Esta etapa é obrigatória para o funcionamento correto do sistema de impostos, pois intercepta as transações financeiras.

- Abra o arquivo:  
  `[qbx]/qbx_core/server/player.lua`

- Localize a função `RemoveMoney` (aproximadamente entre as linhas 1296 e 1349).

- Substitua a função inteira pela versão abaixo (a única alteração relevante é a chamada para o export `space_economy:CalculateTax`):

```lua
---@param identifier Source | string
---@param moneyType MoneyType
---@param amount number
---@param reason? string
---@return boolean success if money was removed
function RemoveMoney(identifier, moneyType, amount, reason)
    local player = type(identifier) == 'string' and (GetPlayerByCitizenId(identifier) or GetOfflinePlayer(identifier)) or GetPlayer(identifier)

    if not player then return false end

    reason = reason or 'unknown'
    amount = qbx.math.round(tonumber(amount) --[[@as number]])

    if amount < 0 or not player.PlayerData.money[moneyType] then return false end

    if not triggerEventHooks('removeMoney', {
        source = player.PlayerData.source,
        moneyType = moneyType,
        amount = amount
    }) then return false end

    for _, mType in pairs(config.money.dontAllowMinus) do
        if mType == moneyType then
            if (player.PlayerData.money[moneyType] - amount) < 0 then
                return false
            end
        end
    end

    -- Desconta o valor da compra imediatamente
    player.PlayerData.money[moneyType] = player.PlayerData.money[moneyType] - amount

    -- // INÍCIO DA MODIFICAÇÃO - NÃO REMOVA ESTE BLOCO \ --
    -- Inicia cálculo da taxa econômica
    if amount > 0 and not player.Offline and (moneyType == 'cash' or moneyType == 'bank' or moneyType == 'crypto') then
        exports['space_economy']:CalculateTax(player.PlayerData.citizenid, amount, reason)
    end
    -- \ FIM DA MODIFICAÇÃO // --

    if not player.Offline then
        UpdatePlayerData(identifier)

        logger.log({
            source = GetInvokingResource() or cache.resource,
            webhook = config.logging.webhook['playermoney'],
            event = 'RemoveMoney',
            color = 'red',
            tags = amount > 100000 and config.logging.role or nil,
            message = ('**%s (citizenid: %s | id: %s)** $%s (%s) removed, new %s balance: $%s reason: %s'):format(
                GetPlayerName(player.PlayerData.source),
                player.PlayerData.citizenid,
                player.PlayerData.source,
                amount, moneyType, moneyType, player.PlayerData.money[moneyType], reason
            ),
        })

        emitMoneyEvents(player.PlayerData.source, player.PlayerData.money, moneyType, amount, 'remove', reason)
    end

    return true
end
```

---

### 4. Configuração

- Abra o arquivo `config.lua` dentro da pasta `space_economy`.
- Ajuste as permissões e demais opções conforme suas necessidades.

Exemplo básico para permissões e alerta:

```lua
-- Sistema de permissões por cargo e grade
Config.Permissions = {
    ['admin']    = { min_grade = 0 },
    ['police']   = { min_grade = 2 },
    ['governor'] = { min_grade = 0 },
}

-- Mensagem de alerta para a polícia
Config.WarrantAlert = {
    title = "ALERTA DE MANDADO",
    description = "Mandado de prisão e apreensão de bens emitido para %s (ID: %s) por dívida governamental não paga no valor de $%s. Todas as unidades, procedam com a captura.",
    police_job_name = 'police' -- Nome do job da polícia no seu servidor (em minúsculas)
}
```

---

## Comandos Administrativos

| Comando         | Argumentos           | Descrição                                                                                 |
|-----------------|---------------------|-------------------------------------------------------------------------------------------|
| `/vercofre`     | -                   | Abre painel NUI mostrando o saldo atual do cofre do governo.                             |
| `/addcofre`     | -                   | Abre painel NUI para adicionar fundos ao cofre do governo.                              |
| `/sacarcofre`   | -                   | Abre painel NUI para sacar fundos do cofre para o personagem (dinheiro em mãos).         |
| `/verdividas`   | `[citizenid]` (opcional) | Lista as dívidas; sem ID lista as 20 maiores; com ID, busca dívidas específicas.          |
| `/verdivida`    | `[citizenid]`        | Mostra detalhes da dívida de um cidadão específico.                                      |
| `/cobrardivida` | `[citizenid]`        | Inicia cobrança interativa de dívida. Envia painel para o jogador pagar ou recusar.       |

---

## Exportações (API)

Para integrar o sistema de taxas a outros scripts (lojas, multas, etc.), utilize o export no servidor:

```lua
exports['space_economy']:CalculateTax(citizenid, amount, reason)
```

- `citizenid` - Identificador do jogador.
- `amount` - Valor da transação.
- `reason` - Motivo da transação.

Isso abrirá automaticamente o painel de pagamento para o jogador.

---

## Dependências

- **qbx_core:** Framework base.
- **ox_lib:** Sistema de notificações.
- **oxmysql:** Comunicação com banco de dados.
- **ps-dispatch (Opcional):** Para alertas policiais em tempo real.
- **ps-mdt (Opcional):** Para registro permanente de mandados.

---

## Contato e Suporte

Para dúvidas, sugestões ou reportar bugs, utilize os canais oficiais do Space Store ou entre em contato diretamente.

---

*Este script é parte do portfólio da Space Store e foi desenvolvido para oferecer uma economia dinâmica e realista para servidores FiveM com QBCore.*
