#!/bin/bash
# Utilitário de configuração para o Monitor de Instalações
set -euo pipefail

MONITOR_DIR="${HOME}/Library/Application Support/monitor_instalacoes"
CONFIG_DIR="$MONITOR_DIR/config"
CRITICAL_APPS_LIST="$CONFIG_DIR/critical_apps.txt"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Cria estrutura se não existir
mkdir -p "$CONFIG_DIR"

show_menu() {
    clear
    echo_color "$BLUE" "=== Configuração do Monitor de Instalações ==="
    echo ""
    echo "1) Configurar modo de execução"
    echo "2) Configurar notificações"
    echo "3) Gerenciar apps críticos"
    echo "4) Configurar logs"
    echo "5) Ver status atual"
    echo "6) Testar configurações"
    echo "7) Instalar/Remover LaunchAgent"
    echo "8) Sair"
    echo ""
    echo -n "Escolha uma opção: "
}

configure_mode() {
    echo_color "$BLUE" "\n=== Configuração de Modo de Execução ==="
    echo ""
    echo "Modos disponíveis:"
    echo "• quick  - Apenas apps críticos (~30s)"
    echo "• normal - Verificação completa padrão (~2-3min)"
    echo "• full   - Verificação profunda (~5-10min)"
    echo ""
    
    current_mode="${MONITOR_MODE:-normal}"
    echo "Modo atual: $current_mode"
    echo ""
    echo -n "Novo modo [quick/normal/full]: "
    read -r new_mode
    
    case "$new_mode" in
        quick|normal|full)
            echo "export MONITOR_MODE=\"$new_mode\"" > "$CONFIG_DIR/mode.env"
            echo_color "$GREEN" "Modo configurado para: $new_mode"
            ;;
        *)
            echo_color "$RED" "Modo inválido!"
            ;;
    esac
}

configure_notifications() {
    echo_color "$BLUE" "\n=== Configuração de Notificações ==="
    echo ""
    
    current_freq="${NOTIFICATION_FREQUENCY:-1}"
    current_grouped="${ENABLE_GROUPED_NOTIFICATIONS:-true}"
    
    echo "Configuração atual:"
    echo "• Frequência: $current_freq horas"
    echo "• Agrupadas: $current_grouped"
    echo ""
    
    echo -n "Nova frequência em horas [1-24]: "
    read -r freq
    if [[ "$freq" =~ ^[1-9]$|^1[0-9]$|^2[0-4]$ ]]; then
        echo "export NOTIFICATION_FREQUENCY=\"$freq\"" > "$CONFIG_DIR/notifications.env"
        echo_color "$GREEN" "Frequência configurada para: $freq horas"
    else
        echo_color "$RED" "Frequência inválida (1-24)!"
        return 1
    fi
    
    echo -n "Habilitar notificações agrupadas? [y/n]: "
    read -r grouped
    if [[ "$grouped" =~ ^[yY]$ ]]; then
        echo "export ENABLE_GROUPED_NOTIFICATIONS=\"true\"" >> "$CONFIG_DIR/notifications.env"
        echo_color "$GREEN" "Notificações agrupadas habilitadas"
    else
        echo "export ENABLE_GROUPED_NOTIFICATIONS=\"false\"" >> "$CONFIG_DIR/notifications.env"
        echo_color "$YELLOW" "Notificações agrupadas desabilitadas"
    fi
}

manage_critical_apps() {
    echo_color "$BLUE" "\n=== Gerenciamento de Apps Críticos ==="
    echo ""
    
    if [ -f "$CRITICAL_APPS_LIST" ]; then
        echo "Apps críticos atuais:"
        echo_color "$YELLOW" "$(cat "$CRITICAL_APPS_LIST" | nl)"
        echo ""
    else
        echo "Nenhum app crítico configurado ainda."
        echo ""
    fi
    
    echo "Opções:"
    echo "1) Adicionar app"
    echo "2) Remover app"
    echo "3) Detectar apps de segurança automaticamente"
    echo "4) Voltar"
    echo ""
    echo -n "Escolha: "
    read -r choice
    
    case "$choice" in
        1)
            echo -n "Caminho completo do app (ex: /Applications/App.app): "
            read -r app_path
            if [ -d "$app_path" ]; then
                echo "$app_path" >> "$CRITICAL_APPS_LIST"
                echo_color "$GREEN" "App adicionado: $app_path"
            else
                echo_color "$RED" "App não encontrado!"
            fi
            ;;
        2)
            if [ -f "$CRITICAL_APPS_LIST" ]; then
                echo -n "Número da linha para remover: "
                read -r line_num
                if [[ "$line_num" =~ ^[0-9]+$ ]]; then
                    sed -i.bak "${line_num}d" "$CRITICAL_APPS_LIST" 2>/dev/null || echo_color "$RED" "Linha inválida!"
                    rm -f "$CRITICAL_APPS_LIST.bak" 2>/dev/null || true
                    echo_color "$GREEN" "App removido"
                fi
            fi
            ;;
        3)
            echo_color "$BLUE" "Detectando apps de segurança..."
            find /Applications -maxdepth 2 -name "*.app" -type d 2>/dev/null | \
                grep -iE "(security|antivirus|firewall|privacy|malware|block|snitch|lulu|knockknock|ransom|clamxav)" | \
                sort -u >> "$CRITICAL_APPS_LIST.new" 2>/dev/null || true
            
            if [ -f "$CRITICAL_APPS_LIST.new" ]; then
                cat "$CRITICAL_APPS_LIST" "$CRITICAL_APPS_LIST.new" 2>/dev/null | sort -u > "$CRITICAL_APPS_LIST.tmp"
                mv "$CRITICAL_APPS_LIST.tmp" "$CRITICAL_APPS_LIST"
                rm -f "$CRITICAL_APPS_LIST.new"
                echo_color "$GREEN" "Apps de segurança detectados e adicionados"
            else
                echo_color "$YELLOW" "Nenhum app de segurança encontrado"
            fi
            ;;
    esac
}

configure_logs() {
    echo_color "$BLUE" "\n=== Configuração de Logs ==="
    echo ""
    
    current_size="${LOG_MAX_SIZE_MB:-50}"
    current_count="${LOG_ROTATION_COUNT:-5}"
    
    echo "Configuração atual:"
    echo "• Tamanho máximo: ${current_size}MB"
    echo "• Arquivos mantidos: $current_count"
    echo ""
    
    echo -n "Novo tamanho máximo em MB [10-500]: "
    read -r size
    if [[ "$size" =~ ^[1-9][0-9]$|^[1-4][0-9][0-9]$|^500$ ]]; then
        echo "export LOG_MAX_SIZE_MB=\"$size\"" > "$CONFIG_DIR/logs.env"
    else
        echo_color "$RED" "Tamanho inválido (10-500MB)!"
        return 1
    fi
    
    echo -n "Número de arquivos a manter [3-20]: "
    read -r count
    if [[ "$count" =~ ^[3-9]$|^1[0-9]$|^20$ ]]; then
        echo "export LOG_ROTATION_COUNT=\"$count\"" >> "$CONFIG_DIR/logs.env"
        echo_color "$GREEN" "Configuração de logs atualizada"
    else
        echo_color "$RED" "Contagem inválida (3-20)!"
        return 1
    fi
}

show_status() {
    echo_color "$BLUE" "\n=== Status Atual ==="
    echo ""
    
    # Carrega configurações
    [ -f "$CONFIG_DIR/mode.env" ] && source "$CONFIG_DIR/mode.env"
    [ -f "$CONFIG_DIR/notifications.env" ] && source "$CONFIG_DIR/notifications.env"
    [ -f "$CONFIG_DIR/logs.env" ] && source "$CONFIG_DIR/logs.env"
    
    echo "Configurações:"
    echo "• Modo: ${MONITOR_MODE:-normal}"
    echo "• Frequência notif.: ${NOTIFICATION_FREQUENCY:-1}h"
    echo "• Notif. agrupadas: ${ENABLE_GROUPED_NOTIFICATIONS:-true}"
    echo "• Log max: ${LOG_MAX_SIZE_MB:-50}MB"
    echo "• Arquivos mantidos: ${LOG_ROTATION_COUNT:-5}"
    echo ""
    
    if [ -f "$CRITICAL_APPS_LIST" ]; then
        echo "Apps críticos: $(wc -l < "$CRITICAL_APPS_LIST") configurados"
    else
        echo "Apps críticos: 0 configurados"
    fi
    
    echo ""
    if [ -d "$MONITOR_DIR" ]; then
        echo "Estatísticas:"
        echo "• Cache: $(du -sh "$MONITOR_DIR/cache" 2>/dev/null | cut -f1 || echo "0B")"
        echo "• Logs: $(du -sh "$MONITOR_DIR/logs" 2>/dev/null | cut -f1 || echo "0B")"
    fi
}

test_configuration() {
    echo_color "$BLUE" "\n=== Teste de Configuração ==="
    echo ""
    
    # Carrega todas as configurações
    export_configs
    
    echo_color "$YELLOW" "Testando configuração atual..."
    echo ""
    
    # Testa modo rápido
    echo "Executando teste em modo rápido..."
    MONITOR_MODE="quick" timeout 60 ./monitor_instalacoes_final.sh || true
    
    echo_color "$GREEN" "Teste concluído! Verifique os logs para detalhes."
}

export_configs() {
    # Exporta todas as configurações como variáveis de ambiente
    [ -f "$CONFIG_DIR/mode.env" ] && source "$CONFIG_DIR/mode.env"
    [ -f "$CONFIG_DIR/notifications.env" ] && source "$CONFIG_DIR/notifications.env"
    [ -f "$CONFIG_DIR/logs.env" ] && source "$CONFIG_DIR/logs.env"
}

install_launchagent() {
    echo_color "$BLUE" "\n=== Instalação/Remoção LaunchAgent ==="
    echo ""
    
    local plist_path="${HOME}/Library/LaunchAgents/com.user.monitor-instalacoes.plist"
    local script_path="$(pwd)/monitor_instalacoes_final.sh"
    
    if [ -f "$plist_path" ]; then
        echo "LaunchAgent já instalado."
        echo -n "Remover? [y/n]: "
        read -r remove
        if [[ "$remove" =~ ^[yY]$ ]]; then
            launchctl unload "$plist_path" 2>/dev/null || true
            rm -f "$plist_path"
            echo_color "$GREEN" "LaunchAgent removido"
        fi
        return 0
    fi
    
    echo "Intervalos sugeridos:"
    echo "• 300  - 5 minutos (desenvolvimento)"
    echo "• 1800 - 30 minutos (modo normal)"
    echo "• 3600 - 1 hora (modo economia)"
    echo ""
    echo -n "Intervalo em segundos: "
    read -r interval
    
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 60 ]; then
        echo_color "$RED" "Intervalo inválido (mínimo 60s)!"
        return 1
    fi
    
    # Cria o LaunchAgent
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.monitor-instalacoes</string>
    <key>ProgramArguments</key>
    <array>
        <string>$script_path</string>
    </array>
    <key>StartInterval</key>
    <integer>$interval</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$MONITOR_DIR/logs/launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>$MONITOR_DIR/logs/launchagent_error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin</string>
EOF
    
    # Adiciona variáveis de configuração
    export_configs
    [ -n "${MONITOR_MODE:-}" ] && cat >> "$plist_path" << EOF
        <key>MONITOR_MODE</key>
        <string>$MONITOR_MODE</string>
EOF
    [ -n "${NOTIFICATION_FREQUENCY:-}" ] && cat >> "$plist_path" << EOF
        <key>NOTIFICATION_FREQUENCY</key>
        <string>$NOTIFICATION_FREQUENCY</string>
EOF
    
    cat >> "$plist_path" << EOF
    </dict>
</dict>
</plist>
EOF
    
    # Carrega o LaunchAgent
    launchctl load "$plist_path"
    echo_color "$GREEN" "LaunchAgent instalado e carregado (intervalo: ${interval}s)"
}

# Menu principal
while true; do
    show_menu
    read -r option
    
    case $option in
        1) configure_mode ;;
        2) configure_notifications ;;
        3) manage_critical_apps ;;
        4) configure_logs ;;
        5) show_status ;;
        6) test_configuration ;;
        7) install_launchagent ;;
        8) echo_color "$GREEN" "Saindo..."; exit 0 ;;
        *) echo_color "$RED" "Opção inválida!" ;;
    esac
    
    echo ""
    echo -n "Pressione Enter para continuar..."
    read -r
done