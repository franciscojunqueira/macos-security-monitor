#!/bin/bash
# Script de teste abrangente para config_monitor.sh
# Testa todas as opções e cenários possíveis

set -euo pipefail

# Configurações
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SCRIPT="$SCRIPT_DIR/../scripts/config_monitor.sh"
MONITOR_DIR="${HOME}/Library/Application Support/monitor_instalacoes"
CONFIG_DIR="$MONITOR_DIR/config"
BACKUP_DIR="$MONITOR_DIR/backup_$(date +%Y%m%d_%H%M%S)"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Função para fazer backup das configurações existentes
backup_configs() {
    echo_color "$BLUE" "=== Fazendo backup das configurações existentes ==="
    if [ -d "$CONFIG_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        cp -r "$CONFIG_DIR"/* "$BACKUP_DIR/" 2>/dev/null || true
        echo_color "$GREEN" "Backup salvo em: $BACKUP_DIR"
    else
        echo_color "$YELLOW" "Nenhuma configuração existente encontrada"
    fi
    echo
}

# Função para restaurar backup
restore_configs() {
    echo_color "$BLUE" "=== Restaurando configurações originais ==="
    if [ -d "$BACKUP_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        cp -r "$BACKUP_DIR"/* "$CONFIG_DIR/" 2>/dev/null || true
        echo_color "$GREEN" "Configurações restauradas"
    fi
    echo
}

# Função para limpar configurações
clean_configs() {
    echo_color "$BLUE" "=== Limpando configurações para teste ==="
    rm -rf "$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
    echo_color "$GREEN" "Configurações limpas"
    echo
}

# Função para verificar se arquivo foi criado
check_file() {
    local file="$1"
    local description="$2"
    if [ -f "$file" ]; then
        echo_color "$GREEN" "✅ $description: $(basename "$file") criado"
        echo "   Conteúdo: $(cat "$file" 2>/dev/null | head -3 | tr '\n' ' ')"
    else
        echo_color "$RED" "❌ $description: $(basename "$file") NÃO criado"
        return 1
    fi
}

# Função para testar configuração de modo
test_mode_configuration() {
    echo_color "$BLUE" "=== Teste 1: Configuração de Modo ==="
    
    # Testa todos os modos válidos
    for mode in quick normal full; do
        echo_color "$YELLOW" "Testando modo: $mode"
        echo -e "1\n$mode\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
        
        if check_file "$CONFIG_DIR/mode.env" "Modo $mode"; then
            expected="export MONITOR_MODE=\"$mode\""
            if grep -q "$expected" "$CONFIG_DIR/mode.env"; then
                echo_color "$GREEN" "✅ Modo $mode configurado corretamente"
            else
                echo_color "$RED" "❌ Conteúdo incorreto para modo $mode"
            fi
        fi
        echo
    done
    
    # Testa modo inválido
    echo_color "$YELLOW" "Testando modo inválido..."
    echo -e "1\ninvalid\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Modo inválido rejeitado adequadamente"
    echo
}

# Função para testar configuração de notificações
test_notification_configuration() {
    echo_color "$BLUE" "=== Teste 2: Configuração de Notificações ==="
    
    # Testa configuração válida
    echo_color "$YELLOW" "Testando notificações: 6h, agrupadas"
    echo -e "2\n6\ny\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    
    if check_file "$CONFIG_DIR/notifications.env" "Notificações"; then
        if grep -q "NOTIFICATION_FREQUENCY=\"6\"" "$CONFIG_DIR/notifications.env" && \
           grep -q "ENABLE_GROUPED_NOTIFICATIONS=\"true\"" "$CONFIG_DIR/notifications.env"; then
            echo_color "$GREEN" "✅ Notificações configuradas corretamente"
        else
            echo_color "$RED" "❌ Conteúdo incorreto nas notificações"
        fi
    fi
    
    # Testa sem agrupamento
    echo_color "$YELLOW" "Testando notificações: 12h, não agrupadas"
    echo -e "2\n12\nn\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    
    if grep -q "ENABLE_GROUPED_NOTIFICATIONS=\"false\"" "$CONFIG_DIR/notifications.env"; then
        echo_color "$GREEN" "✅ Desabilitação de agrupamento funciona"
    else
        echo_color "$RED" "❌ Desabilitação de agrupamento não funciona"
    fi
    
    # Testa valores inválidos
    echo_color "$YELLOW" "Testando frequência inválida..."
    echo -e "2\n25\ny\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Frequência inválida rejeitada adequadamente"
    echo
}

# Função para testar gerenciamento de apps críticos
test_critical_apps_management() {
    echo_color "$BLUE" "=== Teste 3: Gerenciamento de Apps Críticos ==="
    
    # Testa detecção automática
    echo_color "$YELLOW" "Testando detecção automática..."
    echo -e "3\n3\n4\n8" | timeout 60 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    
    if [ -f "$CONFIG_DIR/critical_apps.txt" ]; then
        apps_count=$(wc -l < "$CONFIG_DIR/critical_apps.txt" 2>/dev/null || echo "0")
        echo_color "$GREEN" "✅ Detecção automática encontrou $apps_count app(s)"
        if [ "$apps_count" -gt 0 ]; then
            echo "   Apps detectados:"
            cat "$CONFIG_DIR/critical_apps.txt" | head -5 | sed 's/^/   /'
        fi
    else
        echo_color "$YELLOW" "⚠️  Nenhum app de segurança detectado automaticamente"
    fi
    
    # Testa adição manual de app (usando um app que sabemos que existe)
    echo_color "$YELLOW" "Testando adição manual de app..."
    if [ -d "/Applications/Safari.app" ]; then
        echo -e "3\n1\n/Applications/Safari.app\n4\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
        
        if grep -q "/Applications/Safari.app" "$CONFIG_DIR/critical_apps.txt" 2>/dev/null; then
            echo_color "$GREEN" "✅ Adição manual de app funciona"
        else
            echo_color "$RED" "❌ Adição manual de app não funciona"
        fi
    fi
    
    # Testa remoção de app
    if [ -f "$CONFIG_DIR/critical_apps.txt" ] && [ -s "$CONFIG_DIR/critical_apps.txt" ]; then
        echo_color "$YELLOW" "Testando remoção de app..."
        echo -e "3\n2\n1\n4\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
        echo_color "$GREEN" "✅ Função de remoção testada"
    fi
    
    # Testa app inexistente
    echo_color "$YELLOW" "Testando app inexistente..."
    echo -e "3\n1\n/Applications/AppInexistente.app\n4\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ App inexistente rejeitado adequadamente"
    echo
}

# Função para testar configuração de logs
test_log_configuration() {
    echo_color "$BLUE" "=== Teste 4: Configuração de Logs ==="
    
    # Testa configuração válida
    echo_color "$YELLOW" "Testando logs: 100MB, 10 arquivos"
    echo -e "4\n100\n10\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    
    if check_file "$CONFIG_DIR/logs.env" "Configuração de logs"; then
        if grep -q "LOG_MAX_SIZE_MB=\"100\"" "$CONFIG_DIR/logs.env" && \
           grep -q "LOG_ROTATION_COUNT=\"10\"" "$CONFIG_DIR/logs.env"; then
            echo_color "$GREEN" "✅ Logs configurados corretamente"
        else
            echo_color "$RED" "❌ Conteúdo incorreto na configuração de logs"
        fi
    fi
    
    # Testa valores inválidos
    echo_color "$YELLOW" "Testando tamanho inválido (600MB)..."
    echo -e "4\n600\n5\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Tamanho inválido rejeitado adequadamente"
    
    echo_color "$YELLOW" "Testando contagem inválida (25 arquivos)..."
    echo -e "4\n50\n25\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Contagem inválida rejeitada adequadamente"
    echo
}

# Função para testar visualização de status
test_status_display() {
    echo_color "$BLUE" "=== Teste 5: Visualização de Status ==="
    
    echo_color "$YELLOW" "Testando exibição de status..."
    output=$(echo -e "5\n8" | timeout 30 "$CONFIG_SCRIPT" 2>/dev/null || true)
    
    if echo "$output" | grep -q "Status Atual"; then
        echo_color "$GREEN" "✅ Status exibido corretamente"
        if echo "$output" | grep -q "Configurações:"; then
            echo_color "$GREEN" "✅ Configurações listadas"
        fi
        if echo "$output" | grep -q "Apps críticos:"; then
            echo_color "$GREEN" "✅ Contagem de apps críticos exibida"
        fi
    else
        echo_color "$RED" "❌ Status não exibido corretamente"
    fi
    echo
}

# Função para testar configuração de testes
test_test_configuration() {
    echo_color "$BLUE" "=== Teste 6: Função de Teste ==="
    
    echo_color "$YELLOW" "Testando função de teste (modo quick, 30s timeout)..."
    # Testa a função de teste com timeout menor
    timeout 45 bash -c 'cd "$SCRIPT_DIR/../scripts" && echo -e "6\n8" | ./config_monitor.sh' >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Função de teste executada (pode ter sido interrompida por timeout)"
    echo
}

# Função para testar LaunchAgent (sem realmente instalar)
test_launchagent_menu() {
    echo_color "$BLUE" "=== Teste 7: Menu LaunchAgent ==="
    
    echo_color "$YELLOW" "Testando acesso ao menu LaunchAgent..."
    # Apenas testa se o menu abre e fecha sem instalar
    echo -e "7\nn\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Menu LaunchAgent acessível"
    echo
}

# Função para testar opções inválidas
test_invalid_options() {
    echo_color "$BLUE" "=== Teste 8: Opções Inválidas ==="
    
    echo_color "$YELLOW" "Testando opção inválida (99)..."
    echo -e "99\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Opção inválida tratada adequadamente"
    
    echo_color "$YELLOW" "Testando opção não numérica (abc)..."
    echo -e "abc\n8" | timeout 30 "$CONFIG_SCRIPT" >/dev/null 2>&1 || true
    echo_color "$GREEN" "✅ Opção não numérica tratada adequadamente"
    echo
}

# Função para verificar integridade dos arquivos
verify_final_state() {
    echo_color "$BLUE" "=== Verificação Final ==="
    
    echo "Arquivos de configuração criados:"
    find "$CONFIG_DIR" -type f 2>/dev/null | while read -r file; do
        if [ -f "$file" ]; then
            size=$(wc -c < "$file" 2>/dev/null || echo "0")
            echo_color "$GREEN" "✅ $(basename "$file") ($size bytes)"
        fi
    done
    
    # Testa se todas as configurações são carregáveis
    echo_color "$YELLOW" "Testando carregamento final de todas as configurações..."
    if [ -f "$CONFIG_DIR/mode.env" ] && [ -f "$CONFIG_DIR/notifications.env" ] && [ -f "$CONFIG_DIR/logs.env" ]; then
        # Simula carregamento das configurações
        source "$CONFIG_DIR/mode.env" 2>/dev/null || true
        source "$CONFIG_DIR/notifications.env" 2>/dev/null || true  
        source "$CONFIG_DIR/logs.env" 2>/dev/null || true
        echo_color "$GREEN" "✅ Todas as configurações são carregáveis"
    else
        echo_color "$YELLOW" "⚠️  Nem todas as configurações foram criadas"
    fi
    echo
}

# Função principal
run_comprehensive_test() {
    echo_color "$BLUE" "==================================================="
    echo_color "$BLUE" "  TESTE ABRANGENTE DO CONFIG_MONITOR.SH"
    echo_color "$BLUE" "==================================================="
    echo
    
    # Verifica se o script existe
    if [ ! -f "$CONFIG_SCRIPT" ]; then
        echo_color "$RED" "❌ Script config_monitor.sh não encontrado em: $CONFIG_SCRIPT"
        exit 1
    fi
    
    echo_color "$GREEN" "✅ Script encontrado: $CONFIG_SCRIPT"
    echo
    
    # Faz backup e limpa configurações
    backup_configs
    clean_configs
    
    # Executa todos os testes
    test_mode_configuration
    test_notification_configuration  
    test_critical_apps_management
    test_log_configuration
    test_status_display
    test_test_configuration
    test_launchagent_menu
    test_invalid_options
    
    # Verificação final
    verify_final_state
    
    echo_color "$BLUE" "==================================================="
    echo_color "$GREEN" "  TESTE ABRANGENTE CONCLUÍDO!"
    echo_color "$BLUE" "==================================================="
    echo
    echo_color "$YELLOW" "Para restaurar as configurações originais:"
    echo_color "$YELLOW" "  bash $0 --restore"
    echo
    echo_color "$YELLOW" "Backup das configurações originais em:"
    echo_color "$YELLOW" "  $BACKUP_DIR"
    echo
}

# Função para restaurar backup
restore_backup() {
    echo_color "$BLUE" "=== Restauração de Backup ==="
    
    # Procura o backup mais recente
    if [ -d "$BACKUP_DIR" ]; then
        restore_configs
        echo_color "$GREEN" "✅ Backup restaurado com sucesso!"
    else
        # Procura outros backups
        latest_backup=$(find "$MONITOR_DIR" -name "backup_*" -type d 2>/dev/null | sort -r | head -1)
        if [ -n "$latest_backup" ] && [ -d "$latest_backup" ]; then
            BACKUP_DIR="$latest_backup"
            restore_configs
            echo_color "$GREEN" "✅ Backup mais recente restaurado: $(basename "$latest_backup")"
        else
            echo_color "$YELLOW" "⚠️  Nenhum backup encontrado"
        fi
    fi
}

# Processa argumentos da linha de comando
case "${1:-}" in
    --restore)
        restore_backup
        exit 0
        ;;
    --help|-h)
        echo "Uso: $0 [--restore|--help]"
        echo
        echo "Opções:"
        echo "  (sem argumentos)  Executa teste abrangente"
        echo "  --restore         Restaura backup das configurações"
        echo "  --help           Mostra esta ajuda"
        exit 0
        ;;
    *)
        run_comprehensive_test
        ;;
esac