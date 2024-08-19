#!/bin/bash

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用root权限运行此脚本。"
  exit 1
fi

# 显示菜单并获取用户选择
echo "请选择操作:"
echo "1) 开启IPv6"
echo "2) 关闭IPv6"
read -p "请输入选项 (1或2): " choice

# 根据选择设置IPv6
case $choice in
  1)
    echo "开启IPv6..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
    sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
    echo "net.ipv6.conf.all.disable_ipv6 = 0" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 0" >> /etc/sysctl.conf
    sysctl -p
    echo "IPv6已开启。"
    ;;
  2)
    echo "关闭IPv6..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1
    sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
    sysctl -p
    echo "IPv6已关闭。"
    ;;
  *)
    echo "无效的选项，请输入1或2。"
    exit 1
    ;;
esac
