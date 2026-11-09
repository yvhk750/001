#!/usr/bin/env bash
set -Eeuo pipefail

readonly SB_CONFIG="/etc/sing-box/config.json"
readonly SB_DIR="/etc/sing-box"
readonly CERT_DIR="/etc/sing-box/certs"
readonly SYSCTL_FILE="/etc/sysctl.d/99-bbr.conf"
readonly INSTALL_URL="https://sing-box.app/install.sh"
readonly RELEASE_API="https://api.github.com/repos/SagerNet/sing-box/releases/latest"

C_RESET='\033[0m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'; C_CYAN='\033[36m'

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo -e "${C_RED}请使用 root 运行：sudo bash $0${C_RESET}"
    exit 1
  fi
}

pause() { read -r -p "按 Enter 返回菜单..." _ || true; }

ensure_tools() {
  local missing=()
  for cmd in curl openssl; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
  if ((${#missing[@]})); then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl openssl
  fi
}

current_version() {
  if command -v sing-box >/dev/null 2>&1; then
    sing-box version 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i ~ /^v?[0-9]+\./){sub(/^v/,"",$i); print $i; exit}}'
  else
    printf '未安装'
  fi
}

latest_version() {
  local tag
  tag=$(curl -fsSL --connect-timeout 5 --max-time 10 \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: sb-menu' "$RELEASE_API" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1) || true
  printf '%s' "${tag:-获取失败}"
}

install_singbox() {
  echo -e "${C_CYAN}正在运行 sing-box 官方安装脚本...${C_RESET}"
  ensure_tools
  curl -fsSL "$INSTALL_URL" | sh
  systemctl enable sing-box 2>/dev/null || true
  echo -e "${C_GREEN}安装流程完成。${C_RESET}"
}

random_port() {
  local p
  for _ in {1..100}; do
    p=$((RANDOM % 45536 + 20000))
    if ! ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|:)$p$"; then echo "$p"; return; fi
  done
  echo 8443
}

public_ipv4() { curl -4 -fsSL --connect-timeout 4 --max-time 8 https://api.ipify.org 2>/dev/null || true; }
public_ipv6() { curl -6 -fsSL --connect-timeout 4 --max-time 8 https://api64.ipify.org 2>/dev/null || true; }

urlencode() {
  local s="$1" out='' i c hex
  LC_ALL=C
  for ((i=0; i<${#s}; i++)); do
    c=${s:i:1}
    case "$c" in [a-zA-Z0-9.~_-]) out+="$c";; *) printf -v hex '%%%02X' "'$c"; out+="$hex";; esac
  done
  printf '%s' "$out"
}

generate_anytls() {
  if ! command -v sing-box >/dev/null 2>&1; then
    echo -e "${C_RED}尚未安装 sing-box，请先选择菜单 1。${C_RESET}"; return 1
  fi
  ensure_tools
  install -d -m 0755 "$SB_DIR" "$CERT_DIR"

  local domain port password cert key backup tmp_ip4 tmp_ip6 fingerprint pass_url name
  domain="$(openssl rand -hex 6).com"
  port=$(random_port)
  password=$(openssl rand -hex 16)
  cert="$CERT_DIR/anytls.crt"
  key="$CERT_DIR/anytls.key"

  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -keyout "$key" -out "$cert" -subj "/CN=$domain" \
    -addext "subjectAltName=DNS:$domain" >/dev/null 2>&1
  chmod 600 "$key"; chmod 644 "$cert"

  if [[ -f "$SB_CONFIG" ]]; then
    backup="${SB_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$SB_CONFIG" "$backup"
    echo "原配置已备份：$backup"
  fi

  cat > "${SB_CONFIG}.new" <<JSON
{
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": $port,
      "users": [ { "name": "default", "password": "$password" } ],
      "tls": {
        "enabled": true,
        "server_name": "$domain",
        "certificate_path": "$cert",
        "key_path": "$key"
      }
    }
  ]
}
JSON

  if ! sing-box check -c "${SB_CONFIG}.new"; then
    rm -f "${SB_CONFIG}.new"
    echo -e "${C_RED}配置校验失败，未替换原配置。${C_RESET}"; return 1
  fi
  mv "${SB_CONFIG}.new" "$SB_CONFIG"
  chmod 600 "$SB_CONFIG"
  systemctl enable sing-box >/dev/null 2>&1 || true
  if ! systemctl restart sing-box; then
    echo -e "${C_RED}服务重启失败，请运行：journalctl -u sing-box -n 100 --no-pager${C_RESET}"
    return 1
  fi

  fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2)
  tmp_ip4=$(public_ipv4); tmp_ip6=$(public_ipv6)
  pass_url=$(urlencode "$password"); name=$(urlencode "AnyTLS-$domain")

  echo -e "\n${C_GREEN}AnyTLS 已生成并启动${C_RESET}"
  if [[ -n "$tmp_ip4" ]]; then
    printf '\nIPv4 节点：\nanytls://%s@%s:%s/?sni=%s&pcs=%s#%s-IPv4\n' "$pass_url" "$tmp_ip4" "$port" "$domain" "$fingerprint" "$name"
  else
    echo -e "\n${C_YELLOW}未检测到公网 IPv4。${C_RESET}"
  fi
  if [[ -n "$tmp_ip6" && "$tmp_ip6" == *:* ]]; then
    printf '\nIPv6 节点：\nanytls://%s@[%s]:%s/?sni=%s&pcs=%s#%s-IPv6\n' "$pass_url" "$tmp_ip6" "$port" "$domain" "$fingerprint" "$name"
  else
    echo -e "\n${C_YELLOW}未检测到公网 IPv6。${C_RESET}"
  fi
  echo -e "\n${C_YELLOW}注意：这是自签证书，随机域名为 SNI 标识，不需要 DNS 解析。${C_RESET}"
}

enable_bbr() {
  local active available
  active=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  if [[ "$active" == "bbr" ]]; then echo -e "${C_GREEN}BBR 已开启。${C_RESET}"; return; fi
  modprobe tcp_bbr 2>/dev/null || true
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)
  if ! grep -qw bbr <<<"$available"; then
    echo -e "${C_RED}当前内核未提供 BBR。请先升级到支持 BBR 的 Debian 内核。${C_RESET}"; return 1
  fi
  cat > "$SYSCTL_FILE" <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL
  sysctl --system >/dev/null
  active=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  if [[ "$active" == "bbr" ]]; then echo -e "${C_GREEN}BBR 开启成功。${C_RESET}"; else echo -e "${C_RED}BBR 开启失败。${C_RESET}"; return 1; fi
}

menu() {
  need_root
  if [[ "$0" != "/usr/local/bin/sb" ]]; then
    install -m 0755 "$0" /usr/local/bin/sb
    echo -e "${C_GREEN}已安装命令：以后输入 sb 即可打开菜单。${C_RESET}"
    sleep 1
  fi
  while true; do
    clear
    echo -e "${C_CYAN}========================================${C_RESET}"
    echo -e "        sing-box Debian 管理脚本"
    echo -e " 当前版本：${C_GREEN}$(current_version)${C_RESET}"
    echo -e " 官方最新：${C_GREEN}$(latest_version)${C_RESET}"
    echo -e "${C_CYAN}========================================${C_RESET}"
    echo '1. 安装 sing-box（官方一键脚本）'
    echo '2. 生成 AnyTLS 配置'
    echo '3. 开启 BBR'
    echo '0. 退出'
    read -r -p '请选择 [0-3]：' choice
    case "$choice" in
      1) install_singbox; pause;;
      2) generate_anytls || true; pause;;
      3) enable_bbr || true; pause;;
      0) exit 0;;
      *) echo '无效选择'; sleep 1;;
    esac
  done
}

menu
