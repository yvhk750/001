<details>

<summary>走一波</summary>

```
更新安装软件 
apt update -y
apt update -y && apt upgrade -y
apt install wget curl sudo vim git -y

安装bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf     
echo "net.ipv4.icmp_echo_ignore_all=1" >> /etc/sysctl.conf  
sysctl -p

开关IPV6
curl -O https://github.com/yvhk750/001/raw/main/sh/ipv6.sh && chmod +x ipv6.sh && sudo ./ipv6.sh

安装ssh 
wget https://github.com/yvhk750/001/raw/main/sh/key.sh --no-check-certificate&& bash key.sh yvhk750

一键安装 Hysteria2
curl -O https://raw.githubusercontent.com/yvhk750/001/refs/heads/main/sh/hy.sh && chmod +x hy.sh && ./hy.sh

caddy NaiveProxy 与 Trojan（支持CF优选IP） 
bash <(curl -s https://raw.githubusercontent.com/yvhk750/001/main/sh/nt.sh) 域名 账号 密码

安装 docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

ufw防火墙控制docker 开放80 443 52022
wget -N --no-check-certificate https://github.com/yvhk750/001/raw/main/sh/ufw.sh && bash ufw.sh


安装 alist
curl -fsSL "https://alist.nn.ci/v3.sh" | bash -s install  
更新
curl -fsSL "https://alist.nn.ci/v3.sh" | bash -s update
卸载
curl -fsSL "https://alist.nn.ci/v3.sh" | bash -s uninstall

alist+arist
docker run -d --restart=always -v /etc/alist:/opt/alist/data -v /mnt:/mnt -p 5244:5244 -e PUID=0 -e PGID=0 -e UMASK=022 --name="alist" xhofe/alist-aria2:latest


# 手动设置一个密码,`NEW_PASSWORD`是指你需要设置的密码
docker exec -it alist ./alist admin set NEW_PASSWORD
```
</details>

<details>

<summary>caddy命令</summary>

```
配置重载
systemctl reload caddy
停止
systemctl stop caddy
格式化
caddy fmt /etc/caddy/Caddyfile --overwrite
启动
systemctl start caddy
服务状态
systemctl status caddy
```
</details>


<details>

<summary>Hysteria2</summary>

```
#一键安装Hysteria2
bash <(curl -fsSL https://get.hy2.sh/)

#使用自签证书
```
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/bing.key -out /etc/hysteria/bing.crt \
    -days 36500 -subj "/CN=www.bing.com" \
    -addext "subjectAltName=DNS:www.bing.com,DNS:bing.com" \
&& sudo chown hysteria /etc/hysteria/bing.key /etc/hysteria/bing.crt
```
# 端口跳跃
1，     sudo vim /etc/sysctl.conf
        # 添加或修改以下行，如已开启则跳过此步骤
        net.ipv4.ip_forward=1
        # 应用更改
        sudo sysctl -p
2，     sudo vim /etc/ufw/before.rules 
        sudo vim /etc/ufw/before6.rules

```
*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

-A PREROUTING -p udp --dport 10000:10010 -j REDIRECT --to-port 443

-A POSTROUTING -j MASQUERADE

COMMIT
```
sudo ufw allow 10000:10010/udp

#启动Hysteria2
systemctl start hysteria-server.service
#重启Hysteria2
systemctl restart hysteria-server.service
#查看Hysteria2状态
systemctl status hysteria-server.service
#停止Hysteria2
systemctl stop hysteria-server.service
#设置开机自启
systemctl enable hysteria-server.service
#查看日志
journalctl -u hysteria-server.service
```

服务器配置文件
```
cat << EOF > /etc/hysteria/config.yaml
listen: :443 #监听端口

#使用CA证书
#acme:
#  domains:
#    - a.com #你的域名，需要先解析到服务器ip
#  email: test@email.com

#使用自签证书
tls:
  cert: /etc/hysteria/bing.crt
  key: /etc/hysteria/bing.key

auth:
  type: password
  password: qwert5tgb #设置认证密码
  
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com #伪装网址
    rewriteHost: true
  listenHTTP: :80 
  listenHTTPS: :443 
  forceHTTPS: true 
EOF
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

docker compose 更新命令
docker compose pull
docker compose up -d

```

</details>

<details>

<summary>ufw 防火墙</summary>

```
  安装
apt-get install ufw
  状态
ufw status
  开启tcp与udp端口
ufw allow 22
  删除端口
ufw delete allow 22
  启动
ufw enable
  停止
ufw disable
重置所有规则：
sudo ufw reset


------Docker网络之防火墙-----

#修改ufw默认的配置
nano /etc/default/ufw
#把DEFAULT_FORWARD_POLICY修改成下面这样
DEFAULT_FORWARD_POLICY="ACCEPT"

#修改docker.service配置，防止它修改防火墙规则
##docker.service可能在以下3个路径，选任一修改即可##
/usr/lib/systemd/system/docker.service
/etc/systemd/system/multi-user.target.wants/
/lib/systemd/system/docker.service
#修改文件
nano /usr/lib/systemd/system/docker.service
#找到 ExecStart 字段
#默认为：
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
改为
ExecStart=/usr/bin/dockerd --iptables=false -H fd:// --containerd=/run/containerd/containerd.sock

#修改docker的默认配置。注释DOCKER_OPTS这行，在参数后添加添加--iptables=false
nano /etc/default/docker
#修改文件
DOCKER_OPTS="--dns 8.8.8.8 --dns 8.8.4.4 --iptables=false"

#修改/etc/ufw/before.rules以使容器内部可以访问外网，否则任何容器内的联网操作都会被禁止
nano /etc/ufw/before.rules
#在`*filter`前面添加下面内容，根据自己具体网段往后自行添加
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING ! -s 172.17.0.0/16 -j MASQUERADE
-A POSTROUTING ! -s 172.18.0.0/16 -j MASQUERADE
-A POSTROUTING ! -s 172.xx.0.0/16 -j MASQUERADE
COMMIT

#重启docker
systemctl daemon-reload && systemctl restart docker

#若不生效重启服务器
```
</details>
