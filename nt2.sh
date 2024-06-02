#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 检查 NaïveProxy 安装状态
check_naiveproxy_status() {
  if command -v caddy &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# 安装 NaïveProxy
install_naiveproxy() {
  echo "正在安装 NaïveProxy"

  # 读取用户输入的域名
  read -p "请输入您的已解析域名: " domain

  if [[ -z "${domain}" ]]; then
    echo "域名不能为空。"
    return 1
  fi

  # 读取用户输入的端口
  read -p "请输入您的端口: " proxyport

  if [[ -z "${proxyport}" ]]; then
    echo "端口不能为空。"
    return 1
  fi
  
  # 读取用户输入的用户名
  read -p "请输入您的用户名: " proxyname

  if [[ -z "${proxyname}" ]]; then
    echo "用户名不能为空。"
    return 1
  fi

  # 读取用户输入的密码
  read -p "请输入您的密码: " proxypwd

  if [[ -z "${proxypwd}" ]]; then
    echo "密码不能为空。"
    return 1
  fi

  # 读取用户输入的伪装网站地址
  read -p "请输入您的伪装网站地址: " proxysite

  if [[ -z "${proxysite}" ]]; then
    echo "伪装网站地址不能为空。"
    return 1
  fi
  
# 下载 caddy.zip 文件
  echo "正在下载 caddy.zip 文件"
  if ! wget -O caddy.zip https://github.com/yvhk750/001/raw/main/caddy.zip; then
    echo "无法下载 caddy.zip 文件，请检查网络连接。"
    return 1
  fi

# 解压 caddy.zip 文件
  echo "正在解压 caddy.zip 文件"
  if ! unzip -o caddy.zip; then
    echo "无法解压 caddy.zip 文件。"
    return 1
  fi

# 移动 Caddy 可执行文件到 /usr/bin/ 并确保具有执行权限
  echo "正在移动 Caddy 可执行文件"
  if ! mv caddy /usr/bin/; then
    echo "无法将 Caddy 移动到 /usr/bin/"
    return 1
  fi

  if ! chmod +x /usr/bin/caddy; then
    echo "无法为 Caddy 设置执行权限"
    return 1
  else
    echo "Caddy成功移动到 /usr/bin"
  fi

  # 创建并配置 Caddyfile
  echo "正在创建并配置 Caddyfile"
  if ! mkdir -p /etc/caddy && touch /etc/caddy/Caddyfile; then
    echo "无法创建 Caddyfile"
    return 1
  fi

  cat <<EOF > /etc/caddy/Caddyfile
{
	order trojan before route
	order forward_proxy before trojan
	admin off
	log {
		output file /var/log/caddy/error.log
		level ERROR
	}
	email admin@gmail.com

	servers :$proxyport {
		listener_wrappers {
			trojan
		}
	}
	trojan {
		caddy
		no_proxy
		users $proxypwd 
	}
}

:$proxyport, $domain:$proxyport {
	tls {
		ciphers TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
		curves x25519 secp521r1 secp384r1 secp256r1
	}

	forward_proxy {
		basic_auth $proxyname $proxypwd 
		hide_ip
		hide_via
		probe_resistance
	}

	trojan {
		connect_method
		websocket
	}

	@host {
		host $domain
	}
	route @host {
		header {
			Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		}
		reverse_proxy https://$proxysite {
			header_up Host {upstream_hostport}
			header_up X-Forwarded-Host {host}
		}
	}
}
EOF

  # 格式化并验证 Caddyfile
  if ! caddy fmt --overwrite /etc/caddy/Caddyfile || ! caddy validate --config /etc/caddy/Caddyfile; then
    echo "Caddyfile 格式或验证失败"
    return 1
  fi

  # 确保存在 Caddy 用户组和用户
  if ! getent group caddy > /dev/null; then
    groupadd --system caddy
  fi

  if ! id "caddy" > /dev/null 2>&1; then
    useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy
  fi

  # 创建 systemd 服务并配置 Caddy 服务
  if ! touch /etc/systemd/system/caddy.service; then
    echo "无法创建 caddy.service"
    return 1
  fi

  cat <<EOF > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  # 重载 systemd 守护进程并启动 Caddy 服务
  systemctl daemon-reload
  if ! systemctl start caddy; then
    echo "Caddy 服务启动失败"
    return 1
  fi

  # 确认 Caddy 服务状态
  if systemctl status caddy | grep -q "Active: active (running)"; then
    echo "NaïveProxy 安装成功"
  else
    echo "Caddy 未正确启动"
    return 1
  fi

  # 输出 NaïveProxy 配置
  # 获取本机IP地址
  HOST_IP=$(curl -s http://checkip.amazonaws.com)

  # 获取IP所在国家
  IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)

  # 输出 NaïveProxy 配置
  echo -e "${GREEN}直连效果好用这---稳${RESET}"
  echo "naive+https://${proxyname}:${proxypwd}@${domain}:${proxyport}#${IP_COUNTRY}"

  # 输出 trojan 配置
  echo -e "${GREEN}直连效果不理想用这优选IP吧${RESET}"
  echo "trojan://${proxypwd}@visa.com.hk:${proxyport}?security=tls&sni=${domain}&fp=edge&type=ws&host=${domain}#${IP_COUNTRY}"
}

# 卸载 NaïveProxy
uninstall_naiveproxy() {
  echo "正在卸载 NaïveProxy"

  # 停止 Caddy 服务
  systemctl stop caddy

  # 禁用 Caddy 服务
  systemctl disable caddy

  # 删除 Caddy 可执行文件
  rm /usr/bin/caddy

  # 删除 Caddy 的配置文件
  rm -rf /etc/caddy

  # 删除 systemd 服务配置
  rm /etc/systemd/system/caddy.service
  systemctl daemon-reload

  # 删除 Caddy 编译工具 xcaddy
  rm ~/go/bin/xcaddy

  echo "NaïveProxy 卸载成功"
}

# 显示菜单
show_menu() {
  clear
  check_naiveproxy_status
  naiveproxy_status=$?
  echo -e "${GREEN}=== NaïveProxy 管理工具 ===${RESET}"
  echo -e "${GREEN}当前状态: $(if [ ${naiveproxy_status} -eq 0 ]; then echo "${GREEN}已安装${RESET}"; else echo "${RED}未安装${RESET}"; fi)${RESET}"
  echo "1. 安装 NaïveProxy"
  echo "2. 卸载 NaïveProxy"
  echo "0. 退出"
  echo -e "${GREEN}===========================${RESET}"
  read -p "请输入选项编号: " choice
  echo ""
}

# 捕获 Ctrl+C 信号
trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

# 主循环
while true; do
  show_menu
  case "${choice}" in
    1)
      install_naiveproxy
      ;;
    2)
      uninstall_naiveproxy
      ;;
    0)
      echo -e "${GREEN}已退出 NaïveProxy${RESET}"
      exit 0
      ;;
    *)
      echo -e "${RED}无效的选项${RESET}"
      ;;
  esac
  read -p "按 enter 键继续..."
done
