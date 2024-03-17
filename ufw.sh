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
