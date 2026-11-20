#!/usr/bin/env bash
# ==============================================================================
# sing-box 管理脚本 (sb)
# 功能:
#   1. 官方脚本安装/更新 sing-box
#   2. 一键配置 AnyTLS (自签证书 + pcs SHA-256 指纹) 与 VLESS + Reality
#   3. 检查并开启 BBR 拥塞控制
# ==============================================================================

set -u

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CERT_DIR="${CONFIG_DIR}/certs"
CERT_FILE="${CERT_DIR}/anytls.crt"
KEY_FILE="${CERT_DIR}/anytls.key"
BIN_LINK="/usr/local/bin/sb"

# ------------------------------------------------------------------------------
# 基础工具函数
# ------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误] 请使用 root 用户或 sudo 运行此脚本。${NC}"
        exit 1
    fi
}

install_shortcut() {
    local self_path
    self_path="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
    if [[ "$self_path" != "$BIN_LINK" ]]; then
        cp -f "$self_path" "$BIN_LINK" && chmod +x "$BIN_LINK"
        echo -e "${GREEN}[提示] 已自动安装快捷命令，以后直接输入 ${BOLD}sb${NC}${GREEN} 即可进入菜单。${NC}"
    fi
}

ensure_deps() {
    local missing=()
    for cmd in curl openssl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}[提示] 正在安装基础依赖: ${missing[*]} ...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y >/dev/null 2>&1 && apt-get install -y "${missing[@]}" >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "${missing[@]}" >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "${missing[@]}" >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache "${missing[@]}" >/dev/null 2>&1
        fi
    fi
}

url_encode() {
    local str="$1"
    local len=${#str}
    local encoded=""
    local i c
    for (( i=0; i<len; i++ )); do
        c="${str:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'$c"; encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

# ------------------------------------------------------------------------------
# 状态检测 (sing-box 安装状态 / 版本对比 / BBR)
# ------------------------------------------------------------------------------
get_local_version() {
    if command -v sing-box >/dev/null 2>&1; then
        sing-box version 2>/dev/null | awk '/sing-box version/ {print $3; exit}'
    fi
}

get_latest_version() {
    local tag
    tag=$(curl -fsSL --max-time 5 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null \
        | grep -m1 '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    echo "$tag"
}

check_bbr_status() {
    local cc qdisc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    if [[ "$cc" == "bbr" ]]; then
        echo -e "${GREEN}已开启 (${cc} / ${qdisc})${NC}"
    else
        echo -e "${YELLOW}未开启 (当前: ${cc} / ${qdisc})${NC}"
    fi
}

show_status_banner() {
    local local_ver latest_ver svc_status install_line
    local_ver=$(get_local_version)
    latest_ver=$(get_latest_version)

    if [[ -z "$local_ver" ]]; then
        install_line="${RED}未安装${NC}"
        svc_status="${YELLOW}未安装${NC}"
    else
        if [[ -z "$latest_ver" ]]; then
            install_line="${GREEN}已安装 (v${local_ver})${NC} ${YELLOW}[最新版本获取失败]${NC}"
        elif [[ "$local_ver" == "$latest_ver" ]]; then
            install_line="${GREEN}已安装 (v${local_ver}，已是最新版本)${NC}"
        else
            install_line="${YELLOW}已安装 (当前: v${local_ver} / 最新: v${latest_ver}，可更新)${NC}"
        fi

        if systemctl is-active --quiet sing-box 2>/dev/null; then
            svc_status="${GREEN}运行中${NC}"
        else
            svc_status="${RED}未运行${NC}"
        fi
    fi

    clear
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BOLD}            sing-box 管理面板 (sb)${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo -e "  sing-box 状态 : ${install_line}"
    echo -e "  服务运行状态  : ${svc_status}"
    echo -e "  BBR 拥塞控制  : $(check_bbr_status)"
    echo -e "${BLUE}----------------------------------------------------${NC}"
}

# ------------------------------------------------------------------------------
# 菜单 1: 使用官方脚本安装 sing-box
# ------------------------------------------------------------------------------
install_sing_box() {
    echo -e "\n${BLUE}[信息] 正在使用官方脚本安装/更新 sing-box ...${NC}"
    if curl -fsSL https://sing-box.app/install.sh | sh; then
        systemctl enable sing-box >/dev/null 2>&1 || true
        local ver
        ver=$(get_local_version)
        echo -e "${GREEN}[成功] sing-box 安装完成！当前版本: v${ver:-未知}${NC}"
    else
        echo -e "${RED}[错误] sing-box 官方安装脚本执行失败，请检查网络连接或系统架构。${NC}"
    fi
    read -rp "按回车键返回主菜单..."
}

# ------------------------------------------------------------------------------
# 菜单 2: 配置 AnyTLS 和 VLESS+Reality
# ------------------------------------------------------------------------------
configure_protocols() {
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "\n${RED}[错误] 尚未安装 sing-box，请先选择菜单 1 进行安装。${NC}"
        read -rp "按回车键返回主菜单..."
        return
    fi

    echo -e "\n${BOLD}--- 配置 AnyTLS 与 VLESS+Reality ---${NC}"

    # 1. 输入域名
    local domain reality_sni
    while true; do
        read -rp "请输入用于 AnyTLS 自签证书的域名 (例如 example.com): " domain
        domain="${domain// /}"
        if [[ -n "$domain" ]]; then
            break
        fi
        echo -e "${RED}域名不能为空，请重新输入。${NC}"
    done

    read -rp "请输入 VLESS+Reality 伪装目标域名 (SNI) [默认: ${domain}]: " reality_sni
    reality_sni="${reality_sni// /}"
    [[ -z "$reality_sni" ]] && reality_sni="$domain"

    # 2. 分别输入两个协议的端口
    local anytls_port vless_port
    while true; do
        read -rp "请输入 AnyTLS 监听端口 [默认: 8443]: " anytls_port
        anytls_port="${anytls_port:-8443}"
        if validate_port "$anytls_port"; then
            break
        fi
        echo -e "${RED}端口无效，请输入 1-65535 之间的数字。${NC}"
    done

    while true; do
        read -rp "请输入 VLESS+Reality 监听端口 [默认: 443]: " vless_port
        vless_port="${vless_port:-443}"
        if ! validate_port "$vless_port"; then
            echo -e "${RED}端口无效，请输入 1-65535 之间的数字。${NC}"
        elif [[ "$vless_port" == "$anytls_port" ]]; then
            echo -e "${RED}VLESS+Reality 端口不能与 AnyTLS 端口 (${anytls_port}) 相同，请重新输入。${NC}"
        else
            break
        fi
    done

    # 3. 生成 AnyTLS 自签证书与随机密码
    mkdir -p "$CERT_DIR" "$CONFIG_DIR"
    echo -e "\n${BLUE}[信息] 正在为 ${domain} 生成 AnyTLS 自签证书 ...${NC}"
    if ! openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes -days 3650 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/CN=${domain}" \
        -addext "subjectAltName=DNS:${domain}" >/dev/null 2>&1; then
        echo -e "${RED}[错误] 自签证书生成失败，请检查 openssl 是否正常。${NC}"
        read -rp "按回车键返回主菜单..."
        return
    fi

    # 计算证书十六进制 SHA-256 指纹 (用于 pcs 参数)
    local cert_sha256_hex
    cert_sha256_hex=$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')

    # 生成 AnyTLS 随机密码
    local anytls_pass
    anytls_pass=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)

    # 4. 生成 VLESS+Reality 密钥与 UUID
    echo -e "${BLUE}[信息] 正在生成 VLESS+Reality 密钥对与 UUID ...${NC}"
    local uuid keypair priv_key pub_key short_id
    uuid=$(sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    keypair=$(sing-box generate reality-keypair 2>/dev/null)
    priv_key=$(echo "$keypair" | awk '/PrivateKey:/ {print $2}')
    pub_key=$(echo "$keypair" | awk '/PublicKey:/ {print $2}')
    short_id=$(openssl rand -hex 8)

    if [[ -z "$priv_key" || -z "$pub_key" || -z "$uuid" ]]; then
        echo -e "${RED}[错误] Reality 密钥或 UUID 生成失败，请确认 sing-box 版本正常。${NC}"
        read -rp "按回车键返回主菜单..."
        return
    fi

    # 5. 写入 sing-box 配置文件
    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${anytls_port},
      "users": [
        {
          "name": "anytls-user",
          "password": "${anytls_pass}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${vless_port},
      "users": [
        {
          "name": "vless-user",
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${reality_sni}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${reality_sni}",
            "server_port": 443
          },
          "private_key": "${priv_key}",
          "short_id": [
            "${short_id}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # 6. 校验并重启服务
    echo -e "${BLUE}[信息] 正在校验配置文件并重启 sing-box ...${NC}"
    if ! sing-box check -c "$CONFIG_FILE"; then
        echo -e "${RED}[错误] 配置文件校验未通过，请检查 ${CONFIG_FILE}。${NC}"
        read -rp "按回车键返回主菜单..."
        return
    fi

    systemctl enable sing-box >/dev/null 2>&1 || true
    if ! systemctl restart sing-box; then
        echo -e "${RED}[错误] sing-box 启动失败，请运行 journalctl -u sing-box -e 查看日志。${NC}"
        read -rp "按回车键返回主菜单..."
        return
    fi

    # 7. 获取本机公网 IPv4 和 IPv6
    local ipv4 ipv6
    ipv4=$(curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || curl -4 -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    ipv6=$(curl -6 -fsSL --max-time 5 https://api64.ipify.org 2>/dev/null || curl -6 -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    # 若 api64 返回的仍是 IPv4，则置空
    if [[ "$ipv6" != *:* ]]; then
        ipv6=""
    fi

    echo -e "\n${GREEN}====================================================${NC}"
    echo -e "${BOLD}  配置完成！sing-box 已启动并运行${NC}"
    echo -e "${GREEN}====================================================${NC}"
    echo -e "  AnyTLS 端口        : ${anytls_port}"
    echo -e "  AnyTLS 密码        : ${anytls_pass}"
    echo -e "  AnyTLS SNI         : ${domain}"
    echo -e "  证书 SHA256 (Hex)  : ${cert_sha256_hex}"
    echo -e "  VLESS+Reality 端口 : ${vless_port}"
    echo -e "  VLESS UUID         : ${uuid}"
    echo -e "  Reality SNI        : ${reality_sni}"
    echo -e "  Reality PublicKey  : ${pub_key}"
    echo -e "  Reality ShortID    : ${short_id}"
    echo -e "${BLUE}----------------------------------------------------${NC}"

    if [[ -n "$ipv4" ]]; then
        echo -e "${YELLOW}[IPv4 分享链接]${NC}"
        echo -e "AnyTLS:"
        echo "anytls://${anytls_pass}@${ipv4}:${anytls_port}/?sni=${domain}&pcs=${cert_sha256_hex}#AnyTLS-IPv4"
        echo -e "VLESS+Reality:"
        echo "vless://${uuid}@${ipv4}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_sni}&fp=chrome&pbk=${pub_key}&sid=${short_id}&type=tcp#VLESS-Reality-IPv4"
        echo ""
    else
        echo -e "${YELLOW}[提示] 未检测到公网 IPv4 地址。${NC}"
    fi

    if [[ -n "$ipv6" ]]; then
        echo -e "${YELLOW}[IPv6 分享链接]${NC}"
        echo -e "AnyTLS:"
        echo "anytls://${anytls_pass}@[${ipv6}]:${anytls_port}/?sni=${domain}&pcs=${cert_sha256_hex}#AnyTLS-IPv6"
        echo -e "VLESS+Reality:"
        echo "vless://${uuid}@[${ipv6}]:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_sni}&fp=chrome&pbk=${pub_key}&sid=${short_id}&type=tcp#VLESS-Reality-IPv6"
        echo ""
    else
        echo -e "${YELLOW}[提示] 未检测到公网 IPv6 地址。${NC}"
    fi

    read -rp "按回车键返回主菜单..."
}

# ------------------------------------------------------------------------------
# 菜单 3: 检查并开启 BBR
# ------------------------------------------------------------------------------
enable_bbr() {
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")

    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "\n${GREEN}[提示] 本机已开启 BBR (tcp_congestion_control = bbr)，无需重复操作。${NC}"
        read -rp "按回车键返回主菜单..."
        return
    fi

    echo -e "\n${BLUE}[信息] 检测到本机未开启 BBR，正在配置并开启 ...${NC}"
    # 清理旧配置中冲突项
    if [[ -f /etc/sysctl.conf ]]; then
        sed -i '/net\.core\.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf
    fi

    mkdir -p /etc/sysctl.d
    cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1

    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${GREEN}[成功] BBR 已成功开启！${NC}"
    else
        echo -e "${RED}[警告] 尝试开启 BBR 失败，请检查当前内核版本是否 >= 4.9 (${uname -r})。${NC}"
    fi
    read -rp "按回车键返回主菜单..."
}

# ------------------------------------------------------------------------------
# 主循环
# ------------------------------------------------------------------------------
main() {
    check_root
    ensure_deps
    install_shortcut

    while true; do
        show_status_banner
        echo -e "  ${BOLD}1.${NC} 安装 / 更新 sing-box (官方脚本)"
        echo -e "  ${BOLD}2.${NC} 配置 AnyTLS 和 VLESS+Reality"
        echo -e "  ${BOLD}3.${NC} 检查并开启 BBR"
        echo -e "  ${BOLD}0.${NC} 退出"
        echo -e "${BLUE}====================================================${NC}"
        read -rp "请输入选项 [0-3]: " choice

        case "$choice" in
            1) install_sing_box ;;
            2) configure_protocols ;;
            3) enable_bbr ;;
            0) echo -e "${GREEN}已退出。${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项，请输入 0-3。${NC}"; sleep 1 ;;
        esac
    done
}

main "$@"