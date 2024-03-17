#!/bin/bash

# 检查是否已安装 UFW

if ! command -v ufw &> /dev/null; then
  echo "UFW 未安装，正在安装..."
  apt install -y ufw
else
  echo "UFW 已安装。"
fi

# 启用 UFW

ufw enable

# 设置默认规则

ufw default deny incoming
ufw default allow outgoing

# 允许 SSH 访问

ufw allow 52022

# 允许 HTTP 和 HTTPS 访问

ufw allow 80
ufw allow 443

# 保存规则

ufw reload

echo "UFW 已成功安装并配置。"

sudo sed -i 's/DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
sudo sed -i 's/ExecStart=.*/ExecStart=\/usr\/bin\/dockerd --iptables=false -H fd:\/\/ --containerd=\/run\/containerd\/containerd.sock/g' /usr/lib/systemd/system/docker.service
sudo sed -i 's/#DOCKER_OPTS=.*/DOCKER_OPTS="--dns 8.8.8.8 --dns 8.8.4.4 --iptables=false"/g' /etc/default/docker
sudo sed -i '1i *nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING ! -s 172.17.0.0/16 -j MASQUERADE\n-A POSTROUTING ! -s 172.18.0.0/16 -j MASQUERADE\n-A POSTROUTING ! -s 172.19.0.0/16 -j MASQUERADE\nCOMMIT' /etc/ufw/before.rules

#重启docker
systemctl daemon-reload && systemctl restart docker