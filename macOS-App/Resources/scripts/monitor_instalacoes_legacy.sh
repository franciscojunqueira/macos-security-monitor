#!/bin/bash
# Monitor de mudanças críticas no macOS (compatível com /bin/bash 3.2)
# Apps: monitora por fingerprint do Info.plist (BundleID, ShortVersion, Build, TeamID, hash do Info.plist)
set -euo pipefail

# ===== Ambiente “duro” (HOME pode não existir em LaunchDaemon) =====
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

# (Compatibilidade; não é mais usado para Apps)
/bin/touch "$BASE/last_check" 2>/dev/null || true

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

echo "=== MONITORAMENTO INICIADO ===" >> "$LOG_FILE"
echo "Data: $(date)" >> "$LOG_FILE"
echo "=============================" >> "$LOG_FILE"

# ===== Utilitários =====
notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" 2>/dev/null || true; }
log()    { echo "$*" >> "$LOG_FILE"; }

# Normaliza inteiro: remove tudo que não for dígito; vazio -> 0
to_int() {
  local val="$(printf '%s' "${1:-0}" | tr -cd '0-9')"
  [ -z "$val" ] && val="0"
  echo "$val"
}

# tenta hash; se precisar sudo -n; senão, marca NOACCESS
hash_file_safe() {
  local f="$1"
  if /usr/bin/shasum -a 256 "$f" >/dev/null 2>>"$LOG_FILE"; then
    /usr/bin/shasum -a 256 "$f"
  elif /usr/bin/sudo -n /usr/bin/shasum -a 256 "$f" >/dev/null 2>>"$LOG_FILE"; then
    /usr/bin/sudo -n /usr/bin/shasum -a 256 "$f"
  else
    echo "NOACCESS  $f"
  fi
}

diff_and_log() {
  # $1=last  $2=cur  $3=tag  $4=npfx
  local last cur tag npfx dfile
  last="${1-}"; cur="${2-}"; tag="${3-}"; npfx="${4-}"
  if [ -z "${last:-}" ] || [ -z "${cur:-}" ] || [ -z "${tag:-}" ] || [ -z "${npfx:-}" ]; then
    log "[WARN] diff_and_log chamado com args vazios: last='${last:-}' cur='${cur:-}' tag='${tag:-}' npfx='${npfx:-}'"
    return 0
  fi
  dfile="${cur}.diff"
  if [[ -f "$last" ]]; then
    if ! /usr/bin/diff -u "$last" "$cur" > "$dfile" 2>/dev/null; then
      local added removed delta
      added=$(/usr/bin/awk '/^\+[^+]/ {a++} END{print a+0}' "$dfile")
      removed=$(/usr/bin/awk '/^-[^-]/ {r++} END{print r+0}' "$dfile")
      added="$(to_int "$added")"; removed="$(to_int "$removed")"; delta=$(( added + removed ))
      log "[CHANGE] ${tag}: +${added} -${removed} (linhas de diferença: ${delta})"
      log "----- DIFF BEGIN (${tag}) -----"; /bin/cat "$dfile" >> "$LOG_FILE"; log "------ DIFF END (${tag}) ------"
      notify "Monitor de Segurança" "${npfx}: +${added} -${removed}"
      /bin/rm -f "$dfile" 2>/dev/null || true
    else
      log "Sem mudanças em ${tag}"
      /bin/rm -f "$dfile" 2>/dev/null || true
    fi
  else
    log "[INIT] Baseline de ${tag} criada"
  fi
  /bin/cp -f "$cur" "$last"
}

# ===== 1) Aplicações (/Applications) por versão (fingerprint) =====
# fingerprint: path<TAB>bundleID<TAB>short<TAB>build<TAB>team<TAB>hashInfoPlist
app_fingerprint() {
  local app="$1"; local plist="$app/Contents/Info.plist"
  local bid="" short="" build="" team="" hash=""
  if [ -f "$plist" ]; then
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || echo "")
    short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo "")
    build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo "")
    if /usr/bin/which codesign >/dev/null 2>&1; then
      team=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/awk -F= '/TeamIdentifier=/{print $2; exit}' || echo "")
    fi
    hash=$(/usr/bin/plutil -convert xml1 -o - "$plist" 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
  fi
  /bin/echo -e "${app}\t${bid}\t${short}\t${build}\t${team}\t${hash}"
}

build_apps_fingerprint() {
  : > "$CUR_APPS_FPR"
  /usr/bin/find /Applications -xdev -type d -name "*.app" -prune -print 2>/dev/null \
    | /usr/bin/sort \
    | while IFS= read -r app; do app_fingerprint "$app" || true; done >> "$CUR_APPS_FPR"
  /usr/bin/sort -t $'\t' -k1,1 "$CUR_APPS_FPR" -o "$CUR_APPS_FPR"
  /usr/bin/cut -f1 "$CUR_APPS_FPR" | /usr/bin/sort -u > "$CUR_APPS_PATHS"
}

check_applications_versions() {
  log "[CHECK] Aplicações (fingerprint por Info.plist)"
  build_apps_fingerprint

  if [[ ! -f "$LAST_APPS_FPR" || ! -f "$LAST_APPS_PATHS" ]]; then
    log "[INIT] Baseline de /Applications (fingerprint) criada"
    /bin/cp -f "$CUR_APPS_FPR" "$LAST_APPS_FPR"
    /bin/cp -f "$CUR_APPS_PATHS" "$LAST_APPS_PATHS"
    return 0
  fi

  local added_paths="$BASE/apps_added.txt"
  local removed_paths="$BASE/apps_removed.txt"
  /usr/bin/comm -13 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" > "$added_paths"   || true
  /usr/bin/comm -23 "$LAST_APPS_PATHS" "$CUR_APPS_PATHS" > "$removed_paths" || true

  local n_add n_rem n_chg
  n_add="$(to_int "$(/usr/bin/awk 'END{print NR+0}' "$added_paths" 2>/dev/null)")"
  n_rem="$(to_int "$(/usr/bin/awk 'END{print NR+0}' "$removed_paths" 2>/dev/null)")"

  if [ "$n_add" -gt 0 ]; then
    log "[CHANGE] Aplicações ADICIONADAS ($n_add):"
    /bin/cat "$added_paths" >> "$LOG_FILE"; log "---"
    while IFS= read -r app; do
      [ -z "$app" ] && continue
      {
        echo "NOVA APLICAÇÃO: $app"
        plist="$app/Contents/Info.plist"
        if [ -f "$plist" ]; then
          bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || echo "")
          short=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo "")
          build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo "")
          echo "BundleID: ${bid:-?}"
          echo "Versão: ${short:-?} (build ${build:-?})"
        fi
        if /usr/bin/which codesign >/dev/null 2>&1; then
          team=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/awk -F= '/TeamIdentifier=/{print $2; exit}' || echo "")
          echo "TeamIdentifier: ${team:-?}"
        fi
        echo "---"
      } >> "$LOG_FILE"
    done < "$added_paths"
  else
    log "Sem novas aplicações"
  fi

  if [ "$n_rem" -gt 0 ]; then
    log "[CHANGE] Aplicações REMOVIDAS ($n_rem):"
    /bin/cat "$removed_paths" >> "$LOG_FILE"; log "---"
  else
    log "Sem remoções de aplicações"
  fi

  local joined="$BASE/apps_joined.tsv" changes="$BASE/apps_changed.tsv"
  /usr/bin/join -t $'\t' -1 1 -2 1 "$LAST_APPS_FPR" "$CUR_APPS_FPR" > "$joined" || true

  /usr/bin/awk -F'\t' '{
    last = $2 FS $3 FS $4 FS $5 FS $6
    cur  = $7 FS $8 FS $9 FS $10 FS $11
    if (last != cur) {
      printf "ALTERADA: %s\n  ID: %s -> %s\n  Versão: %s (build %s) -> %s (build %s)\n  Team: %s -> %s\n  Info.plist hash: %s -> %s\n---\n",
             $1, $2, $7, $3, $4, $8, $9, $5, $10, $6, $11
    }
  }' "$joined" > "$changes" 2>/dev/null || true

  # conta quantas "ALTERADA:" existem (número de apps alterados)
  n_chg="$(to_int "$(/usr/bin/grep -c '^ALTERADA:' "$changes" 2>/dev/null || echo 0)")"

  if [ "$n_chg" -gt 0 ]; then
    log "[CHANGE] Aplicações ALTERADAS (por versão/fingerprint): $n_chg"
    /bin/cat "$changes" >> "$LOG_FILE"
  else
    log "Sem alterações de versão/fingerprint em /Applications"
  fi

  if [ "$n_add" -gt 0 ] || [ "$n_rem" -gt 0 ] || [ "$n_chg" -gt 0 ]; then
    notify "Monitor de Segurança" "Apps (versão): +${n_add}  -${n_rem}  ~${n_chg}"
  fi

  /bin/cp -f "$CUR_APPS_FPR" "$LAST_APPS_FPR"
  /bin/cp -f "$CUR_APPS_PATHS" "$LAST_APPS_PATHS"
  /bin/rm -f "$added_paths" "$removed_paths" "$joined" "$changes" 2>/dev/null || true
}

# ===== 2) LaunchDaemons/LaunchAgents (hash dos .plist) =====
hash_plists_dir() {
  local dir="${1}"
  if [ -d "$dir" ]; then
    /usr/bin/find "$dir" -maxdepth 1 -type f -name "*.plist" -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do hash_file_safe "$f"; done | /usr/bin/sort -k2
  fi
}
check_launch() {
  log "[CHECK] LaunchDaemons/LaunchAgents"
  hash_plists_dir "/Library/LaunchDaemons"     > "$CUR_LD_SYS" || echo "" > "$CUR_LD_SYS"
  hash_plists_dir "/Library/LaunchAgents"      > "$CUR_LA_SYS" || echo "" > "$CUR_LA_SYS"
  hash_plists_dir "${HOME:-/var/root}/Library/LaunchAgents" > "$CUR_LA_USR" || echo "" > "$CUR_LA_USR"
  diff_and_log "$LAST_LD_SYS" "$CUR_LD_SYS" "LaunchDaemons (/Library)" "LaunchDaemons"
  diff_and_log "$LAST_LA_SYS" "$CUR_LA_SYS" "LaunchAgents (sistema)" "LaunchAgents (sys)"
  diff_and_log "$LAST_LA_USR" "$CUR_LA_USR" "LaunchAgents (usuário)" "LaunchAgents (usr)"
}

# ===== 3) Privileged Helper Tools =====
check_helpers() {
  log "[CHECK] PrivilegedHelperTools"
  if [ -d "/Library/PrivilegedHelperTools" ]; then
    /usr/bin/find /Library/PrivilegedHelperTools -maxdepth 1 -type f -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do hash_file_safe "$f"; done | /usr/bin/sort -k2 > "$CUR_HELPERS"
  else : > "$CUR_HELPERS"; fi
  diff_and_log "$LAST_HELPERS" "$CUR_HELPERS" "PrivilegedHelperTools" "Helpers"
}

# ===== 4) System Extensions =====
canonicalize_extensions() {
  /usr/bin/systemextensionsctl list 2>/dev/null | /usr/bin/sed '/^[[:space:]]*$/d' | /usr/bin/awk '{print $0}' | /usr/bin/sort
}
check_system_extensions() {
  log "[CHECK] System Extensions"
  canonicalize_extensions > "$CUR_EXT" || echo "" > "$CUR_EXT"
  diff_and_log "$LAST_EXT" "$CUR_EXT" "System Extensions" "SystemExtensions"
}

# ===== 5) Perfis/MDM =====
canonicalize_profiles() {
  local tmp_xml="$BASE/profiles_dump.xml" tmp_json="$BASE/profiles_dump.json"
  : > "$CUR_PROF"
  if /usr/bin/profiles -P -o "$tmp_xml" >/dev/null 2>&1 || /usr/bin/profiles show -o "$tmp_xml" >/dev/null 2>&1; then
    if /usr/bin/plutil -convert json -o "$tmp_json" "$tmp_xml" >/dev/null 2>&1 && [ -s "$tmp_json" ]; then
      /usr/bin/sed 's/[[:space:]]\+$//' "$tmp_json" > "$CUR_PROF"; /bin/rm -f "$tmp_xml" "$tmp_json" 2>/dev/null || true; return 0
    fi
  fi
  /usr/bin/profiles list -type configuration 2>/dev/null | /usr/bin/sed 's/[[:space:]]\{1,\}/ /g' | /usr/bin/sed '/^[[:space:]]*$/d' | /usr/bin/sort > "$CUR_PROF"
  /bin/rm -f "$tmp_xml" "$tmp_json" 2>/dev/null || true
}
check_profiles() { log "[CHECK] Perfis (MDM/Configuration)"; canonicalize_profiles; diff_and_log "$LAST_PROF" "$CUR_PROF" "Profiles (MDM)" "Profiles"; }

# ===== 6) Sudoers / SSH =====
check_ssh_sudo() {
  log "[CHECK] Sudoers/SSH"; : > "$CUR_SSH_SUDO"
  for f in /etc/sudoers /etc/ssh/sshd_config; do [ -f "$f" ] && hash_file_safe "$f" >> "$CUR_SSH_SUDO"; done
  if [ -d /etc/sudoers.d ]; then
    /usr/bin/find /etc/sudoers.d -maxdepth 1 -type f -print0 2>/dev/null \
      | while IFS= read -r -d '' f; do hash_file_safe "$f"; done | /usr/bin/sort -k2 >> "$CUR_SSH_SUDO"
  fi
  [ -f "${HOME:-/var/root}/.ssh/authorized_keys" ] && hash_file_safe "${HOME:-/var/root}/.ssh/authorized_keys" >> "$CUR_SSH_SUDO" || true
  diff_and_log "$LAST_SSH_SUDO" "$CUR_SSH_SUDO" "Sudoers/SSH" "Sudo/SSH"
}

# ===== 7) SystemConfiguration + /etc/hosts =====
dump_plist_json_append() {
  local plist="$1"
  if [ -f "$plist" ]; then
    echo "### $plist" >> "$CUR_SYSCFG"
    if /usr/bin/plutil -convert json -o - "$plist" 2>/dev/null | /usr/bin/sed 's/[[:space:]]\+$//' >> "$CUR_SYSCFG"; then echo "" >> "$CUR_SYSCFG"; fi
  fi
}
check_syscfg_hosts() {
  log "[CHECK] SystemConfiguration + /etc/hosts"; : > "$CUR_SYSCFG"
  dump_plist_json_append "/Library/Preferences/SystemConfiguration/preferences.plist"
  dump_plist_json_append "/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist"
  dump_plist_json_append "/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist"
  dump_plist_json_append "/Library/Preferences/SystemConfiguration/com.apple.proxy.plist"
  diff_and_log "$LAST_SYSCFG" "$CUR_SYSCFG" "SystemConfiguration" "SysCfg"
  [ -f /etc/hosts ] && /usr/bin/shasum -a 256 /etc/hosts > "$CUR_HOSTS" || : > "$CUR_HOSTS"
  diff_and_log "$LAST_HOSTS" "$CUR_HOSTS" "/etc/hosts" "hosts"
}

# ===== 8) Firewall =====
check_firewall() { log "[CHECK] Firewall apps"; /usr/libexec/ApplicationFirewall/socketfilterfw --listapps 2>/dev/null | /usr/bin/sort > "$CUR_FW" || echo "" > "$CUR_FW"; diff_and_log "$LAST_FW" "$CUR_FW" "Firewall (listapps)" "Firewall"; }

# ===== 9) Pacotes (pkgutil + Homebrew) =====
check_pkgs() {
  log "[CHECK] Pacotes (pkgutil/Homebrew)"
  /usr/sbin/pkgutil --pkgs 2>/dev/null | /usr/bin/sort > "$CUR_PKGS" || echo "" > "$CUR_PKGS"; diff_and_log "$LAST_PKGS" "$CUR_PKGS" "pkgutil --pkgs" "Pacotes"
  local BREW_BIN=""; [ -x /opt/homebrew/bin/brew ] && BREW_BIN="/opt/homebrew/bin/brew"; [ -z "$BREW_BIN" ] && [ -x /usr/local/bin/brew ] && BREW_BIN="/usr/local/bin/brew"
  if [ -n "$BREW_BIN" ]; then "$BREW_BIN" list --versions 2>/dev/null | /usr/bin/sort > "$CUR_BREW" || echo "" > "$CUR_BREW"; diff_and_log "$LAST_BREW" "$CUR_BREW" "Homebrew (list --versions)" "Homebrew"; fi
}

# ===== 10) Login Items =====
check_login_items() {
  log "[CHECK] Login Items"
  /usr/bin/osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | /usr/bin/tr ',' '\n' | /usr/bin/sed 's/^ *//; s/ *$//' | /usr/bin/sort > "$CUR_LOGIN" || echo "" > "$CUR_LOGIN"
  diff_and_log "$LAST_LOGIN" "$CUR_LOGIN" "Login Items" "LoginItems"
}

# ===== Execução =====
# Guard opcional — pula execução se estiver em bateria <30% e descarregando
if /usr/bin/pmset -g batt 2>/dev/null | /usr/bin/grep -qi "discharging"; then
  pct=$(/usr/bin/pmset -g batt | /usr/bin/awk -F';|%' '/InternalBattery|Battery Power/ {gsub(/ /,""); print $2; exit}')
  pct="$(to_int "$pct")"
  if [ "$pct" -lt 30 ]; then
    log "$(date) [SKIP] Bateria em ${pct}% (descarregando). Execução adiada."
    exit 0
  fi
fi

check_applications_versions
check_launch
check_helpers
check_system_extensions
check_profiles
check_ssh_sudo
check_syscfg_hosts
check_firewall
check_pkgs
check_login_items

echo "Verificação concluída em $(date)" >> "$LOG_FILE"
echo "=============================" >> "$LOG_FILE"
