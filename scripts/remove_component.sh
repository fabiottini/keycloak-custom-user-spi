#!/bin/bash

# =====================================================
# USER FEDERATION COMPONENT REMOVAL SCRIPT
# =====================================================
# Removes existing User Federation components
# in Keycloak to allow clean reinstallation.
#
# Purpose:
#   Removes all User Federation components that match
#   the configured SPI_NAME from the Keycloak realm.
#
# Process:
#   1. Loads configuration from .env
#   2. Obtains administrative access token
#   3. Queries existing components
#   4. Removes matching components
#
# Usage:
#   ./remove_component.sh
#
# Requirements:
#   - Keycloak running
#   - Realm already created
#   - Valid .env configuration file
#   - curl and jq installed
# =====================================================

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

echo "========================================"
echo "User Federation Component Removal"
echo "========================================"
echo ""

# Load configuration (without full init to avoid duplicate output)
load_config

# =====================================================
# AUTHENTICATION
# =====================================================

# -----------------------------------------------------
# Obtain Administrative Access Token
# -----------------------------------------------------
echo "Obtaining administrative access token..."
ADMIN_TOKEN=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=$KEYCLOAK_ADMIN_USER" \
    -d "password=$KEYCLOAK_ADMIN_PASSWORD" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
    echo "ERROR: Failed to obtain admin token"
    echo "HINT: Verify admin credentials in .env file"
    exit 1
fi
echo "Admin token obtained successfully"
echo ""

# =====================================================
# COMPONENT REMOVAL
# =====================================================

# -----------------------------------------------------
# Query Existing Components
# -----------------------------------------------------
echo "Searching for existing User Federation components..."
COMPONENTS=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/components?type=org.keycloak.storage.UserStorageProvider" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json")

# Check if realm exists
if echo "$COMPONENTS" | jq -e 'type == "object" and has("error")' > /dev/null 2>&1; then
    echo "WARNING: Realm '$REALM_NAME' may not exist or is not accessible"
    echo "Skipping component removal"
    exit 0
fi

# Extract component IDs that match our SPI name or provider ID
COMPONENT_IDS=$(echo "$COMPONENTS" | jq -r ".[] | select(.name == \"$SPI_NAME\" or .providerId == \"$SPI_PROVIDER_ID\") | .id")

if [ -z "$COMPONENT_IDS" ]; then
    echo "No existing User Federation components found matching:"
    echo "  Name: $SPI_NAME"
    echo "  Provider ID: $SPI_PROVIDER_ID"
    echo ""
    echo "Nothing to remove."
    exit 0
fi

# -----------------------------------------------------
# Remove Components
# -----------------------------------------------------
echo "Found components to remove:"
echo "$COMPONENT_IDS" | while read -r component_id; do
    if [ -n "$component_id" ]; then
        COMPONENT_INFO=$(echo "$COMPONENTS" | jq -r ".[] | select(.id == \"$component_id\") | {name: .name, providerId: .providerId}")
        COMPONENT_NAME=$(echo "$COMPONENT_INFO" | jq -r '.name')
        COMPONENT_PROVIDER=$(echo "$COMPONENT_INFO" | jq -r '.providerId')
        echo "  - ID: $component_id"
        echo "    Name: $COMPONENT_NAME"
        echo "    Provider: $COMPONENT_PROVIDER"
    fi
done
echo ""

REMOVAL_COUNT=0
echo "$COMPONENT_IDS" | while read -r component_id; do
    if [ -n "$component_id" ]; then
        echo "Removing component: $component_id"
        
        HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE \
            "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/components/$component_id" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json")
        
        if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
            echo "  ✅ Component removed successfully (HTTP $HTTP_CODE)"
            REMOVAL_COUNT=$((REMOVAL_COUNT + 1))
        else
            echo "  ⚠️  Failed to remove component (HTTP $HTTP_CODE)"
        fi
    fi
done

echo ""
echo "========================================"
echo "Component Removal Complete"
echo "========================================"
echo ""
echo "Components processed for removal"
echo ""

