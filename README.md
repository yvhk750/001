<details>

<summary>走一波</summary>

```
更新安装软件 
apt update -y
apt install wget curl sudo vim git -y

安装bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf     
echo "net.ipv4.icmp_echo_ignore_all=1" >> /etc/sysctl.conf  
sysctl -p

安装ssh 
wget https://github.com/yvhk750/001/raw/main/sh/key.sh --no-check-certificate&& bash key.sh yvhk750

caddy NaiveProxy 与 Trojan（支持CF优选IP） 
1. wget -N --no-check-certificate https://github.com/yvhk750/001/raw/main/sh/nt1.sh && bash nt1.sh
2. bash <(curl -s https://raw.githubusercontent.com/yvhk750/001/main/sh/nt.sh) 域名 账号 密码

安装 docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

ufw防火墙 开放80 443 52022
wget -N --no-check-certificate https://github.com/yvhk750/001/raw/main/sh/ufw.sh && bash ufw.sh


安装 alist
curl -fsSL "https://alist.nn.ci/v3.sh" | bash -s install  
更新
curl -fsSL "https://alist.nn.ci/v3.sh" | bash -s update
卸载
curl -fsSL "https://alist.nn.ci/v3.sh" | bash -s uninstall

alist+arist(本地目录设置位置 /opt/alist/data/abc )
docker run -d --restart=always -v /etc/alist:/opt/alist/data -v /mnt:/mnt -p 5244:5244 -e PUID=0 -e PGID=0 -e UMASK=022 --name="alist" xhofe/alist-aria2:latest

# 手动设置一个密码,`NEW_PASSWORD`是指你需要设置的密码
docker exec -it alist ./alist admin set NEW_PASSWORD
```
</details>

<details>

<summary>caddy命令</summary>

```
停止
systemctl stop caddy
格式化
caddy fmt /etc/caddy/Caddyfile --overwrite
启动
systemctl start caddy
```
</details>


<details>

<summary>docker命令</summary>

```
安装
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
查看
docker ps -a
停止
docker stop id
启动
docker start id
重启
docker restart id
删除
docker rm -f id
docker-compose启动
docker compose up -d
docker-compose停止
docker compose down
查看网络
docker inspect id
查看日志
docker logs -f id

```

</details>
