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

export SBP_SKIP_DEPS=1
export SBP_SKIP_ROOT=1
export SBP_ROOT="$test_root/sbp-root"
export SBP_BIN_DIR="$test_root/bin"
export SBP_DEPS_SENTINEL="$test_root/sbp-root/.deps_ok"
export SB_DIR="$test_root/state"
export CONF_JSON="$test_root/state/config.json"
export DATA_DIR="$test_root/state/data"
export CERT_DIR="$test_root/state/cert"
export WGCF_DIR="$test_root/state/wgcf"
export DIAG_DIR="$test_root/state/diagnostics"
export ROUTE_JSON="$test_root/state/routes.json"
export SHARE_LINKS_FILE="$test_root/state/share-links.txt"
export BIN_PATH="$test_root/bin/sing-box"
export SYSTEMD_SERVICE="test-sing-box.service"

mkdir -p "$SBP_BIN_DIR" "$SB_DIR" "$DATA_DIR" "$CERT_DIR"

# shellcheck source=../sing-box-plus.sh
source "$main_script"

assert_equal(){
  local expected=$1 actual=$2 message=$3
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

# 1. 测试 version_lt 逻辑
if ! version_lt "1.11.0" "1.12.0"; then
  echo "FAIL: 1.11.0 must be less than 1.12.0" >&2; exit 1
fi
if ! version_lt "1.12.0" "1.12.7"; then
  echo "FAIL: 1.12.0 must be less than 1.12.7" >&2; exit 1
fi
if ! version_lt "1.12.0-rc.1" "1.12.0"; then
  echo "FAIL: 1.12.0-rc.1 must be less than 1.12.0" >&2; exit 1
fi
if version_lt "1.12.7" "1.12.7"; then
  echo "FAIL: 1.12.7 must not be less than 1.12.7" >&2; exit 1
fi
if version_lt "1.13.0" "1.12.7"; then
  echo "FAIL: 1.13.0 must not be less than 1.12.7" >&2; exit 1
fi

# 2. 测试 get_singbox_local_version
cat > "$BIN_PATH" <<'EOF'
#!/usr/bin/env bash
echo "sing-box version 1.11.5"
EOF
chmod 0755 "$BIN_PATH"
local_v=$(get_singbox_local_version "$BIN_PATH")
assert_equal "1.11.5" "$local_v" "must correctly extract semver from version output"

# 3. 测试 GeoFiles 模拟更新与落地路径
# 模拟 curl
cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "$out" ]]; then
  printf 'mock-geo-content\n' > "$out"
  exit 0
fi
printf '{"Status":0}\n'
EOF
chmod 0755 "$test_root/bin/curl"
export PATH="$test_root/bin:$PATH"

systemctl(){
  return 0
}

update_geofiles > "$test_root/geofiles.log" 2>&1
if [[ ! -f "$DATA_DIR/geoip.db" ]]; then
  echo "FAIL: geoip.db must exist in $DATA_DIR" >&2
  exit 1
fi
if [[ ! -f "$DATA_DIR/geosite.db" ]]; then
  echo "FAIL: geosite.db must exist in $DATA_DIR" >&2
  exit 1
fi
if [[ ! -f "$DATA_DIR/geoip-cn.srs" ]]; then
  echo "FAIL: geoip-cn.srs must exist in $DATA_DIR" >&2
  exit 1
fi
if [[ ! -f "$SB_DIR/geofiles.version" ]]; then
  echo "FAIL: geofiles.version must exist in $SB_DIR" >&2
  exit 1
fi

# 4. 测试 show_service_status 输出
status_out=$(show_service_status 2>&1)
if ! echo "$status_out" | grep -q "Sing-Box-Plus 综合运行状态看板"; then
  echo "FAIL: show_service_status must render title banner" >&2
  exit 1
fi
if ! echo "$status_out" | grep -q "20 节点端口监听监控"; then
  echo "FAIL: show_service_status must render 20 node status section" >&2
  exit 1
fi

# 5. 测试 uninstall_all 交互取消与确认
(echo "n" | uninstall_all) > "$test_root/uninstall_cancel.log" 2>&1 || true
if [[ ! -d "$SB_DIR" ]]; then
  echo "FAIL: canceling uninstall must keep $SB_DIR intact" >&2
  exit 1
fi

(echo "y" | uninstall_all) > "$test_root/uninstall_exec.log" 2>&1 || true
if [[ -d "$SB_DIR" ]]; then
  echo "FAIL: confirming uninstall must remove $SB_DIR" >&2
  exit 1
fi
if [[ -f "$BIN_PATH" ]]; then
  echo "FAIL: confirming uninstall must remove $BIN_PATH" >&2
  exit 1
fi

printf '%s\n' "PASS: enhanced features (version compare, geofiles update, status viewer, uninstall) work correctly"
