#!/bin/bash

TOKEN=
ZONE_ID=
ZONE_NAME=
RECORD_TYPE=A
RULE_PROXIABLE=true
RULE_PROXIED=true
RULE_LOCKED=false

# Get your RECORD_ID by running
# curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" | jq '.'
RECORD_ID=
RECORD_NAME=

PUBLIC_IP=$(curl -s 'icanhazip.com')
STORED_IP=$(cat cloudflare-dynamic-ip-last.txt)

is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        for octet in $(echo $ip | tr '.' ' '); do
            if [[ $octet -lt 0 || $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

is_valid_ipv6() {
    local ip=$1
    if [[ $ip =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]] || \
       [[ $ip =~ ^::([0-9a-fA-F]{1,4}:){0,7}[0-9a-fA-F]{1,4}$ ]] || \
       [[ $ip =~ ^([0-9a-fA-F]{1,4}:){1,7}:$ ]]; then
        return 0
    else
        return 1
    fi
}

echo "Fetching current public IP address..."
PUBLIC_IP=$(curl -s 'icanhazip.com')
echo "Current public IP address: $PUBLIC_IP"

echo "Fetching stored IP address from file..."
STORED_IP=$(cat cloudflare-dynamic-ip-last.txt)
echo "Stored IP address: $STORED_IP"

if (is_valid_ipv4 "$PUBLIC_IP" || is_valid_ipv6 "$PUBLIC_IP") && \
   (is_valid_ipv4 "$STORED_IP" || is_valid_ipv6 "$STORED_IP"); then
    echo "Both IP addresses are valid."

    if [[ $STORED_IP != $PUBLIC_IP ]]; then
        echo "Public IP address has changed. Updating Cloudflare DNS record..."

        OUTPUT=$(wget --quiet \
            --method PUT \
            --timeout=0 \
            --header 'Content-Type: application/json' \
            --header="Authorization: Bearer $TOKEN" \
            --body-data="{
                \"id\": \"$RECORD_ID\",
                \"type\": \"$RECORD_TYPE\",
                \"name\": \"$RECORD_NAME\",
                \"content\": \"$PUBLIC_IP\",
                \"proxiable\": $RULE_PROXIABLE,
                \"proxied\": $RULE_PROXIED,
                \"ttl\": 1,
                \"locked\": $RULE_LOCKED,
                \"zone_id\": \"$ZONE_ID\",
                \"zone_name\": \"$ZONE_NAME\",
                \"meta\": {
                        \"auto_added\": false,
                        \"managed_by_apps\": false,
                        \"managed_by_argo_tunnel\": false
                }
        }" \
             -O - "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID")

        IP_UPDATED=$(echo $OUTPUT | jq -r '.result.content')
        echo "Cloudflare DNS record updated to new IP address: $IP_UPDATED"

        echo $IP_UPDATED > cloudflare-dynamic-ip-last.txt
        echo "Updated IP saved to cloudflare-dynamic-ip-last.txt."

        RESULT=$(echo $OUTPUT | jq -r '.success')
        if [[ $RESULT == 'true' ]]; then
            echo "Cloudflare dynamic IP address update success for IP: $IP_UPDATED"
        else
            echo "Cloudflare dynamic IP address update failed. Error details:"
            echo $OUTPUT
        fi
    else
        echo "Public IP address is the same as the stored IP. No update necessary."
    fi
else
    echo "Error: Invalid IP format detected for either PUBLIC_IP or STORED_IP."
    echo "Public IP address: $PUBLIC_IP"
    echo "Stored IP address: $STORED_IP"
fi
