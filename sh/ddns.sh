#!/bin/bash


# 安装 jq: sudo apt install jq
# 设置执行权限: chmod +x ddns.sh

# 配置部分，请根据实际情况修改
API_KEY="你的Cloudflare API密钥"
EMAIL="你的Cloudflare邮箱"
ZONE_ID="你的域名对应的Zone ID"
RECORD_NAME="要更新的记录名称，例如@或www"
RECORD_TYPE="A"  # 或AAAA，根据需要修改
INTERVAL="3"  # 定时任务更新间隔，单位分

# 获取当前主机IP
IPV4=$(curl -4 ip.gs)
IPV6=$(curl -6 ip.gs)

# 更新Cloudflare DNS记录
function update_record() {
  local ip=$1
  local record_type=$2
  curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "X-Auth-Email: $EMAIL" \
  -H "X-Auth-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"type\": \"$record_type\", \"name\": \"$RECORD_NAME\", \"content\": \"$ip\"}" > /dev/null 2>&1
}

# 获取记录ID
RECORD_ID=$(curl -sX GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME&type=$RECORD_TYPE" \
  -H "X-Auth-Email: $EMAIL" \
  -H "X-Auth-Key: $API_KEY" | jq -r '.result[0].id')

# 更新IPv4记录
update_record "$IPV4" "A"

# 更新IPv6记录
update_record "$IPV6" "AAAA"

# 定时任务设置, /opt/ddns.sh 脚本位置
echo "*/$INTERVAL * * * * root /opt/ddns.sh" | crontab -
