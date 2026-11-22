#!/usr/bin/env bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 路径配置
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CERT_DIR="${CONFIG_DIR}/cert"
LINKS_FILE="${CONFIG_DIR}/links.txt"
SCRIPT_PATH="/usr/local/bin/sb"

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}" && exit 1

# 自动注册 sb 快捷命令
install_shortcut() {
    local current_script
    current_script=$(readlink -f "$0")
    if [[ "$current_script" != "$SCRIPT_PATH" ]]; then
        cp -f "$current_script" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
}

# 检查基础依赖
check_deps() {
    local deps=("curl" "openssl")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}正在安装必要依赖: ${missing[*]} ...${PLAIN}"
        if command -v apt-get &>/dev/null; then
            apt-get update -y && apt-get install -y "${missing[@]}"
        elif command -v dnf &>/dev/null; then
            dnf install -y "${missing[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y "${missing[@]}"
        elif command -v apk &>/dev/null; then
            apk add --no-cache "${missing[@]}"
        else
            echo -e "${RED}无法自动安装依赖，请手动安装: ${missing[*]}${PLAIN}"
            exit 1
        fi
    fi
}

# 检查 sing-box 安装状态与版本
check_singbox_status() {
    if command -v sing-box &>/dev/null; then
        LOCAL_VER=$(sing-box version 2>/dev/null | awk '/sing-box version/ {print $3}')
        [[ -z "$LOCAL_VER" ]] && LOCAL_VER="未知"
        INSTALL_STATUS="${GREEN}已安装 (v${LOCAL_VER})${PLAIN}"
    else
        LOCAL_VER=""
        INSTALL_STATUS="${RED}未安装${PLAIN}"
    fi

    # 获取 GitHub 最新版本（设置 3 秒超时防止卡死）
    LATEST_VER=$(curl -s --max-time 3 https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    if [[ -z "$LATEST_VER" ]]; then
        VER_STATUS="${YELLOW}获取最新版本失败${PLAIN}"
    elif [[ -z "$LOCAL_VER" ]]; then
        VER_STATUS="${YELLOW}最新可用版本: v${LATEST_VER}${PLAIN}"
    elif [[ "$LOCAL_VER" == "$LATEST_VER" ]]; then
        VER_STATUS="${GREEN}已是最新版本 (v${LATEST_VER})${PLAIN}"
    else
        VER_STATUS="${YELLOW}发现新版本: v${LATEST_VER} (建议更新)${PLAIN}"
    fi
}

# 菜单 1：官方脚本安装 sing-box
install_singbox() {
    echo -e "${BLUE}正在调用官方安装脚本安装 sing-box...${PLAIN}"
    bash <(curl -fsSL https://sing-box.app/install.sh)
    if command -v sing-box &>/dev/null; then
        systemctl enable sing-box &>/dev/null
        echo -e "${GREEN}sing-box 安装完成！${PLAIN}"
    else
        echo -e "${RED}sing-box 安装似乎失败了，请检查网络或上方日志。${PLAIN}"
    fi
}

# 菜单 2：配置 AnyTLS 和 VLESS+Reality
configure_protocols() {
    if ! command -v sing-box &>/dev/null; then
        echo -e "${RED}请先选择菜单 1 安装 sing-box！${PLAIN}"
        return
    fi

    check_deps
    mkdir -p "$CONFIG_DIR" "$CERT_DIR"

    echo -e "\n${BLUE}=== 配置 AnyTLS 与 VLESS+Reality ===${PLAIN}"
    
    # 输入域名
    read -rp "请输入要使用的伪装/证书域名 (例如 www.microsoft.com 或你的域名): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        DOMAIN="www.microsoft.com"
        echo -e "${YELLOW}未输入域名，默认使用: ${DOMAIN}${PLAIN}"
    fi

    # 输入端口
    read -rp "请输入 AnyTLS 监听端口 [默认 8443]: " ANYTLS_PORT
    [[ -z "$ANYTLS_PORT" ]] && ANYTLS_PORT=8443

    read -rp "请输入 VLESS+Reality 监听端口 [默认 443]: " REALITY_PORT
    [[ -z "$REALITY_PORT" ]] && REALITY_PORT=443

    if [[ "$ANYTLS_PORT" == "$REALITY_PORT" ]]; then
        echo -e "${RED}错误：两个协议不能使用相同的端口！${PLAIN}"
        return
    fi

    echo -e "${YELLOW}正在生成密钥与自签证书...${PLAIN}"

    # 1. 生成 AnyTLS 自签证书及密码
    ANYTLS_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    CERT_PATH="${CERT_DIR}/anytls.crt"
    KEY_PATH="${CERT_DIR}/anytls.key"

    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$KEY_PATH" -out "$CERT_PATH" \
        -subj "/CN=${DOMAIN}" -days 3650 &>/dev/null

    # 提取整张证书 DER 格式的 SHA-256 十六进制指纹（64位小写字符）
    CERT_PCS=$(openssl x509 -in "$CERT_PATH" -outform der | \
        openssl dgst -sha256 | \
        awk '{print $NF}')

    # 2. 生成 VLESS+Reality 密钥对、UUID 和 ShortID
    REALITY_UUID=$(sing-box generate uuid)
    KEYPAIR=$(sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/ {print $2}')
    PUBLIC_KEY=$(echo "$KEYPAIR" | awk '/PublicKey/ {print $2}')
    SHORT_ID=$(openssl rand -hex 4)

    # 3. 写入 sing-box 配置文件
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
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "password": "${ANYTLS_PASS}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [
        {
          "uuid": "${REALITY_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DOMAIN}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
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

    # 校验配置并重启服务
    if ! sing-box check -c "$CONFIG_FILE"; then
        echo -e "${RED}配置文件校验失败，请检查输入的域名或 sing-box 版本！${PLAIN}"
        return
    fi

    systemctl restart sing-box
    sleep 1
    if ! systemctl is-active --quiet sing-box; then
        echo -e "${RED}sing-box 启动失败，请运行 journalctl -u sing-box -e 查看日志。${PLAIN}"
        return
    fi

    # 4. 获取公网 IPv4 和 IPv6
    IPV4=$(curl -s4 --max-time 4 https://api.ipify.org || curl -s4 --max-time 4 https://ifconfig.me)
    IPV6=$(curl -s6 --max-time 4 https://api64.ipify.org || curl -s6 --max-time 4 https://ifconfig.me)

    # 生成并保存分享链接
    > "$LINKS_FILE"
    echo -e "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LINKS_FILE"
    echo -e "伪装/证书域名: ${DOMAIN}" >> "$LINKS_FILE"
    echo -e "证书 SHA-256 (Hex): ${CERT_PCS}\n" >> "$LINKS_FILE"

    if [[ -n "$IPV4" ]]; then
        ANYTLS_V4="anytls://${ANYTLS_PASS}@${IPV4}:${ANYTLS_PORT}/?sni=${DOMAIN}&pcs=${CERT_PCS}#AnyTLS-IPv4"
        REALITY_V4="vless://${REALITY_UUID}@${IPV4}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-IPv4"
        {
            echo "=== IPv4 分享链接 ==="
            echo "[AnyTLS IPv4]:"
            echo "${ANYTLS_V4}"
            echo ""
            echo "[VLESS+Reality IPv4]:"
            echo "${REALITY_V4}"
            echo ""
        } >> "$LINKS_FILE"
    fi

    if [[ -n "$IPV6" ]]; then
        ANYTLS_V6="anytls://${ANYTLS_PASS}@[${IPV6}]:${ANYTLS_PORT}/?sni=${DOMAIN}&pcs=${CERT_PCS}#AnyTLS-IPv6"
        REALITY_V6="vless://${REALITY_UUID}@[${IPV6}]:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-IPv6"
        {
            echo "=== IPv6 分享链接 ==="
            echo "[AnyTLS IPv6]:"
            echo "${ANYTLS_V6}"
            echo ""
            echo "[VLESS+Reality IPv6]:"
            echo "${REALITY_V6}"
            echo ""
        } >> "$LINKS_FILE"
    fi

    echo -e "\n${GREEN}配置写入并启动成功！${PLAIN}"
    show_links
}

# 菜单 3：显示当前已安装分享链接
show_links() {
    if [[ -f "$LINKS_FILE" && -s "$LINKS_FILE" ]]; then
        echo -e "\n${BLUE}======================================================${PLAIN}"
        cat "$LINKS_FILE"
        echo -e "${BLUE}======================================================${PLAIN}"
    else
        echo -e "${YELLOW}未找到已生成的分享链接，请先执行菜单 2 进行配置。${PLAIN}"
    fi
}

# 菜单 4：检查并开启 BBR
enable_bbr() {
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local current_qdisc
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${GREEN}本机已开启 BBR (拥塞控制: ${current_cc}, 队列算法: ${current_qdisc})，无需重复操作。${PLAIN}"
        return
    fi

    echo -e "${YELLOW}当前拥塞控制算法为: ${current_cc:-未知}，正在配置开启 BBR...${PLAIN}"
    
    # 清理旧的重复配置并写入 sysctl
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    
    sysctl -p &>/dev/null

    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == "bbr" ]]; then
        echo -e "${GREEN}BBR 开启成功！${PLAIN}"
    else
        echo -e "${RED}BBR 开启失败，可能是当前系统内核版本过低（需 >= 4.9）或容器环境（如 OpenVZ/LXC）限制。${PLAIN}"
    fi
}

# 主菜单循环
main_menu() {
    install_shortcut
    while true; do
        clear
        check_singbox_status
        echo -e "${BLUE}==========================================${PLAIN}"
        echo -e "${BLUE}          sing-box 极简管理脚本           ${PLAIN}"
        echo -e "${BLUE}==========================================${PLAIN}"
        echo -e " 安装状态 : ${INSTALL_STATUS}"
        echo -e " 版本检测 : ${VER_STATUS}"
        echo -e "${BLUE}------------------------------------------${PLAIN}"
        echo -e "  ${GREEN}1.${PLAIN} 安装 / 更新 sing-box (官方脚本)"
        echo -e "  ${GREEN}2.${PLAIN} 配置 AnyTLS 和 VLESS+Reality"
        echo -e "  ${GREEN}3.${PLAIN} 显示当前已生成的分享链接"
        echo -e "  ${GREEN}4.${PLAIN} 检查并开启 BBR"
        echo -e "  ${GREEN}0.${PLAIN} 退出脚本"
        echo -e "${BLUE}==========================================${PLAIN}"
        read -rp "请输入选项 [0-4]: " choice

        case "$choice" in
            1) install_singbox ;;
            2) configure_protocols ;;
            3) show_links ;;
            4) enable_bbr ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效输入，请输入 0 到 4 之间的数字。${PLAIN}" ;;
        esac
        echo ""
        read -rp "按回车键返回主菜单..."
    done
}

main_menu