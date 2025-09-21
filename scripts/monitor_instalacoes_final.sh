#!/bin/bash
# Monitor de mudanças críticas no macOS (VERSÃO FINAL OTIMIZADA)
# Apps: monitora por fingerprint do Info.plist (BundleID, ShortVersion, Build, TeamID, hash do Info.plist)
set -euo pipefail

# ===== Configuração Avançada =====
# Modos de execução:
# - quick: Apenas apps críticos e mudanças essenciais (~30s)
# - normal: Verificação padrão completa (~2-3min)
# - full: Verificação completa + análise profunda (~5-10min)
MONITOR_MODE="${MONITOR_MODE:-normal}"

# Frequência de notificações (em horas)
NOTIFICATION_FREQUENCY="${NOTIFICATION_FREQUENCY:-1}"

# Tamanho máximo do log principal (em MB)
LOG_MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-50}"

# Número de arquivos de log a manter
LOG_ROTATION_COUNT="${LOG_ROTATION_COUNT:-5}"

# Habilita notificações agrupadas
ENABLE_GROUPED_NOTIFICATIONS="${ENABLE_GROUPED_NOTIFICATIONS:-true}"

# Apps críticos (podem ser definidos via variável de ambiente)
CRITICAL_APPS="${CRITICAL_APPS:-/Applications/Little Snitch.app:/Applications/1Blocker- Ad Blocker & Privacy.app:/Applications/Privacy Cleaner Pro.app:/Applications/Malware Hunter.app:/Applications/ClamXav.app:/Applications/BlockBlock.app:/Applications/LuLu.app:/Applications/RansomWhere?.app:/Applications/KnockKnock.app}"

# ===== Ambiente "duro" (HOME pode não existir em LaunchDaemon) =====
if [ -z "${HOME:-}" ] || [ ! -d "${HOME:-/var/root}" ]; then
  U="$(/usr/bin/id -un 2>/dev/null || echo root)"
  H="$(/usr/bin/dscl . -read /Users/$U NFSHomeDirectory 2>/dev/null | /usr/bin/awk -F': ' '{print $2}')"
  HOME="${H:-/var/root}"
fi
export LC_ALL=C
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# ===== Estrutura de Diretórios =====
if [ "$(/usr/bin/id -u)" -eq 0 ]; then
  BASE="/var/db/monitor_instalacoes"
else
  BASE="${HOME:-/var/root}/Library/Application Support/monitor_instalacoes"
fi
/bin/mkdir -p "$BASE"

CACHE_DIR="$BASE/cache"
LOGS_DIR="$BASE/logs"
CONFIG_DIR="$BASE/config"
NOTIFICATIONS_DIR="$BASE/notifications"

/bin/mkdir -p "$CACHE_DIR" "$LOGS_DIR" "$CONFIG_DIR" "$NOTIFICATIONS_DIR"

# ===== Configuração de Logs Rotativos =====
LOG_FILE="${LOG_FILE:-$LOGS_DIR/monitor_$(date +%Y%m%d).log}"
SUMMARY_LOG="$LOGS_DIR/summary.log"
CRITICAL_LOG="$LOGS_DIR/critical.log"

# ===== Configurações de Notificação =====
LAST_NOTIFICATION_FILE="$NOTIFICATIONS_DIR/last_notification"
PENDING_NOTIFICATIONS_FILE="$NOTIFICATIONS_DIR/pending.json"
NOTIFICATION_SUMMARY_FILE="$NOTIFICATIONS_DIR/summary_$(date +%Y%m%d).txt"

# ===== Configuração de Apps Críticos =====
CRITICAL_APPS_LIST="$CONFIG_DIR/critical_apps.txt"
if [ ! -f "$CRITICAL_APPS_LIST" ]; then
  echo "$CRITICAL_APPS" | tr ':' '\n' | grep -v '^$' > "$CRITICAL_APPS_LIST"
fi

# ===== Baselines =====
CUR_APPS_FPR="$BASE/apps_fpr.cur.tsv";       LAST_APPS_FPR="$BASE/apps_fpr.last.tsv"
CUR_APPS_PATHS="$BASE/apps_paths.cur.txt";   LAST_APPS_PATHS="$BASE/apps_paths.last.txt"
CUR_CRITICAL_APPS="$BASE/critical_apps.cur.tsv"; LAST_CRITICAL_APPS="$BASE/critical_apps.last.tsv"

CUR_EXT="$BASE/current_extensions.txt";      LAST_EXT="$BASE/last_extensions.txt"
CUR_PROF="$BASE/current_profiles.txt";       LAST_PROF="$BASE/last_profiles.txt"

CUR_LD_SYS="$BASE/current_launchdaemons.txt";    LAST_LD_SYS="$BASE/last_launchdaemons.txt"
CUR_LA_SYS="$BASE/current_launchagents_sys.txt"; LAST_LA_SYS="$BASE/last_launchagents_sys.txt"
CUR_LA_USR="$BASE/current_launchagents_usr.txt"; LAST_LA_USR="$BASE/last_launchagents_usr.txt"

CUR_HELPERS="$BASE/current_helpers.txt";     LAST_HELPERS="$BASE/last_helpers.txt"
CUR_SSH_SUDO="$BASE/current_ssh_sudo.txt";   LAST_SSH_SUDO="$BASE/last_ssh_sudo.txt"
CUR_SYSCFG="$BASE/current_syscfg.txt";       LAST_SYSCFG="$BASE/last_syscfg.txt"
CUR_HOSTS="$BASE/current_hosts.txt";         LAST_HOSTS="$BASE/last_hosts.txt"
CUR_FW="$BASE/current_firewall.txt";         LAST_FW="$BASE/last_firewall.txt"
CUR_PKGS="$BASE/current_pkgs.txt";           LAST_PKGS="$BASE/last_pkgs.txt"
CUR_BREW="$BASE/current_brew.txt";           LAST_BREW="$BASE/last_brew.txt"
CUR_LOGIN="$BASE/current_login.txt";         LAST_LOGIN="$BASE/last_login.txt"

# ===== Sistema de Log Rotativo =====
rotate_logs() {
  local log_file="$1"
  local max_size_mb="$2"
  local keep_count="$3"
  
  if [ ! -f "$log_file" ]; then
    return 0
  fi
  
  # Verifica tamanho do log em MB
  local size_mb=$(($(stat -f%z "$log_file" 2>/dev/null || echo 0) / 1048576))
  
  if [ "$size_mb" -gt "$max_size_mb" ]; then
    # Compacta e rotaciona
    gzip -c "$log_file" > "${log_file}.$(date +%Y%m%d_%H%M%S).gz" 2>/dev/null || true
    > "$log_file"  # Limpa o log atual
    
    # Remove logs antigos, mantendo apenas os mais recentes
    find "$(dirname "$log_file")" -name "$(basename "$log_file").*.gz" -type f \
      | sort -r | tail -n +$((keep_count + 1)) \
      | xargs rm -f 2>/dev/null || true
  fi
}

# ===== Utilitários Avançados =====
log() {
  local level="${1:-INFO}"
  shift
  local message="$*"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" >/dev/null
  
  # Log crítico separado
  if [ "$level" = "CRITICAL" ]; then
    echo "[$timestamp] $message" >> "$CRITICAL_LOG"
  fi
  
  # Summary log para mudanças importantes
  if [ "$level" = "CHANGE" ] || [ "$level" = "CRITICAL" ]; then
    echo "[$timestamp] [$level] $message" >> "$SUMMARY_LOG"
  fi
}

# Sistema de notificações inteligentes
queue_notification() {
  local priority="$1"  # CRITICAL, HIGH, MEDIUM, LOW
  local title="$2"
  local message="$3"
  local timestamp="$(date +%s)"
  
  # Cria entrada JSON para a notificação
  local notification_entry="{\"timestamp\":$timestamp,\"priority\":\"$priority\",\"title\":\"$title\",\"message\":\"$message\"}"
  
  if [ "$priority" = "CRITICAL" ]; then
    # Notificação crítica: enviar imediatamente
    send_notification "$title" "$message" "Basso"
    log "CRITICAL" "$title: $message"
  else
    # Adiciona à fila de notificações pendentes
    echo "$notification_entry" >> "$PENDING_NOTIFICATIONS_FILE"
  fi
}

send_notification() {
  local title="$1"
  local message="$2"
  local sound="${3:-Glass}"
  
  /usr/bin/osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

# Processa notificações agrupadas
process_pending_notifications() {
  if [ ! -f "$PENDING_NOTIFICATIONS_FILE" ] || [ ! -s "$PENDING_NOTIFICATIONS_FILE" ]; then
    return 0
  fi
  
  local last_notification_time=0
  [ -f "$LAST_NOTIFICATION_FILE" ] && last_notification_time=$(cat "$LAST_NOTIFICATION_FILE" 2>/dev/null || echo 0)
  
  local current_time=$(date +%s)
  local time_diff=$(((current_time - last_notification_time) / 3600))  # Diferença em horas
  
  if [ "$time_diff" -ge "$NOTIFICATION_FREQUENCY" ] || [ "$ENABLE_GROUPED_NOTIFICATIONS" != "true" ]; then
    # Conta notificações por prioridade
    local high_count=$(grep '"priority":"HIGH"' "$PENDING_NOTIFICATIONS_FILE" | wc -l | tr -d ' ')
    local medium_count=$(grep '"priority":"MEDIUM"' "$PENDING_NOTIFICATIONS_FILE" | wc -l | tr -d ' ')
    local low_count=$(grep '"priority":"LOW"' "$PENDING_NOTIFICATIONS_FILE" | wc -l | tr -d ' ')
    local total=$((high_count + medium_count + low_count))
    
    if [ "$total" -gt 0 ]; then
      local summary="Monitor: $total mudanças"
      [ "$high_count" -gt 0 ] && summary="$summary (${high_count} importantes)"
      
      send_notification "Monitor de Segurança" "$summary"
      
      # Salva resumo detalhado
      {
        echo "=== Resumo de Notificações - $(date) ==="
        echo "Total de mudanças: $total"
        echo "Alta prioridade: $high_count"
        echo "Média prioridade: $medium_count"
        echo "Baixa prioridade: $low_count"
        echo ""
        echo "Detalhes:"
        cat "$PENDING_NOTIFICATIONS_FILE"
        echo "========================="
      } >> "$NOTIFICATION_SUMMARY_FILE"
      
      # Limpa notificações processadas e atualiza timestamp
      > "$PENDING_NOTIFICATIONS_FILE"
      echo "$current_time" > "$LAST_NOTIFICATION_FILE"
    fi
  fi
}

# Normaliza inteiro: remove tudo que não for dígito; vazio -> 0
to_int() {
  local val="$(printf '%s' "${1:-0}" | tr -cd '0-9')"
  [ -z "$val" ] && val="0"
  echo "$val"
}

# Cache inteligente para hash de arquivos
hash_file_cached() {
  local f="$1"
  local cache_file="$CACHE_DIR/$(echo "$f" | /usr/bin/shasum -a 256 | cut -d' ' -f1).cache"
  
  if [ -f "$cache_file" ]; then
    local cache_mtime=$(stat -f "%m" "$cache_file" 2>/dev/null || echo 0)
    local file_mtime=$(stat -f "%m" "$f" 2>/dev/null || echo 0)
    
    if [ "$file_mtime" -le "$cache_mtime" ]; then
      cat "$cache_file" 2>/dev/null && return 0
    fi
  fi
  
  local hash_result
  if hash_result=$(/usr/bin/shasum -a 256 "$f" 2>/dev/null); then
    echo "$hash_result" | tee "$cache_file"
  elif hash_result=$(/usr/bin/sudo -n /usr/bin/shasum -a 256 "$f" 2>/dev/null); then
    echo "$hash_result" | tee "$cache_file"
  else
    echo "NOACCESS  $f"
  fi
}

# Função otimizada para diff e log com níveis de prioridade
diff_and_log() {
  local last="$1" cur="$2" tag="$3" npfx="$4" priority="${5:-MEDIUM}"
  
  if [ -z "${last:-}" ] || [ -z "${cur:-}" ] || [ -z "${tag:-}" ] || [ -z "${npfx:-}" ]; then
    log "WARN" "diff_and_log chamado com args vazios"
    return 0
  fi
  
  if [[ -f "$last" ]]; then
    if ! /usr/bin/diff -u "$last" "$cur" > "$BASE/temp.diff" 2>/dev/null; then
      local added removed
      added=$(grep -c '^+[^+]' "$BASE/temp.diff" 2>/dev/null || echo 0)
      removed=$(grep -c '^-[^-]' "$BASE/temp.diff" 2>/dev/null || echo 0)
      
      added="$(to_int "$added")"
      removed="$(to_int "$removed")"
      local delta=$((added + removed))
      
      log "CHANGE" "${tag}: +${added} -${removed} (linhas: ${delta})"
      log "INFO" "----- DIFF BEGIN (${tag}) -----"
      cat "$BASE/temp.diff" >> "$LOG_FILE"
      log "INFO" "------ DIFF END (${tag}) ------"
      
      # Determina prioridade baseada no tipo de mudança
      if echo "$tag" | grep -qi "critical\|helper\|launch\|sudo"; then
        priority="HIGH"
      elif [ "$delta" -gt 10 ]; then
        priority="HIGH"
      fi
      
      queue_notification "$priority" "Monitor: $npfx" "+${added} -${removed}"
      /bin/rm -f "$BASE/temp.diff" 2>/dev/null || true
    else
      log "INFO" "Sem mudanças em ${tag}"
    fi
  else
    log "INIT" "Baseline de ${tag} criada"
  fi
  /bin/cp -f "$cur" "$last"
}

# ===== Detecção Automática de Apps Críticos =====
detect_critical_apps() {
  local critical_patterns="security|antivirus|firewall|privacy|malware|block|snitch|lulu|knockknock|ransom|clamxav"
  
  # Atualiza lista de apps críticos baseada em padrões conhecidos
  /usr/bin/find /Applications -maxdepth 2 -type d -name "*.app" -print 2>/dev/null | while IFS= read -r app; do
    if echo "$app" | grep -iE "$critical_patterns" >/dev/null 2>&1; then
      echo "$app"
    elif [ -f "$app/Contents/Info.plist" ]; then
      local bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || echo "")
      if echo "$bundle_id" | grep -iE "$critical_patterns" >/dev/null 2>&1; then
        echo "$app"
      fi
    fi
  done | sort -u >> "$CRITICAL_APPS_LIST.new"
  
  # Merge com apps críticos existentes
  if [ -f "$CRITICAL_APPS_LIST.new" ]; then
    cat "$CRITICAL_APPS_LIST" "$CRITICAL_APPS_LIST.new" 2>/dev/null | sort -u > "$CRITICAL_APPS_LIST.tmp"
    mv "$CRITICAL_APPS_LIST.tmp" "$CRITICAL_APPS_LIST"
    rm -f "$CRITICAL_APPS_LIST.new" 2>/dev/null || true
  fi
}

# ===== Fingerprint Otimizado para Apps Críticos =====
app_fingerprint_critical() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  local bid="" short="" build="" team="" hash=""
  
  if [ -f "$plist" ]; then
    # Para apps críticos, sempre recalcula (sem cache agressivo)
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || echo "")
    short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo "")
    build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo "")
    
    if /usr/bin/which codesign >/dev/null 2>&1; then
      team=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/awk -F= '/TeamIdentifier=/{print $2; exit}' || echo "")
    fi
    
    hash=$(/usr/bin/plutil -convert xml1 -o - "$plist" 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
  fi
  
  echo -e "${app}\t${bid}\t${short}\t${build}\t${team}\t${hash}"
}

app_fingerprint_optimized() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  local bid="" short="" build="" team="" hash=""
  
  if [ -f "$plist" ]; then
    local plist_cache="$CACHE_DIR/$(echo "$plist" | /usr/bin/shasum -a 256 | cut -d' ' -f1).plist_data"
    local plist_mtime=$(stat -f "%m" "$plist" 2>/dev/null || echo 0)
    local cache_mtime=0
    
    if [ -f "$plist_cache" ]; then
      cache_mtime=$(stat -f "%m" "$plist_cache" 2>/dev/null || echo 0)
    fi
    
    if [ "$plist_mtime" -le "$cache_mtime" ]; then
      cat "$plist_cache" 2>/dev/null && return 0
    fi
    
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || echo "")
    short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo "")
    build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo "")
    
    local team_cache="$CACHE_DIR/$(echo "$app" | /usr/bin/shasum -a 256 | cut -d' ' -f1).team"
    if [ -f "$team_cache" ]; then
      team=$(cat "$team_cache" 2>/dev/null || echo "")
    elif /usr/bin/which codesign >/dev/null 2>&1; then
      team=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/awk -F= '/TeamIdentifier=/{print $2; exit}' || echo "")
      echo "$team" > "$team_cache" 2>/dev/null || true
    fi
    
    hash=$(/usr/bin/plutil -convert xml1 -o - "$plist" 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
    
    local result="${app}\t${bid}\t${short}\t${build}\t${team}\t${hash}"
    echo -e "$result" | tee "$plist_cache" >/dev/null 2>&1 || echo -e "$result"
  else
    echo -e "${app}\t\t\t\t\t"
  fi
}

# ===== Verificação de Apps Críticos =====
check_critical_applications() {
  log "INFO" "Verificando aplicações críticas"
  : > "$CUR_CRITICAL_APPS"
  
  if [ -f "$CRITICAL_APPS_LIST" ]; then
    while IFS= read -r app; do
      [ -z "$app" ] || [ ! -d "$app" ] && continue
      app_fingerprint_critical "$app" >> "$CUR_CRITICAL_APPS"
    done < "$CRITICAL_APPS_LIST"
  fi
  
  if [[ -f "$LAST_CRITICAL_APPS" ]]; then
    diff_and_log "$LAST_CRITICAL_APPS" "$CUR_CRITICAL_APPS" "Aplicações Críticas" "Apps Críticos" "CRITICAL"
  else
    log "INIT" "Baseline de aplicações críticas criada"
    /bin/cp -f "$CUR_CRITICAL_APPS" "$LAST_CRITICAL_APPS"
  fi
}

# ===== Verificação Completa de Aplicações =====
build_apps_fingerprint_optimized() {
  : > "$CUR_APPS_FPR"
  
  if [ "$MONITOR_MODE" = "quick" ]; then
    # Modo rápido: apenas apps críticos + alguns diretórios principais
    if [ -f "$CRITICAL_APPS_LIST" ]; then
      while IFS= read -r app; do
        [ -z "$app" ] || [ ! -d "$app" ] && continue
        app_fingerprint_optimized "$app" || true
      done < "$CRITICAL_APPS_LIST" >> "$CUR_APPS_FPR"
    fi
    
    # Adiciona apenas apps principais em /Applications (nível 1)
    /usr/bin/find /Applications -maxdepth 1 -type d -name "*.app" -print 2>/dev/null \
      | head -20 | while IFS= read -r app; do
        app_fingerprint_optimized "$app" || true
      done >> "$CUR_APPS_FPR"
  else
    # Modo normal/full
    local max_depth=2
    [ "$MONITOR_MODE" = "full" ] && max_depth=3
    
    /usr/bin/find /Applications -xdev -maxdepth $max_depth -type d -name "*.app" -print 2>/dev/null \
      | /usr/bin/sort \
      | while IFS= read -r app; do 
          app_fingerprint_optimized "$app" || true
        done >> "$CUR_APPS_FPR"
  fi
  
  /usr/bin/sort -t $'\t' -k1,1 "$CUR_APPS_FPR" -o "$CUR_APPS_FPR" 2>/dev/null || true
  /usr/bin/cut -f1 "$CUR_APPS_FPR" > "$CUR_APPS_PATHS" 2>/dev/null || true
}

check_applications_versions_optimized() {
  log "INFO" "Aplicações (fingerprint otimizado - modo: $MONITOR_MODE)"
  build_apps_fingerprint_optimized
  
  if [[ ! -f "$LAST_APPS_FPR" || ! -f "$LAST_APPS_PATHS" ]]; then
    log "INIT" "Baseline de /Applications criada"
    /bin/cp -f "$CUR_APPS_FPR" "$LAST_APPS_FPR"
    /bin/cp -f "$CUR_APPS_PATHS" "$LAST_APPS_PATHS"
    return 0
  fi
  
  local n_add n_rem n_chg
  
  n_add=$(comm -13 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" 2>/dev/null | wc -l | tr -d ' ')
  n_rem=$(comm -23 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" 2>/dev/null | wc -l | tr -d ' ')
  
  n_add="$(to_int "$n_add")"
  n_rem="$(to_int "$n_rem")"
  
  if [ "$n_add" -gt 0 ]; then
    log "CHANGE" "Aplicações ADICIONADAS ($n_add)"
    queue_notification "HIGH" "Novas Aplicações" "$n_add apps instalados"
  fi
  
  if [ "$n_rem" -gt 0 ]; then
    log "CHANGE" "Aplicações REMOVIDAS ($n_rem)"
    queue_notification "MEDIUM" "Apps Removidos" "$n_rem apps desinstalados"
  fi
  
  n_chg=$(join -t $'\t' -1 1 -2 1 "$LAST_APPS_FPR" "$CUR_APPS_FPR" 2>/dev/null \
    | awk -F'\t' 'BEGIN{count=0} {
        last = $2 FS $3 FS $4 FS $5 FS $6
        cur  = $7 FS $8 FS $9 FS $10 FS $11
        if (last != cur) count++
      } END{print count+0}' 2>/dev/null || echo 0)
      
  n_chg="$(to_int "$n_chg")"
  
  if [ "$n_chg" -gt 0 ]; then
    log "CHANGE" "Aplicações ALTERADAS: $n_chg"
    queue_notification "MEDIUM" "Apps Atualizados" "$n_chg apps modificados"
  fi
  
  /bin/cp -f "$CUR_APPS_FPR" "$LAST_APPS_FPR"
  /bin/cp -f "$CUR_APPS_PATHS" "$LAST_APPS_PATHS"
}

# ===== Outras funções otimizadas (adaptadas para o sistema de modos) =====
hash_plists_dir_optimized() {
  local dir="$1"
  if [ -d "$dir" ]; then
    /usr/bin/find "$dir" -maxdepth 1 -type f -name "*.plist" -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do 
          hash_file_cached "$f"
        done | /usr/bin/sort -k2
  fi
}

check_launch_optimized() {
  log "INFO" "LaunchDaemons/LaunchAgents (otimizado)"
  
  if [ "$MONITOR_MODE" = "quick" ]; then
    # Modo rápido: apenas LaunchDaemons críticos
    hash_plists_dir_optimized "/Library/LaunchDaemons" > "$CUR_LD_SYS" || echo "" > "$CUR_LD_SYS"
    diff_and_log "$LAST_LD_SYS" "$CUR_LD_SYS" "LaunchDaemons" "LaunchDaemons" "HIGH"
  else
    # Modo normal/completo
    {
      hash_plists_dir_optimized "/Library/LaunchDaemons" > "$CUR_LD_SYS" 2>/dev/null || echo "" > "$CUR_LD_SYS"
    } &
    
    {
      hash_plists_dir_optimized "/Library/LaunchAgents" > "$CUR_LA_SYS" 2>/dev/null || echo "" > "$CUR_LA_SYS"
    } &
    
    {
      hash_plists_dir_optimized "${HOME:-/var/root}/Library/LaunchAgents" > "$CUR_LA_USR" 2>/dev/null || echo "" > "$CUR_LA_USR"
    } &
    
    wait
    
    diff_and_log "$LAST_LD_SYS" "$CUR_LD_SYS" "LaunchDaemons" "LaunchDaemons" "HIGH"
    diff_and_log "$LAST_LA_SYS" "$CUR_LA_SYS" "LaunchAgents (sistema)" "LaunchAgents (sys)" "HIGH"
    diff_and_log "$LAST_LA_USR" "$CUR_LA_USR" "LaunchAgents (usuário)" "LaunchAgents (usr)" "MEDIUM"
  fi
}

check_helpers_optimized() {
  log "INFO" "PrivilegedHelperTools"
  if [ -d "/Library/PrivilegedHelperTools" ]; then
    /usr/bin/find /Library/PrivilegedHelperTools -maxdepth 1 -type f -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do hash_file_cached "$f"; done \
      | /usr/bin/sort -k2 > "$CUR_HELPERS"
  else 
    : > "$CUR_HELPERS"
  fi
  diff_and_log "$LAST_HELPERS" "$CUR_HELPERS" "PrivilegedHelperTools" "Helpers" "HIGH"
}

check_system_extensions_optimized() {
  log "INFO" "System Extensions"
  /usr/bin/systemextensionsctl list 2>/dev/null | /usr/bin/sed '/^[[:space:]]*$/d' | /usr/bin/sort > "$CUR_EXT" || echo "" > "$CUR_EXT"
  diff_and_log "$LAST_EXT" "$CUR_EXT" "System Extensions" "Extensions" "HIGH"
}

check_profiles_optimized() { 
  if [ "$MONITOR_MODE" = "quick" ]; then
    return 0  # Skip em modo rápido
  fi
  
  log "INFO" "Perfis (MDM/Configuration)"
  local profile_cache="$CACHE_DIR/profiles.cache"
  local cache_age=$(($(date +%s) - $(stat -f "%m" "$profile_cache" 2>/dev/null || echo 0)))
  
  if [ -f "$profile_cache" ] && [ "$cache_age" -lt 300 ]; then
    cp "$profile_cache" "$CUR_PROF"
  else
    if /usr/bin/profiles -P -o "$BASE/profiles_tmp.xml" >/dev/null 2>&1; then
      /usr/bin/plutil -convert json -o "$CUR_PROF" "$BASE/profiles_tmp.xml" 2>/dev/null || \
      /usr/bin/profiles list -type configuration 2>/dev/null | /usr/bin/sort > "$CUR_PROF"
    else
      /usr/bin/profiles list -type configuration 2>/dev/null | /usr/bin/sort > "$CUR_PROF"
    fi
    cp "$CUR_PROF" "$profile_cache" 2>/dev/null || true
    /bin/rm -f "$BASE/profiles_tmp.xml" 2>/dev/null || true
  fi
  
  diff_and_log "$LAST_PROF" "$CUR_PROF" "Profiles (MDM)" "Profiles" "HIGH"
}

check_ssh_sudo_optimized() {
  log "INFO" "Sudoers/SSH"
  : > "$CUR_SSH_SUDO"
  
  {
    for f in /etc/sudoers /etc/ssh/sshd_config; do 
      [ -f "$f" ] && hash_file_cached "$f"
    done
  } >> "$CUR_SSH_SUDO" &
  
  {
    if [ -d /etc/sudoers.d ]; then
      /usr/bin/find /etc/sudoers.d -maxdepth 1 -type f -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do hash_file_cached "$f"; done
    fi
  } >> "$CUR_SSH_SUDO" &
  
  {
    [ -f "${HOME:-/var/root}/.ssh/authorized_keys" ] && \
      hash_file_cached "${HOME:-/var/root}/.ssh/authorized_keys"
  } >> "$CUR_SSH_SUDO" &
  
  wait
  /usr/bin/sort -k2 "$CUR_SSH_SUDO" -o "$CUR_SSH_SUDO" 2>/dev/null || true
  diff_and_log "$LAST_SSH_SUDO" "$CUR_SSH_SUDO" "Sudoers/SSH" "SSH/Sudo" "HIGH"
}

# Funções rápidas para modo quick
check_syscfg_hosts_optimized() {
  if [ "$MONITOR_MODE" = "quick" ]; then
    # Modo rápido: apenas /etc/hosts
    [ -f /etc/hosts ] && /usr/bin/shasum -a 256 /etc/hosts > "$CUR_HOSTS" || : > "$CUR_HOSTS"
    diff_and_log "$LAST_HOSTS" "$CUR_HOSTS" "/etc/hosts" "hosts" "MEDIUM"
    return 0
  fi
  
  log "INFO" "SystemConfiguration + /etc/hosts"
  : > "$CUR_SYSCFG"
  
  for plist in "/Library/Preferences/SystemConfiguration/preferences.plist" \
              "/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist" \
              "/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist" \
              "/Library/Preferences/SystemConfiguration/com.apple.proxy.plist"; do
    if [ -f "$plist" ]; then
      echo "### $plist" >> "$CUR_SYSCFG"
      /usr/bin/plutil -convert json -o - "$plist" 2>/dev/null >> "$CUR_SYSCFG" || true
      echo "" >> "$CUR_SYSCFG"
    fi
  done
  
  diff_and_log "$LAST_SYSCFG" "$CUR_SYSCFG" "SystemConfiguration" "SysCfg" "MEDIUM"
  
  [ -f /etc/hosts ] && /usr/bin/shasum -a 256 /etc/hosts > "$CUR_HOSTS" || : > "$CUR_HOSTS"
  diff_and_log "$LAST_HOSTS" "$CUR_HOSTS" "/etc/hosts" "hosts" "MEDIUM"
}

check_firewall_optimized() {
  if [ "$MONITOR_MODE" = "quick" ]; then
    return 0  # Skip em modo rápido
  fi
  
  log "INFO" "Firewall apps"
  /usr/libexec/ApplicationFirewall/socketfilterfw --listapps 2>/dev/null | /usr/bin/sort > "$CUR_FW" || echo "" > "$CUR_FW"
  diff_and_log "$LAST_FW" "$CUR_FW" "Firewall" "Firewall" "MEDIUM"
}

check_pkgs_optimized() {
  if [ "$MONITOR_MODE" = "quick" ]; then
    return 0  # Skip em modo rápido
  fi
  
  log "INFO" "Pacotes (pkgutil/Homebrew)"
  
  {
    /usr/sbin/pkgutil --pkgs 2>/dev/null | /usr/bin/sort > "$CUR_PKGS" || echo "" > "$CUR_PKGS"
  } &
  
  {
    local BREW_BIN=""
    [ -x /opt/homebrew/bin/brew ] && BREW_BIN="/opt/homebrew/bin/brew"
    [ -z "$BREW_BIN" ] && [ -x /usr/local/bin/brew ] && BREW_BIN="/usr/local/bin/brew"
    
    if [ -n "$BREW_BIN" ]; then
      "$BREW_BIN" list --versions 2>/dev/null | /usr/bin/sort > "$CUR_BREW" || echo "" > "$CUR_BREW"
    else
      echo "" > "$CUR_BREW"
    fi
  } &
  
  wait
  
  diff_and_log "$LAST_PKGS" "$CUR_PKGS" "Pacotes" "Pacotes" "LOW"
  [ -s "$CUR_BREW" ] && diff_and_log "$LAST_BREW" "$CUR_BREW" "Homebrew" "Homebrew" "LOW"
}

check_login_items_optimized() {
  if [ "$MONITOR_MODE" = "quick" ]; then
    return 0  # Skip em modo rápido
  fi
  
  log "INFO" "Login Items"
  /usr/bin/osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | /usr/bin/tr ',' '\n' | /usr/bin/sed 's/^ *//; s/ *$//' | /usr/bin/sort > "$CUR_LOGIN" || echo "" > "$CUR_LOGIN"
  diff_and_log "$LAST_LOGIN" "$CUR_LOGIN" "Login Items" "LoginItems" "MEDIUM"
}

# Limpeza de cache e logs
cleanup_cache_and_logs() {
  # Remove cache mais antigo que 7 dias
  if [ -d "$CACHE_DIR" ]; then
    /usr/bin/find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
  fi
  
  # Rotaciona logs principais
  rotate_logs "$LOG_FILE" "$LOG_MAX_SIZE_MB" "$LOG_ROTATION_COUNT"
  rotate_logs "$SUMMARY_LOG" "$LOG_MAX_SIZE_MB" "$LOG_ROTATION_COUNT"
  rotate_logs "$CRITICAL_LOG" 10 3  # Critical log menor
  
  # Remove notificações antigas
  /usr/bin/find "$NOTIFICATIONS_DIR" -name "summary_*.txt" -mtime +30 -delete 2>/dev/null || true
}

# Relatório de status
generate_status_report() {
  local report_file="$LOGS_DIR/status_$(date +%Y%m%d_%H%M).txt"
  
  {
    echo "=== Monitor de Instalações - Status Report ==="
    echo "Data: $(date)"
    echo "Modo: $MONITOR_MODE"
    echo "Frequência de notificação: $NOTIFICATION_FREQUENCY horas"
    echo "Notificações agrupadas: $ENABLE_GROUPED_NOTIFICATIONS"
    echo ""
    echo "Estatísticas:"
    echo "- Apps críticos monitorados: $(wc -l < "$CRITICAL_APPS_LIST" 2>/dev/null || echo 0)"
    echo "- Tamanho do cache: $(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0B")"
    echo "- Tamanho dos logs: $(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1 || echo "0B")"
    echo ""
    echo "Últimas mudanças críticas:"
    tail -10 "$CRITICAL_LOG" 2>/dev/null || echo "Nenhuma mudança crítica registrada"
    echo ""
    echo "Resumo das últimas 24h:"
    grep "$(date -v-1d '+%Y-%m-%d')" "$SUMMARY_LOG" 2>/dev/null | wc -l | xargs echo "- Mudanças detectadas:"
  } > "$report_file"
  
  # Mantém apenas os últimos 10 relatórios
  /usr/bin/find "$LOGS_DIR" -name "status_*.txt" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
}

# ===== Execução Principal =====
main() {
  log "INFO" "=== Monitor iniciado - Modo: $MONITOR_MODE ==="
  
  # Rotação de logs e limpeza
  cleanup_cache_and_logs
  
  # Detecta apps críticos automaticamente
  detect_critical_apps
  
  # Processa notificações pendentes
  process_pending_notifications
  
  # Guard de bateria
  if /usr/bin/pmset -g batt 2>/dev/null | /usr/bin/grep -qi "discharging"; then
    pct=$(/usr/bin/pmset -g batt | /usr/bin/awk -F';|%' '/InternalBattery|Battery Power/ {gsub(/ /,""); print $2; exit}')
    pct="$(to_int "$pct")"
    if [ "$pct" -lt 30 ]; then
      log "INFO" "Bateria em ${pct}% - Modo de economia ativado"
      MONITOR_MODE="quick"
    fi
  fi
  
  # Executa verificações baseadas no modo
  case "$MONITOR_MODE" in
    "quick")
      log "INFO" "Modo rápido: verificações essenciais apenas"
      check_critical_applications &
      check_launch_optimized &
      check_helpers_optimized &
      wait
      check_syscfg_hosts_optimized
      ;;
    "normal")
      log "INFO" "Modo normal: verificação completa padrão"
      check_critical_applications &
      check_applications_versions_optimized &
      check_launch_optimized &
      check_helpers_optimized &
      check_system_extensions_optimized &
      wait
      check_ssh_sudo_optimized
      check_syscfg_hosts_optimized
      check_firewall_optimized
      check_login_items_optimized
      ;;
    "full")
      log "INFO" "Modo completo: verificação profunda"
      check_critical_applications &
      check_applications_versions_optimized &
      check_launch_optimized &
      check_helpers_optimized &
      check_system_extensions_optimized &
      check_profiles_optimized &
      wait
      check_ssh_sudo_optimized
      check_syscfg_hosts_optimized
      check_firewall_optimized
      check_pkgs_optimized
      check_login_items_optimized
      generate_status_report &
      ;;
  esac
  
  # Processa notificações finais
  process_pending_notifications
  
  log "INFO" "=== Monitor finalizado - $(date) ==="
}

# Execução
main "$@"