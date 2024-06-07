#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin; export PATH

# tempfile & rm it when exit
trap 'rm -f "$TMPFILE"' EXIT; TMPFILE=$(mktemp) || exit 1

########
# Check if the number of arguments is exactly 3
if [[ $# != 3 ]]; then
  echo "Error! Usage: bash this_script.sh domain name pwd"
  exit 1
fi

# Assign arguments to variables
domain="$1"
name="$2"
pwd="$3"
########

# Your script's main logic starts here
# For example, you can print the variables to verify
echo "域名: $domain"
echo "账号: $name"
echo "密码: $pwd"


function _install(){
    caddyURL="$(wget -qO- https://api.github.com/repos/caddyserver/caddy/releases | grep -E "browser_download_url.*linux_$(dpkg --print-architecture)\.deb" | cut -f4 -d\" | head -n1)"
    naivecaddyURL="$(wget -qO- https://api.github.com/repos/lxhao61/integrated-examples/releases | grep -E "browser_download_url.*linux-$(dpkg --print-architecture)\.tar.gz" | cut -f4 -d\" | head -n1)"
    wget -O $TMPFILE $caddyURL && dpkg -i $TMPFILE
    wget -4 -O $TMPFILE $naivecaddyURL && tar -zxf $TMPFILE -C /usr/bin && chmod +x /usr/bin/caddy
}

function _config(){
    cat <<EOF >/etc/caddy/Caddyfile
{
    order trojan before route
    order forward_proxy before trojan
    admin off
    servers :443 {
        listener_wrappers {
            trojan
        }
    }
    trojan {
        caddy
        no_proxy
        users $pwd
    }
}

:443, $domain {
    forward_proxy {
        basic_auth $name $pwd
        hide_ip
        hide_via
        probe_resistance 
    }
    trojan {
        connect_method
        websocket
    }
    @host host $domain
	route @host {
		reverse_proxy localhost:5244
 }
}
EOF
    cat <<EOF >/lib/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
}

function _info(){
    systemctl enable caddy && systemctl restart caddy && sleep 3 && systemctl status caddy | grep -A 2 "service" | tee $TMPFILE
    cat <<EOF >$TMPFILE
$(date)
naive+https://$name:$pwd@$domain:443#naive

trojan://$pwd@visa.com.hk:443?security=tls&sni=$domain&type=ws&host=$domain#trojan

Visit: https://$domain
EOF
    cat $TMPFILE | tee /var/log/${TMPFILE##*/} && echo && echo $(date) Info saved: /var/log/${TMPFILE##*/}
}

function main(){
    _install
    _config
    _info
}

main
