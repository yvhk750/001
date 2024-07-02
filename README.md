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
