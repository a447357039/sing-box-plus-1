#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
main_script="$repo_root/sing-box-plus.sh"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

command -v jq >/dev/null 2>&1 || {
  echo "jq is required" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/state" "$test_root/systemd" "$test_root/root"

cat > "$test_root/state/config.json" <<'EOF'
{
  "dns": {"final": "dns-doh-primary"},
  "route": {"default_domain_resolver": "dns-doh-primary"},
  "outbounds": [],
  "endpoints": []
}
EOF
printf '%s\n' 'UUID=keep-this-credential' > "$test_root/state/creds.env"
printf '%s\n' 'PORT_VLESSR=12345' > "$test_root/state/ports.env"
cat > "$test_root/state/env.conf" <<EOF
# Existing settings and custom lines must survive a runtime update.
CONF_JSON=$test_root/state/config.json
DNS_HEALTH_INTERVAL=3m
export CUSTOM_SETTING='keep value'
EOF

printf '%s\n' 'old management script' > "$test_root/root/sbp.sh"
printf '%s\n' 'old dns helper' > "$test_root/bin/dns-health"
printf '%s\n' 'old event helper' > "$test_root/bin/event-log"
printf '%s\n' 'old dns service' > "$test_root/systemd/test-dns-health.service"
printf '%s\n' 'old dns timer' > "$test_root/systemd/test-dns-health.timer"

cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"Status":0}'
EOF

cat > "$test_root/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  is-active)
    if [[ "$*" == *test-dns-health.timer* && -f "$TEST_ROOT/timer-inactive" ]]; then
      exit 3
    fi
    exit 0
    ;;
  is-enabled)
    exit 0
    ;;
  show)
    printf '%s\n' 4242
    ;;
  stop|start)
    printf '%s\n' "$*" >> "$TEST_ROOT/systemctl.log"
    ;;
  daemon-reload)
    printf '%s\n' "$*" >> "$TEST_ROOT/systemctl.log"
    if [[ -f "$TEST_ROOT/fail-daemon-reload-once" ]]; then
      rm -f "$TEST_ROOT/fail-daemon-reload-once"
      exit 1
    fi
    ;;
  restart|enable|disable)
    printf 'unexpected systemctl mutation: %s\n' "$*" >&2
    exit 99
    ;;
  *)
    printf 'unexpected systemctl command: %s\n' "$*" >&2
    exit 98
    ;;
esac
EOF
chmod 0755 "$test_root/bin/curl" "$test_root/bin/systemctl"

export TEST_ROOT="$test_root"
export SBP_ROOT="$test_root/sbp-root"
export SBP_BIN_DIR="$test_root/bin"
export SBP_DEPS_SENTINEL="$test_root/sbp-root/.deps_ok"
export SB_DIR="$test_root/state"
export CONF_JSON="$test_root/state/config.json"
export DATA_DIR="$test_root/state/data"
export CERT_DIR="$test_root/state/cert"
export WGCF_DIR="$test_root/state/wgcf"
export DIAG_DIR="$test_root/state/diagnostics"
export BIN_PATH="$test_root/bin/sing-box"
export DNS_HEALTH_BIN="$test_root/bin/dns-health"
export EVENT_LOG_BIN="$test_root/bin/event-log"
export SYSTEMD_UNIT_DIR="$test_root/systemd"
export SYSTEMD_SERVICE="test-sing-box.service"
export DNS_HEALTH_SERVICE="test-dns-health.service"
export DNS_HEALTH_TIMER="test-dns-health.timer"
export SBP_SCRIPT_PATH="$test_root/root/sbp.sh"
export PATH="$test_root/bin:$PATH"

config_hash=$(sha256sum "$CONF_JSON" | awk '{print $1}')
creds_hash=$(sha256sum "$SB_DIR/creds.env" | awk '{print $1}')
ports_hash=$(sha256sum "$SB_DIR/ports.env" | awk '{print $1}')
: > "$test_root/systemctl.log"

assert_equal(){
  local expected=$1 actual=$2 message=$3
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_file_unchanged(){
  local expected_hash=$1 file=$2 message=$3 actual_hash
  actual_hash=$(sha256sum "$file" | awk '{print $1}')
  assert_equal "$expected_hash" "$actual_hash" "$message"
}

assert_threshold(){
  local key=$1 expected=$2 count value
  count=$(grep -Ec "^[[:space:]]*(export[[:space:]]+)?${key}=" "$SB_DIR/env.conf")
  value=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$SB_DIR/env.conf" | tail -n1 | cut -d= -f2-)
  assert_equal 1 "$count" "$key must occur exactly once"
  assert_equal "$expected" "$value" "$key must contain the requested value"
}

bash "$main_script" --update-runtime > "$test_root/update-1.log"

assert_threshold DNS_FAILURE_THRESHOLD 3
assert_threshold DNS_RECOVERY_THRESHOLD 5
assert_threshold DNS_SWITCH_COOLDOWN 600
grep -Fqx "export CUSTOM_SETTING='keep value'" "$SB_DIR/env.conf"
grep -Fqx 'DNS_HEALTH_INTERVAL=3m' "$SB_DIR/env.conf"

DNS_FAILURE_THRESHOLD=4 DNS_RECOVERY_THRESHOLD=6 DNS_SWITCH_COOLDOWN=900 \
  bash "$main_script" --update-runtime > "$test_root/update-2.log"

assert_threshold DNS_FAILURE_THRESHOLD 4
assert_threshold DNS_RECOVERY_THRESHOLD 6
assert_threshold DNS_SWITCH_COOLDOWN 900
grep -Fqx "export CUSTOM_SETTING='keep value'" "$SB_DIR/env.conf"

assert_file_unchanged "$config_hash" "$CONF_JSON" "config.json must not change"
assert_file_unchanged "$creds_hash" "$SB_DIR/creds.env" "creds.env must not change"
assert_file_unchanged "$ports_hash" "$SB_DIR/ports.env" "ports.env must not change"

bash -n "$SBP_SCRIPT_PATH"
bash -n "$DNS_HEALTH_BIN"
bash -n "$EVENT_LOG_BIN"
assert_equal 755 "$(stat -c '%a' "$SBP_SCRIPT_PATH")" "installed management script mode"
assert_equal 755 "$(stat -c '%a' "$DNS_HEALTH_BIN")" "DNS helper mode"
assert_equal 644 "$(stat -c '%a' "$SYSTEMD_UNIT_DIR/$DNS_HEALTH_TIMER")" "timer unit mode"
grep -Fq 'OnUnitActiveSec=3m' "$SYSTEMD_UNIT_DIR/$DNS_HEALTH_TIMER"

: > "$test_root/timer-inactive"
bash "$main_script" --update-runtime > "$test_root/update-inactive-timer.log"
rm -f "$test_root/timer-inactive"
assert_equal 2 "$(grep -c '^stop test-dns-health.timer$' "$test_root/systemctl.log")" \
  "an inactive timer must not be stopped"
assert_equal 2 "$(grep -c '^start test-dns-health.timer$' "$test_root/systemctl.log")" \
  "an inactive timer must remain inactive"

script_hash=$(sha256sum "$SBP_SCRIPT_PATH" | awk '{print $1}')
helper_hash=$(sha256sum "$DNS_HEALTH_BIN" | awk '{print $1}')
event_hash=$(sha256sum "$EVENT_LOG_BIN" | awk '{print $1}')
env_hash=$(sha256sum "$SB_DIR/env.conf" | awk '{print $1}')
service_hash=$(sha256sum "$SYSTEMD_UNIT_DIR/$DNS_HEALTH_SERVICE" | awk '{print $1}')
timer_hash=$(sha256sum "$SYSTEMD_UNIT_DIR/$DNS_HEALTH_TIMER" | awk '{print $1}')
: > "$test_root/fail-daemon-reload-once"
if DNS_FAILURE_THRESHOLD=7 bash "$main_script" --update-runtime > "$test_root/update-rollback.log" 2>&1; then
  echo "FAIL: injected daemon-reload failure must fail the update" >&2
  exit 1
fi

assert_file_unchanged "$script_hash" "$SBP_SCRIPT_PATH" "failed update must restore management script"
assert_file_unchanged "$helper_hash" "$DNS_HEALTH_BIN" "failed update must restore DNS helper"
assert_file_unchanged "$event_hash" "$EVENT_LOG_BIN" "failed update must restore event helper"
assert_file_unchanged "$env_hash" "$SB_DIR/env.conf" "failed update must restore env.conf"
assert_file_unchanged "$service_hash" "$SYSTEMD_UNIT_DIR/$DNS_HEALTH_SERVICE" "failed update must restore service unit"
assert_file_unchanged "$timer_hash" "$SYSTEMD_UNIT_DIR/$DNS_HEALTH_TIMER" "failed update must restore timer unit"

backup_count=$(find "$SB_DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'runtime-update-*' | wc -l | tr -d ' ')
assert_equal 4 "$backup_count" "each update attempt must create a separate backup"
while IFS= read -r backup_dir; do
  [[ -f "$backup_dir/config.json" ]]
  [[ -f "$backup_dir/creds.env" ]]
  [[ -f "$backup_dir/ports.env" ]]
done < <(find "$SB_DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'runtime-update-*')

if grep -Eq '(^| )restart( |$)|(^| )(enable|disable)( |$)' "$test_root/systemctl.log"; then
  echo "FAIL: runtime update must not restart sing-box or change timer enablement" >&2
  cat "$test_root/systemctl.log" >&2
  exit 1
fi
assert_equal 4 "$(grep -c '^stop test-dns-health.timer$' "$test_root/systemctl.log")" \
  "updates and rollback must pause the timer before replacing files"
assert_equal 3 "$(grep -c '^start test-dns-health.timer$' "$test_root/systemctl.log")" \
  "successful updates and rollback must restore the active timer"

printf '%s\n' "PASS: lightweight runtime update is isolated, idempotent, and restart-free"
