# Testes do macOS Security Monitor

Este diretório contém os testes automatizados para o macOS Security Monitor.

## Scripts de Teste

### `test_config_monitor.sh`

Script de teste abrangente para o utilitário de configuração `config_monitor.sh`.

#### Funcionalidades Testadas

✅ **Configuração de Modo de Execução**
- Testa modos: `quick`, `normal`, `full`
- Valida rejeição de modos inválidos
- Verifica persistência das configurações

✅ **Configuração de Notificações**
- Testa frequências válidas (1-24 horas)
- Testa habilitação/desabilitação de agrupamento
- Valida rejeição de valores inválidos

✅ **Gerenciamento de Apps Críticos**
- Detecção automática de apps de segurança
- Adição manual de aplicativos
- Remoção de aplicativos da lista
- Validação de caminhos de apps

✅ **Configuração de Logs**
- Testa tamanhos válidos (10-500MB)
- Testa contagem de arquivos (3-20)
- Valida rejeição de valores fora dos limites

✅ **Visualização de Status**
- Verifica exibição de configurações atuais
- Testa contagem de apps críticos
- Valida estatísticas do sistema

✅ **Funcionalidade de Teste**
- Executa teste em modo quick com timeout
- Verifica funcionamento básico do monitor

✅ **Menu LaunchAgent**
- Testa acesso ao menu de instalação
- Verifica funcionamento sem instalação real

✅ **Tratamento de Erros**
- Testa opções inválidas do menu
- Verifica entrada não numérica

## Como Usar

### Execução Básica

```bash
# A partir do diretório raiz do projeto
./tests/test_config_monitor.sh
```

### Opções Disponíveis

```bash
# Executa todos os testes
./tests/test_config_monitor.sh

# Restaura configurações originais
./tests/test_config_monitor.sh --restore  

# Mostra ajuda
./tests/test_config_monitor.sh --help
```

## Funcionalidades de Segurança

### Backup Automático
- Faz backup das configurações existentes antes de testar
- Salva em `~/Library/Application Support/monitor_instalacoes/backup_YYYYMMDD_HHMMSS/`

### Restauração
- Pode restaurar configurações originais após os testes
- Localiza e restaura o backup mais recente automaticamente

### Timeout de Segurança
- Usa `timeout` para evitar que testes travem
- Cada teste tem limite de tempo apropriado

## Estrutura dos Testes

### 1. Preparação
- Backup de configurações existentes
- Limpeza do ambiente de teste
- Verificação de dependências

### 2. Execução
- 8 suítes de teste independentes
- Validação de entrada e saída
- Verificação de persistência de dados

### 3. Verificação
- Validação de arquivos criados
- Teste de carregamento de configurações
- Relatório de resultados

## Arquivos Testados

O script testa a criação e validação dos seguintes arquivos:

- `~/Library/Application Support/monitor_instalacoes/config/mode.env`
- `~/Library/Application Support/monitor_instalacoes/config/notifications.env`
- `~/Library/Application Support/monitor_instalacoes/config/logs.env`
- `~/Library/Application Support/monitor_instalacoes/config/critical_apps.txt`

## Saída do Teste

### Formato dos Resultados
- ✅ Verde: Teste passou
- ❌ Vermelho: Teste falhou
- ⚠️ Amarelo: Aviso ou situação especial

### Exemplo de Saída
```
=== Teste 1: Configuração de Modo ===
Testando modo: quick
✅ Modo quick: mode.env criado
   Conteúdo: export MONITOR_MODE="quick"
✅ Modo quick configurado corretamente
```

## Troubleshooting

### Script não encontrado
```bash
# Certifique-se de estar no diretório correto
cd /caminho/para/macos-security-monitor
./tests/test_config_monitor.sh
```

### Permissões
```bash
# Torne o script executável se necessário
chmod +x tests/test_config_monitor.sh
```

### Timeout Issues
Se testes estão expirando, pode ser devido a:
- Sistema lento
- Muitos apps instalados (detecção automática demora mais)
- Prompt de senha do sistema

### Restauração de Backup
```bash
# Listar backups disponíveis
ls -la ~/Library/Application\ Support/monitor_instalacoes/backup_*

# Restaurar manualmente
./tests/test_config_monitor.sh --restore
```

## Integração com CI/CD

Os testes são compatíveis com GitHub Actions e podem ser integrados ao pipeline de CI/CD:

```yaml
- name: Run configuration tests
  run: ./tests/test_config_monitor.sh
```

## Desenvolvimento

### Adicionando Novos Testes

Para adicionar novos testes ao script:

1. Crie uma nova função `test_nova_funcionalidade()`
2. Adicione a chamada em `run_comprehensive_test()`
3. Siga o padrão de nomenclatura e saída existente

### Convenções

- Use `echo_color` para saídas coloridas
- Implemente timeout adequado para cada teste
- Valide tanto entrada quanto saída
- Teste cenários válidos e inválidos

## Dependências

### Ferramentas Requeridas
- `bash` (3.2+ ou 4.0+)
- `timeout` (GNU coreutils)
- `grep`, `sed`, `find` (utilitários padrão)

### Sistemas Suportados
- macOS 10.14+ (Mojave ou superior)
- Tanto Intel quanto Apple Silicon

## Limitações

1. **Detecção automática**: Depende de apps instalados no sistema
2. **LaunchAgent**: Não instala realmente (apenas testa menu)
3. **Função de teste**: Limitada por timeout para evitar travamentos
4. **Permissões**: Requer acesso a `~/Library/Application Support/`

## Contribuição

Para contribuir com melhorias nos testes:

1. Fork do repositório
2. Crie branch para sua funcionalidade
3. Adicione testes apropriados
4. Teste em diferentes versões do macOS
5. Abra Pull Request

## Licença

Os testes seguem a mesma licença do projeto principal.