更新安装软件 
```
apt update -y
apt install wget curl sudo vim git -y
```
安装bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf     
echo "net.ipv4.icmp_echo_ignore_all=1" >> /etc/sysctl.conf  
sysctl -p

安装ssh 端口52022
wget https://github.com/yvhk750/001/raw/main/key.sh --no-check-certificate&& bash key.sh yvhk750
