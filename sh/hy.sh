#!/bin/bash

# 提示用户输入自定义的 listen 端口和密码
read -p "请输入伪装域名（默认为 www.bing.com）: " domain
domain=${domain:-www.bing.com}

read -p "请输入监听端口（默认为443）: " listen_port
listen_port=${listen_port:-443}

read -p "请输入密码（默认为password）: " password
password=${password:-password}

# 询问是否启用增强伪装
read -p "是否加强伪装.需要占用80 443（y/n）：" enhance_masking
enhance_masking=${enhance_masking:-y}

# 1. 一键安装 Hysteria2
echo "正在安装 Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/)

# 2. 使用自签证书
echo "正在生成自签证书..."
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/zs.key -out /etc/hysteria/zs.crt \
    -days 36500 -subj "/CN=$domain" \
    -addext "subjectAltName=DNS:$domain" \
&& sudo chown hysteria /etc/hysteria/zs.key /etc/hysteria/zs.crt

# 3. 创建服务器配置文件
echo "正在生成配置文件..."
if [ "$enhance_masking" == "y" ] || [ "$enhance_masking" == "Y" ]; then
    # 增强伪装：保留伪装相关配置
    cat << EOF > /etc/hysteria/config.yaml
listen: :$listen_port

tls:
  cert: /etc/hysteria/zs.crt
  key: /etc/hysteria/zs.key

auth:
  type: password
  password: $password
  
masquerade:
  type: proxy
  proxy:
    url: https://$domain
    rewriteHost: true
  listenHTTP: :80 
  listenHTTPS: :443 
  forceHTTPS: true 
EOF
else
    # 不启用伪装：删除伪装相关配置
    cat << EOF > /etc/hysteria/config.yaml
listen: :$listen_port

tls:
  cert: /etc/hysteria/zs.crt
  key: /etc/hysteria/zs.key

auth:
  type: password
  password: $password

masquerade:
  type: proxy
  proxy:
    url: https://$domain
    rewriteHost: true
EOF
fi

echo "设置开机自启"
systemctl enable hysteria-server.service
systemctl restart hysteria-server.service

# 显示本机的外网 IP 地址
echo "本机的外网 IP 地址："
external_ip=$(curl -s ifconfig.me) # 获取外网 IP 地址
echo $external_ip

# 输出完成信息
echo "Hysteria2 安装与配置完成！"
echo "伪装域名：$domain"
echo "监听端口：$listen_port"
echo "密码：$password"
echo "证书内容："
cat /etc/hysteria/zs.crt
