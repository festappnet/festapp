#!/bin/bash

# Configuration
REGION="eu-central-1"
EXPECTED_MX="inbound-smtp.$REGION.amazonaws.com"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Auto-detect domain if not provided
if [ -z "$1" ]; then
    echo "No domain provided. Attempting to detect from AWS SES..."
    
    # Try to get identities (text output is easier to parse without jq)
    IDENTITIES=$(aws ses list-identities --region $REGION --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$IDENTITIES" ]; then
        # 1. Prefer 'bank.*' subdomain
        DETECTED=$(echo "$IDENTITIES" | grep -o 'bank\.[^[:space:]]*' | head -n 1)
        
        # 2. Fallback to any identity if 'bank' is not found
        if [ -z "$DETECTED" ]; then
             DETECTED=$(echo "$IDENTITIES" | awk '{print $2}') # awk default split by space/tab
        fi
        
        if [ -n "$DETECTED" ]; then
            DOMAIN="$DETECTED"
            echo -e "${GREEN}Detected configured identity: $DOMAIN${NC}"
        else
             DOMAIN="festapp.net"
             echo "No identities found in output. Defaulting to: $DOMAIN"
        fi
    else
        DOMAIN="festapp.net"
        echo "Failed to list identities (check AWS CLI config). Defaulting to: $DOMAIN"
    fi
else
    DOMAIN="$1"
fi

echo "Checking DNS setup for domain: $DOMAIN"
echo "-------------------------------------"

# 1. Check MX Record
echo "Checking MX Record..."
MX_RECORD=$(dig +short MX $DOMAIN)

if echo "$MX_RECORD" | grep -q "$EXPECTED_MX"; then
    echo -e "${GREEN}[OK] MX Record found: $MX_RECORD${NC}"
else
    echo -e "${RED}[FAIL] MX Record missing or incorrect.${NC}"
    echo "Expected line containing: $EXPECTED_MX"
    echo "Found: $MX_RECORD"
    echo "Action: Add MX record '10 $EXPECTED_MX' to your DNS."
fi

echo ""

# 2. Check TXT Record (_amazonses)
echo "Checking SES Verification TXT (_amazonses.$DOMAIN)..."
TXT_RECORD=$(dig +short TXT "_amazonses.$DOMAIN")

if [ -n "$TXT_RECORD" ]; then
    echo -e "${GREEN}[OK] SES Verification TXT found: $TXT_RECORD${NC}"
else
    echo -e "${RED}[WARNING] SES Verification TXT not found.${NC}"
    echo "This might be expected if you haven't verified identity yet."
    echo "Action: Check AWS Console > SES > Verified Identities for the Value."
fi

echo ""
echo "Done."
