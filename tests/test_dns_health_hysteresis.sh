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

helper="$test_root/dns-health"
awk '
  $0 == "  cat > \"$DNS_HEALTH_BIN\" <<'\''EOF'\''" { capture=1; next }
  capture && $0 == "EOF" { exit }
  capture { print }
' "$main_script" > "$helper"
chmod 0755 "$helper"

mkdir -p "$test_root/bin" "$test_root/state"
cat > "$test_root/state/config.json" <<'EOF'
{
  "dns": {"final": "dns-doh-primary"},
  "route": {"default_domain_resolver": "dns-doh-primary"},
  "outbounds": [{"type": "direct", "tag": "direct", "domain_resolver": "dns-doh-primary"}],
  "endpoints": []
}
EOF

cat > "$test_root/state/env.conf" <<EOF
CONF_JSON=$test_root/state/config.json
DNS_HEALTH_LOG=$test_root/state/dns-health.log
BIN_PATH=$test_root/bin/sing-box
SYSTEMD_SERVICE=sing-box.service
DNS_FAILURE_THRESHOLD=3
DNS_RECOVERY_THRESHOLD=5
DNS_SWITCH_COOLDOWN=600
EOF

cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *cloudflare-dns.com*) result=$(cat "$TEST_STATE/cloudflare") ;;
  *dns.google*) result=$(cat "$TEST_STATE/google") ;;
  *) exit 22 ;;
esac
[[ "$result" == "ok" ]] || exit 22
printf '%s\n' '{"Status":0}'
EOF

cat > "$test_root/bin/sing-box" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "check" ]]
EOF

cat > "$test_root/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" ]]; then
  exit 0
fi
if [[ "${1:-}" == "restart" ]]; then
  printf '%s\n' "$*" >> "$TEST_STATE/restarts"
  exit 0
fi
exit 1
EOF
chmod 0755 "$test_root/bin/"*

export TEST_STATE="$test_root/state"
export SB_DIR="$TEST_STATE"
export PATH="$test_root/bin:$PATH"
printf '%s\n' fail > "$TEST_STATE/cloudflare"
printf '%s\n' ok > "$TEST_STATE/google"
: > "$TEST_STATE/restarts"

assert_equal(){
  local expected=$1 actual=$2 message=$3
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

current_dns(){
  jq -r '.dns.final' "$TEST_STATE/config.json"
}

restart_count(){
  wc -l < "$TEST_STATE/restarts" | tr -d ' '
}

"$helper"
"$helper"
assert_equal dns-doh-primary "$(current_dns)" "two failures must not switch DNS"
assert_equal 0 "$(restart_count)" "two failures must not restart sing-box"

"$helper"
assert_equal dns-doh-backup "$(current_dns)" "third failure must switch to backup"
assert_equal 1 "$(restart_count)" "confirmed failover must restart exactly once"

printf '%s\n' ok > "$TEST_STATE/cloudflare"
for _ in 1 2 3 4 5; do
  "$helper"
done
assert_equal dns-doh-backup "$(current_dns)" "recovery cooldown must prevent an early switch"
assert_equal 1 "$(restart_count)" "recovery cooldown must prevent an early restart"

sed -i 's/^last_switch=.*/last_switch=1/' "$TEST_STATE/dns-health.state"
"$helper"
assert_equal dns-doh-primary "$(current_dns)" "stable recovery must restore primary DNS"
assert_equal 2 "$(restart_count)" "stable recovery must restart exactly once"

printf '%s\n' "PASS: DNS health hysteresis and cooldown"
