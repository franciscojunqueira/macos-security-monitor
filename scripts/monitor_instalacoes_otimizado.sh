#!/bin/bash
# Monitor de mudanças críticas no macOS (VERSÃO OTIMIZADA)
# Apps: monitora por fingerprint do Info.plist (BundleID, ShortVersion, Build, TeamID, hash do Info.plist)
set -euo pipefail

# ===== Ambiente "duro" (HOME pode não existir em LaunchDaemon) =====
if [ -z "${HOME:-}" ] || [ ! -d "${HOME:-/var/root}" ]; then
  U="$(/usr/bin/id -un 2>/dev/null || echo root)"
  H="$(/usr/bin/dscl . -read /Users/$U NFSHomeDirectory 2>/dev/null | /usr/bin/awk -F': ' '{print $2}')"
  HOME="${H:-/var/root}"
fi
export LC_ALL=C
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# ===== Config =====
LOG_FILE="${LOG_FILE:-${HOME:-/var/root}/Desktop/instalacoes_log.txt}"

# Estado persistente (não usar /tmp)
if [ "$(/usr/bin/id -u)" -eq 0 ]; then
  BASE="/var/db/monitor_instalacoes"
else
  BASE="${HOME:-/var/root}/Library/Application Support/monitor_instalacoes"
fi
/bin/mkdir -p "$BASE"

# Cache para otimização
CACHE_DIR="$BASE/cache"
/bin/mkdir -p "$CACHE_DIR"

# ===== Baselines =====
CUR_APPS_FPR="$BASE/apps_fpr.cur.tsv";       LAST_APPS_FPR="$BASE/apps_fpr.last.tsv"
CUR_APPS_PATHS="$BASE/apps_paths.cur.txt";   LAST_APPS_PATHS="$BASE/apps_paths.last.txt"

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

echo "=== MONITORAMENTO INICIADO (OTIMIZADO) ===" >> "$LOG_FILE"
echo "Data: $(date)" >> "$LOG_FILE"
echo "=============================" >> "$LOG_FILE"

# ===== Utilitários Otimizados =====
notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" 2>/dev/null || true; }
log()    { echo "$*" >> "$LOG_FILE"; }

# Normaliza inteiro: remove tudo que não for dígito; vazio -> 0 (CORRIGIDO)
to_int() {
  local val="$(printf '%s' "${1:-0}" | tr -cd '0-9')"
  [ -z "$val" ] && val="0"
  echo "$val"
}

# Cache inteligente para hash de arquivos
hash_file_cached() {
  local f="$1"
  local cache_file="$CACHE_DIR/$(echo "$f" | /usr/bin/shasum -a 256 | cut -d' ' -f1).cache"
  
  # Verifica se existe cache válido (baseado na data de modificação)
  if [ -f "$cache_file" ]; then
    local cache_mtime=$(stat -f "%m" "$cache_file" 2>/dev/null || echo 0)
    local file_mtime=$(stat -f "%m" "$f" 2>/dev/null || echo 0)
    
    if [ "$file_mtime" -le "$cache_mtime" ]; then
      cat "$cache_file" 2>/dev/null && return 0
    fi
  fi
  
  # Calcula hash e salva no cache
  local hash_result
  if hash_result=$(/usr/bin/shasum -a 256 "$f" 2>/dev/null); then
    echo "$hash_result" | tee "$cache_file"
  elif hash_result=$(/usr/bin/sudo -n /usr/bin/shasum -a 256 "$f" 2>/dev/null); then
    echo "$hash_result" | tee "$cache_file"
  else
    echo "NOACCESS  $f"
  fi
}

# Função otimizada para diff e log (streaming)
diff_and_log() {
  local last="$1" cur="$2" tag="$3" npfx="$4"
  
  if [ -z "${last:-}" ] || [ -z "${cur:-}" ] || [ -z "${tag:-}" ] || [ -z "${npfx:-}" ]; then
    log "[WARN] diff_and_log chamado com args vazios"
    return 0
  fi
  
  if [[ -f "$last" ]]; then
    if ! /usr/bin/diff -u "$last" "$cur" > "$BASE/temp.diff" 2>/dev/null; then
      # Conta linhas de diferença usando streaming (menos memória)
      local added removed
      added=$(grep -c '^+[^+]' "$BASE/temp.diff" 2>/dev/null || echo 0)
      removed=$(grep -c '^-[^-]' "$BASE/temp.diff" 2>/dev/null || echo 0)
      
      added="$(to_int "$added")"
      removed="$(to_int "$removed")"
      local delta=$((added + removed))
      
      log "[CHANGE] ${tag}: +${added} -${removed} (linhas: ${delta})"
      log "----- DIFF BEGIN (${tag}) -----"
      cat "$BASE/temp.diff" >> "$LOG_FILE"
      log "------ DIFF END (${tag}) ------"
      notify "Monitor de Segurança" "${npfx}: +${added} -${removed}"
      
      /bin/rm -f "$BASE/temp.diff" 2>/dev/null || true
    else
      log "Sem mudanças em ${tag}"
    fi
  else
    log "[INIT] Baseline de ${tag} criada"
  fi
  /bin/cp -f "$cur" "$last"
}

# ===== 1) Aplicações (/Applications) por versão (fingerprint) OTIMIZADO =====
app_fingerprint_optimized() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  local bid="" short="" build="" team="" hash=""
  
  if [ -f "$plist" ]; then
    # Usa cache para Info.plist se não mudou
    local plist_cache="$CACHE_DIR/$(echo "$plist" | /usr/bin/shasum -a 256 | cut -d' ' -f1).plist_data"
    local plist_mtime=$(stat -f "%m" "$plist" 2>/dev/null || echo 0)
    local cache_mtime=0
    
    if [ -f "$plist_cache" ]; then
      cache_mtime=$(stat -f "%m" "$plist_cache" 2>/dev/null || echo 0)
    fi
    
    if [ "$plist_mtime" -le "$cache_mtime" ]; then
      # Usa cache
      cat "$plist_cache" 2>/dev/null && return 0
    fi
    
    # Calcula dados do plist
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || echo "")
    short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo "")
    build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo "")
    
    # TeamID é custoso - cache separado ou skip se não mudou
    local team_cache="$CACHE_DIR/$(echo "$app" | /usr/bin/shasum -a 256 | cut -d' ' -f1).team"
    if [ -f "$team_cache" ]; then
      team=$(cat "$team_cache" 2>/dev/null || echo "")
    elif /usr/bin/which codesign >/dev/null 2>&1; then
      team=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/awk -F= '/TeamIdentifier=/{print $2; exit}' || echo "")
      echo "$team" > "$team_cache" 2>/dev/null || true
    fi
    
    hash=$(/usr/bin/plutil -convert xml1 -o - "$plist" 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
    
    # Salva no cache
    local result="${app}\t${bid}\t${short}\t${build}\t${team}\t${hash}"
    echo -e "$result" | tee "$plist_cache" >/dev/null 2>&1 || echo -e "$result"
  else
    echo -e "${app}\t\t\t\t\t"
  fi
}

build_apps_fingerprint_optimized() {
  : > "$CUR_APPS_FPR"
  
  # Usa find mais eficiente com limits
  /usr/bin/find /Applications -xdev -maxdepth 2 -type d -name "*.app" -print 2>/dev/null \
    | /usr/bin/sort \
    | while IFS= read -r app; do 
        app_fingerprint_optimized "$app" || true
      done >> "$CUR_APPS_FPR"
      
  /usr/bin/sort -t $'\t' -k1,1 "$CUR_APPS_FPR" -o "$CUR_APPS_FPR"
  /usr/bin/cut -f1 "$CUR_APPS_FPR" > "$CUR_APPS_PATHS"
}

check_applications_versions_optimized() {
  log "[CHECK] Aplicações (fingerprint otimizado)"
  build_apps_fingerprint_optimized
  
  if [[ ! -f "$LAST_APPS_FPR" || ! -f "$LAST_APPS_PATHS" ]]; then
    log "[INIT] Baseline de /Applications (fingerprint) criada"
    /bin/cp -f "$CUR_APPS_FPR" "$LAST_APPS_FPR"
    /bin/cp -f "$CUR_APPS_PATHS" "$LAST_APPS_PATHS"
    return 0
  fi
  
  # Processamento streaming para economizar memória
  local n_add n_rem n_chg=0
  
  # Apps adicionados/removidos
  n_add=$(comm -13 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" | wc -l | tr -d ' ')
  n_rem=$(comm -23 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" | wc -l | tr -d ' ')
  
  n_add="$(to_int "$n_add")"
  n_rem="$(to_int "$n_rem")"
  
  if [ "$n_add" -gt 0 ]; then
    log "[CHANGE] Aplicações ADICIONADAS ($n_add):"
    comm -13 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" >> "$LOG_FILE"
  fi
  
  if [ "$n_rem" -gt 0 ]; then
    log "[CHANGE] Aplicações REMOVIDAS ($n_rem):"
    comm -23 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" >> "$LOG_FILE"
  fi
  
  # Apps alterados (usando processamento mais eficiente)
  n_chg=$(join -t $'\t' -1 1 -2 1 "$LAST_APPS_FPR" "$CUR_APPS_FPR" 2>/dev/null \
    | awk -F'\t' 'BEGIN{count=0} {
        last = $2 FS $3 FS $4 FS $5 FS $6
        cur  = $7 FS $8 FS $9 FS $10 FS $11
        if (last != cur) count++
      } END{print count+0}' || echo 0)
      
  n_chg="$(to_int "$n_chg")"
  
  if [ "$n_chg" -gt 0 ]; then
    log "[CHANGE] Aplicações ALTERADAS (versão/fingerprint): $n_chg"
  fi
  
  if [ "$n_add" -gt 0 ] || [ "$n_rem" -gt 0 ] || [ "$n_chg" -gt 0 ]; then
    notify "Monitor de Segurança" "Apps: +${n_add} -${n_rem} ~${n_chg}"
  fi
  
  /bin/cp -f "$CUR_APPS_FPR" "$LAST_APPS_FPR"
  /bin/cp -f "$CUR_APPS_PATHS" "$LAST_APPS_PATHS"
}

# ===== 2) LaunchDaemons/LaunchAgents otimizado =====
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
  log "[CHECK] LaunchDaemons/LaunchAgents (otimizado)"
  
  # Execução paralela usando background jobs (limitada para não sobrecarregar)
  {
    hash_plists_dir_optimized "/Library/LaunchDaemons" > "$CUR_LD_SYS" 2>/dev/null || echo "" > "$CUR_LD_SYS"
  } &
  
  {
    hash_plists_dir_optimized "/Library/LaunchAgents" > "$CUR_LA_SYS" 2>/dev/null || echo "" > "$CUR_LA_SYS"
  } &
  
  {
    hash_plists_dir_optimized "${HOME:-/var/root}/Library/LaunchAgents" > "$CUR_LA_USR" 2>/dev/null || echo "" > "$CUR_LA_USR"
  } &
  
  # Aguarda todos os jobs
  wait
  
  diff_and_log "$LAST_LD_SYS" "$CUR_LD_SYS" "LaunchDaemons (/Library)" "LaunchDaemons"
  diff_and_log "$LAST_LA_SYS" "$CUR_LA_SYS" "LaunchAgents (sistema)" "LaunchAgents (sys)"
  diff_and_log "$LAST_LA_USR" "$CUR_LA_USR" "LaunchAgents (usuário)" "LaunchAgents (usr)"
}

# ===== Funções restantes otimizadas =====
check_helpers_optimized() {
  log "[CHECK] PrivilegedHelperTools (otimizado)"
  if [ -d "/Library/PrivilegedHelperTools" ]; then
    /usr/bin/find /Library/PrivilegedHelperTools -maxdepth 1 -type f -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do hash_file_cached "$f"; done \
      | /usr/bin/sort -k2 > "$CUR_HELPERS"
  else 
    : > "$CUR_HELPERS"
  fi
  diff_and_log "$LAST_HELPERS" "$CUR_HELPERS" "PrivilegedHelperTools" "Helpers"
}

# Mantém as outras funções similares mas com otimizações pontuais
check_system_extensions_optimized() {
  log "[CHECK] System Extensions"
  /usr/bin/systemextensionsctl list 2>/dev/null | /usr/bin/sed '/^[[:space:]]*$/d' | /usr/bin/sort > "$CUR_EXT" || echo "" > "$CUR_EXT"
  diff_and_log "$LAST_EXT" "$CUR_EXT" "System Extensions" "SystemExtensions"
}

check_profiles_optimized() { 
  log "[CHECK] Perfis (MDM/Configuration)"
  # Usa cache para profiles que são custosos de obter
  local profile_cache="$CACHE_DIR/profiles.cache"
  local cache_age=$(($(date +%s) - $(stat -f "%m" "$profile_cache" 2>/dev/null || echo 0)))
  
  if [ -f "$profile_cache" ] && [ "$cache_age" -lt 300 ]; then  # Cache válido por 5 minutos
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
  
  diff_and_log "$LAST_PROF" "$CUR_PROF" "Profiles (MDM)" "Profiles"
}

check_ssh_sudo_optimized() {
  log "[CHECK] Sudoers/SSH (otimizado)"
  : > "$CUR_SSH_SUDO"
  
  # Processa arquivos em paralelo
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
  /usr/bin/sort -k2 "$CUR_SSH_SUDO" -o "$CUR_SSH_SUDO"
  diff_and_log "$LAST_SSH_SUDO" "$CUR_SSH_SUDO" "Sudoers/SSH" "Sudo/SSH"
}

# Funções mais simples mantidas com otimizações menores
check_syscfg_hosts_optimized() {
  log "[CHECK] SystemConfiguration + /etc/hosts"
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
  
  diff_and_log "$LAST_SYSCFG" "$CUR_SYSCFG" "SystemConfiguration" "SysCfg"
  
  [ -f /etc/hosts ] && /usr/bin/shasum -a 256 /etc/hosts > "$CUR_HOSTS" || : > "$CUR_HOSTS"
  diff_and_log "$LAST_HOSTS" "$CUR_HOSTS" "/etc/hosts" "hosts"
}

check_firewall_optimized() { 
  log "[CHECK] Firewall apps"
  /usr/libexec/ApplicationFirewall/socketfilterfw --listapps 2>/dev/null | /usr/bin/sort > "$CUR_FW" || echo "" > "$CUR_FW"
  diff_and_log "$LAST_FW" "$CUR_FW" "Firewall (listapps)" "Firewall"
}

check_pkgs_optimized() {
  log "[CHECK] Pacotes (pkgutil/Homebrew)"
  
  # Execução paralela
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
  
  diff_and_log "$LAST_PKGS" "$CUR_PKGS" "pkgutil --pkgs" "Pacotes"
  [ -s "$CUR_BREW" ] && diff_and_log "$LAST_BREW" "$CUR_BREW" "Homebrew (list --versions)" "Homebrew"
}

check_login_items_optimized() {
  log "[CHECK] Login Items"
  /usr/bin/osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | /usr/bin/tr ',' '\n' | /usr/bin/sed 's/^ *//; s/ *$//' | /usr/bin/sort > "$CUR_LOGIN" || echo "" > "$CUR_LOGIN"
  diff_and_log "$LAST_LOGIN" "$CUR_LOGIN" "Login Items" "LoginItems"
}

# Limpeza periódica do cache
cleanup_cache() {
  # Remove cache mais antigo que 7 dias
  if [ -d "$CACHE_DIR" ]; then
    /usr/bin/find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
  fi
}

# ===== Execução Otimizada =====
# Guard opcional — pula execução se estiver em bateria <30% e descarregando
if /usr/bin/pmset -g batt 2>/dev/null | /usr/bin/grep -qi "discharging"; then
  pct=$(/usr/bin/pmset -g batt | /usr/bin/awk -F';|%' '/InternalBattery|Battery Power/ {gsub(/ /,""); print $2; exit}')
  pct="$(to_int "$pct")"
  if [ "$pct" -lt 30 ]; then
    log "$(date) [SKIP] Bateria em ${pct}% (descarregando). Execução adiada."
    exit 0
  fi
fi

# Limpeza de cache antigo
cleanup_cache

# Execução das verificações (algumas podem rodar em paralelo)
log "[INFO] Iniciando verificações otimizadas..."

# Verificações mais custosas primeiro e em background quando possível
check_applications_versions_optimized &
APP_PID=$!

check_launch_optimized &
LAUNCH_PID=$!

check_helpers_optimized &
check_system_extensions_optimized &
check_profiles_optimized &

# Aguarda os processos mais custosos
wait $APP_PID
wait $LAUNCH_PID
wait  # Aguarda todos os outros background jobs

# Verificações mais rápidas em sequência
check_ssh_sudo_optimized
check_syscfg_hosts_optimized
check_firewall_optimized
check_pkgs_optimized
check_login_items_optimized

echo "Verificação otimizada concluída em $(date)" >> "$LOG_FILE"
echo "=============================" >> "$LOG_FILE"