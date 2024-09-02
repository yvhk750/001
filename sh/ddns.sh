#!/bin/bash

# Cloudflare API Token (需要替换为你自己的)
CF_API_TOKEN="your_cloudflare_api_token"

# Cloudflare Zone ID (需要替换为你的Zone ID)
CF_ZONE_ID="your_zone_id"

# 需要更新的DNS记录名称 (如 "example.com" 或 "sub.example.com")
DNS_RECORD_NAME="your_dns_record_name"

# 获取外部IPv4地址
IPV4=$(curl -s https://ipv4.icanhazip.com)

# 获取外部IPv6地址
IPV6=$(curl -s https://ipv6.icanhazip.com)

# 更新IPv4记录
if [ -n "$IPV4" ]; then
    CF_RECORD_ID_IPV4=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${DNS_RECORD_NAME}&type=A" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r .result[0].id)

    if [ -z "$CF_RECORD_ID_IPV4" ] || [ "$CF_RECORD_ID_IPV4" == "null" ]; then
        echo "无法获取IPv4 DNS记录ID，请检查你的域名和API设置。"
    else
        CURRENT_IPV4=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID_IPV4}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" | jq -r .result.content)

        if [ "$IPV4" != "$CURRENT_IPV4" ]; then
            echo "IPv4地址已更改，更新DNS记录..."
            RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID_IPV4}" \
                -H "Authorization: Bearer ${CF_API_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"${DNS_RECORD_NAME}\",\"content\":\"${IPV4}\",\"ttl\":120,\"proxied\":false}")

            if echo "$RESPONSE" | grep -q "\"success\":true"; then
                echo "IPv4 DNS记录已成功更新为 $IPV4"
            else
                echo "IPv4 DNS记录更新失败: $RESPONSE"
            fi
        else
            echo "IPv4地址未更改，无需更新。"
        fi
    fi
fi

# 更新IPv6记录
if [ -n "$IPV6" ]; then
    CF_RECORD_ID_IPV6=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=${DNS_RECORD_NAME}&type=AAAA" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r .result[0].id)

    if [ -z "$CF_RECORD_ID_IPV6" ] || [ "$CF_RECORD_ID_IPV6" == "null" ]; then
        echo "无法获取IPv6 DNS记录ID，请检查你的域名和API设置。"
    else
        CURRENT_IPV6=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID_IPV6}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" | jq -r .result.content)

        if [ "$IPV6" != "$CURRENT_IPV6" ]; then
            echo "IPv6地址已更改，更新DNS记录..."
            RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID_IPV6}" \
                -H "Authorization: Bearer ${CF_API_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"AAAA\",\"name\":\"${DNS_RECORD_NAME}\",\"content\":\"${IPV6}\",\"ttl\":120,\"proxied\":false}")

            if echo "$RESPONSE" | grep -q "\"success\":true"; then
                echo "IPv6 DNS记录已成功更新为 $IPV6"
            else
                echo "IPv6 DNS记录更新失败: $RESPONSE"
            fi
        else
            echo "IPv6地址未更改，无需更新。"
        fi
    fi
fi
