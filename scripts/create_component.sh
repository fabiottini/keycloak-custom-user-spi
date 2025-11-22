#!/bin/bash

# =====================================================
# USER FEDERATION COMPONENT CREATION SCRIPT
# =====================================================
# Creates and configures the User Federation component
# in Keycloak to enable the Custom User Storage Provider.
#
# Purpose:
#   Registers the custom SPI as a User Federation provider within
#   the configured Keycloak realm, connecting it to the custom
#   user database for authentication operations.
#
# Process:
#   1. Loads configuration from .env
#   2. Obtains administrative access token
#   3. Retrieves realm ID (required as parentId)
#   4. Creates User Federation component with database configuration
#   5. Verifies component creation
#
# Component Configuration:
#   - Provider ID: fabiottini-custom-user-storage (matches SPI factory)
#   - Provider Type: org.keycloak.storage.UserStorageProvider
#   - Database connection parameters from .env
#   - Enabled by default with DEFAULT cache policy
#
# Usage:
#   ./create_component.sh
#
# Requirements:
#   - Keycloak running with custom SPI deployed
#   - Realm already created
#   - Valid .env configuration file
#   - curl and jq installed
# =====================================================

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

echo "========================================"
echo "User Federation Component Configuration"
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
# REALM INFORMATION RETRIEVAL
# =====================================================

# -----------------------------------------------------
# Get Realm ID
# -----------------------------------------------------
# The realm ID (UUID) is required as the parentId for
# the User Federation component
echo "Retrieving realm ID for realm: $REALM_NAME"
REALM_ID=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.id')

if [ "$REALM_ID" = "null" ] || [ -z "$REALM_ID" ]; then
    echo "ERROR: Failed to retrieve realm ID"
    echo "HINT: Ensure realm '$REALM_NAME' exists in Keycloak"
    exit 1
fi
echo "Realm ID: $REALM_ID"
echo ""

# =====================================================
# COMPONENT CREATION
# =====================================================

# -----------------------------------------------------
# Create User Federation Component
# -----------------------------------------------------
# This component connects the custom SPI to the realm,
# enabling user authentication against the custom database
echo "Creating User Federation component..."
echo ""
echo "Component Configuration:"
echo "  Name: $SPI_NAME"
echo "  Provider ID: $SPI_PROVIDER_ID"
echo "  Database URL: $DB_URL"
echo "  Database User: $DB_USER"
echo "  Table Name: $DB_TABLE_NAME"
echo ""

# Execute component creation via Keycloak Admin REST API
# The -w flag captures HTTP status code for error checking
COMPONENT_RESPONSE=$(curl -s -w "%{http_code}" -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/components" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$SPI_NAME\",
        \"providerId\": \"$SPI_PROVIDER_ID\",
        \"providerType\": \"org.keycloak.storage.UserStorageProvider\",
        \"config\": {
            \"dbUrl\": [\"$DB_URL\"],
            \"dbUser\": [\"$DB_USER\"],
            \"dbPassword\": [\"$DB_PASSWORD\"],
            \"tableName\": [\"$DB_TABLE_NAME\"],
            \"enabled\": [\"true\"],
            \"cachePolicy\": [\"DEFAULT\"],
            \"parentId\": [\"$REALM_ID\"]
        }
    }")

# Extract HTTP status code from response
HTTP_CODE="${COMPONENT_RESPONSE: -3}"
RESPONSE_BODY="${COMPONENT_RESPONSE%???}"

# =====================================================
# VALIDATION
# =====================================================

# -----------------------------------------------------
# Check Component Creation Status
# -----------------------------------------------------
if [ "$HTTP_CODE" -ge 400 ]; then
    echo "ERROR: Component creation failed (HTTP $HTTP_CODE)"
    echo "Response: $RESPONSE_BODY"
    echo ""
    echo "Common Causes:"
    echo "  - Component already exists (try deleting it first)"
    echo "  - Invalid database connection parameters"
    echo "  - Custom SPI JAR not loaded in Keycloak"
    exit 1
fi

echo "Component created successfully"
echo ""

# -----------------------------------------------------
# Verify Component Configuration
# -----------------------------------------------------
# Query the components endpoint to confirm the component
# was created and retrieve its configuration
echo "Verifying component configuration..."
curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/components" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" | jq ".[] | select(.name == \"$SPI_NAME\")"

echo ""
echo "========================================"
echo "User Federation Configuration Complete"
echo "========================================"
echo ""
echo "The custom user storage provider is now active"
echo "Users from the custom database can now authenticate"
echo ""
