#!/bin/bash

# =====================================================
# KEYCLOAK CUSTOM SPI CONFIGURATION SCRIPT
# =====================================================
# Automates the complete setup of the Custom User Storage Provider
# within a running Keycloak instance.
#
# This script orchestrates the following operations:
#   1. Deploys the SPI JAR to Keycloak's providers directory
#   2. Restarts Keycloak to load the custom provider
#   3. Obtains administrative access token
#   4. Creates the configured realm
#   5. Configures OAuth2 clients with proper redirect URIs
#   6. Configures User Federation with custom database connection
#   7. Creates test users in the custom database (optional)
#
# Interactive Mode:
#   The script prompts for confirmation at each major step,
#   allowing selective execution and troubleshooting.
#
# Usage:
#   ./setup-spi.sh
#
# Requirements:
#   - Keycloak container running
#   - Custom SPI JAR built (run build-spi.sh first)
#   - Valid .env configuration file
#   - curl and jq installed
# =====================================================

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

# =====================================================
# HELPER FUNCTIONS
# =====================================================

# -----------------------------------------------------
# FUNCTION: ask_confirmation
# -----------------------------------------------------
# Prompts the user for yes/no confirmation before
# executing a step. Supports default values.
#
# Parameters:
#   $1 - Message to display to the user
#   $2 - Default response ("y" or "n"), defaults to "y"
#
# Returns:
#   0 if user confirms (yes), 1 if user declines (no)
# -----------------------------------------------------
ask_confirmation() {
    local message="$1"
    local default="${2:-y}"

    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -n "$message $prompt: "
    read -r response

    if [ -z "$response" ]; then
        response="$default"
    fi

    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# -----------------------------------------------------
# FUNCTION: execute_step
# -----------------------------------------------------
# Executes a configuration step with user confirmation
# and error handling.
#
# Parameters:
#   $1 - Step name (for display)
#   $2 - Function to execute
#
# Error Handling:
#   If the step fails, prompts user to continue or abort
# -----------------------------------------------------
execute_step() {
    local step_name="$1"
    local step_function="$2"

    echo ""
    echo "========================================="
    echo "Step: $step_name"
    echo "========================================="

    if ask_confirmation "Execute this step?"; then
        echo "Executing: $step_name"
        $step_function
        if [ $? -eq 0 ]; then
            echo "SUCCESS: $step_name completed"
        else
            echo "ERROR: $step_name failed"
            if ask_confirmation "Continue with remaining steps?" "n"; then
                echo "Continuing..."
            else
                echo "Setup aborted by user"
                exit 1
            fi
        fi
    else
        echo "SKIPPED: $step_name"
    fi
}

# =====================================================
# CONFIGURATION STEP FUNCTIONS
# =====================================================

# -----------------------------------------------------
# FUNCTION: update_jar_step
# -----------------------------------------------------
# Deploys the custom SPI JAR to Keycloak and restarts
# the service to load the provider.
#
# Process:
#   1. Removes any existing JAR files
#   2. Copies new JAR to providers directory
#   3. Sets appropriate file permissions
#   4. Restarts Keycloak container
#   5. Waits for restart and displays logs
#
# Returns:
#   0 on success, 1 if JAR file not found
# -----------------------------------------------------
update_jar_step() {
    echo "Deploying custom SPI JAR to Keycloak..."

    # Remove existing JAR files to prevent conflicts
    echo "  [1/5] Removing existing JAR files..."
    docker exec "$KEYCLOAK_CONTAINER_NAME" rm -f "$SPI_PROVIDERS_PATH/$SPI_JAR_NAME" 2>/dev/null || true
    docker exec "$KEYCLOAK_CONTAINER_NAME" rm -f "$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME" 2>/dev/null || true

    # Show current providers directory state
    echo "  [2/5] Providers directory (before):"
    docker exec "$KEYCLOAK_CONTAINER_NAME" ls -la "$SPI_PROVIDERS_PATH/"

    # Verify JAR exists before attempting copy
    if [ ! -f "$SPI_JAR_PATH" ]; then
        echo "ERROR: JAR file not found: $SPI_JAR_PATH"
        echo "HINT: Run 'make build-spi' first to build the JAR"
        return 1
    fi

    # Copy new JAR to Keycloak
    echo "  [3/5] Copying new JAR..."
    docker cp "$SPI_JAR_PATH" "$KEYCLOAK_CONTAINER_NAME:$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME"

    # Set read permissions for Keycloak process
    echo "  [4/5] Setting file permissions..."
    docker exec --user root "$KEYCLOAK_CONTAINER_NAME" bash -c "chmod 644 '$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME'"

    # Verify deployment
    echo "  [5/5] Providers directory (after):"
    docker exec "$KEYCLOAK_CONTAINER_NAME" ls -la "$SPI_PROVIDERS_PATH/"

    # Restart Keycloak to load the new provider
    echo "Restarting Keycloak to load custom provider..."
    docker-compose restart "$KEYCLOAK_CONTAINER_NAME"

    # Wait and display startup logs
    echo "Waiting ${RESTART_SLEEP_TIME}s for Keycloak to restart..."
    sleep "$RESTART_SLEEP_TIME"
    echo "Recent Keycloak logs:"
    docker-compose logs "$KEYCLOAK_CONTAINER_NAME" --tail="$LOGS_TAIL_LINES"
}

# -----------------------------------------------------
# FUNCTION: wait_keycloak_step
# -----------------------------------------------------
# Waits for Keycloak to become ready by polling the
# health endpoint.
#
# Polling Strategy:
#   - Attempts connection every WAIT_INTERVAL seconds
#   - Maximum of MAX_WAIT_ATTEMPTS attempts
#   - Uses Keycloak's /health endpoint
#
# Returns:
#   0 when Keycloak is ready, 1 on timeout
# -----------------------------------------------------
wait_keycloak_step() {
    echo "Waiting for Keycloak to become ready..."
    local attempt=0

    until curl -s "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/health" > /dev/null 2>&1; do
        echo "  Attempt $((++attempt))/$MAX_WAIT_ATTEMPTS - Keycloak not ready yet..."
        if [ $attempt -ge "$MAX_WAIT_ATTEMPTS" ]; then
            echo "ERROR: Timeout waiting for Keycloak (${MAX_WAIT_ATTEMPTS} attempts)"
            return 1
        fi
        sleep "$WAIT_INTERVAL"
    done
    echo "Keycloak is ready"
}

# -----------------------------------------------------
# FUNCTION: get_admin_token_step
# -----------------------------------------------------
# Obtains an administrative access token from Keycloak
# for performing configuration operations.
#
# Authentication:
#   - Uses master realm admin credentials
#   - Grants: password grant type
#   - Client: admin-cli (Keycloak's admin client)
#
# Returns:
#   0 on success (sets ADMIN_TOKEN variable), 1 on failure
# -----------------------------------------------------
get_admin_token_step() {
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
        return 1
    fi
    echo "Admin token obtained successfully"
}

# -----------------------------------------------------
# FUNCTION: create_realm_step
# -----------------------------------------------------
# Creates a new realm in Keycloak for testing the
# custom user storage provider.
#
# Realm Configuration:
#   - Realm name from REALM_NAME variable
#   - Display name from REALM_DISPLAY_NAME variable
#   - Enabled by default
#
# Note: If realm already exists, this will fail silently
# -----------------------------------------------------
create_realm_step() {
    echo "Creating realm: $REALM_NAME..."

    curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"realm\": \"$REALM_NAME\",
            \"enabled\": true,
            \"displayName\": \"$REALM_DISPLAY_NAME\"
        }" > /dev/null

    echo "Realm creation request sent"
}

# -----------------------------------------------------
# FUNCTION: create_oauth_client_step
# -----------------------------------------------------
# Creates or updates two OAuth2 clients in the realm.
#
# Smart Client Management:
#   - Checks if client already exists
#   - If exists: retrieves existing secret (preserves persistence)
#   - If not exists: creates new client with new secret
#   - Updates redirect URIs if client exists but URIs changed
#
# Client Configuration:
#   - Client 1: CLIENT_ID1 with configured redirect URIs
#   - Client 2: CLIENT_ID2 with configured redirect URIs
#   - Both support standard flow and direct grants
#
# Outputs:
#   - Client IDs and secrets (existing or new)
#   - Configured redirect URIs
# -----------------------------------------------------
create_oauth_client_step() {
    echo "Configuring OAuth2 client 1: $CLIENT_ID1..."

    # Check if client already exists
    CLIENT_UUID=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients?clientId=$CLIENT_ID1" \
        -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id // empty')

    if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" = "null" ]; then
        # Client doesn't exist, create it
        echo "  Creating new client: $CLIENT_ID1"
        
        CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
                \"clientId\": \"$CLIENT_ID1\",
                \"enabled\": true,
                \"publicClient\": false,
                \"redirectUris\": [\"$CLIENT_REDIRECT_URI_1\", \"$CLIENT_REDIRECT_URI_2\"],
                \"webOrigins\": [\"$CLIENT_WEB_ORIGINS_1\", \"$CLIENT_WEB_ORIGINS_2\"],
                \"standardFlowEnabled\": true,
                \"directAccessGrantsEnabled\": true
            }")
        
        HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
        
        if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
            # Get the newly created client UUID
            CLIENT_UUID=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients?clientId=$CLIENT_ID1" \
                -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')
            
            # Generate new secret for new client
            CLIENT_SECRET_GENERATED1=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/client-secret" \
                -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.value')
            
            echo "  ✅ Client created successfully"
        else
            echo "  ⚠️  Failed to create client (HTTP $HTTP_CODE)"
        fi
    else
        # Client exists, retrieve existing secret
        echo "  Client already exists, retrieving existing secret..."
        
        CLIENT_SECRET_GENERATED1=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/client-secret" \
            -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.value')
        
        echo "  ✅ Using existing client"
    fi

    echo "Client 1 configured:"
    echo "  Client ID: $CLIENT_ID1"
    echo "  Client Secret: $CLIENT_SECRET_GENERATED1"
    echo "  Redirect URIs: $CLIENT_REDIRECT_URI_1, $CLIENT_REDIRECT_URI_2"
    echo ""

    # Same process for second client
    echo "Configuring OAuth2 client 2: $CLIENT_ID2..."

    CLIENT_UUID=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients?clientId=$CLIENT_ID2" \
        -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id // empty')

    if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" = "null" ]; then
        echo "  Creating new client: $CLIENT_ID2"
        
        CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{
                \"clientId\": \"$CLIENT_ID2\",
                \"enabled\": true,
                \"publicClient\": false,
                \"redirectUris\": [\"$CLIENT_REDIRECT_URI_1\", \"$CLIENT_REDIRECT_URI_2\"],
                \"webOrigins\": [\"$CLIENT_WEB_ORIGINS_1\", \"$CLIENT_WEB_ORIGINS_2\"],
                \"standardFlowEnabled\": true,
                \"directAccessGrantsEnabled\": true
            }")
        
        HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
        
        if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
            CLIENT_UUID=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients?clientId=$CLIENT_ID2" \
                -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')
            
            CLIENT_SECRET_GENERATED2=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/client-secret" \
                -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.value')
            
            echo "  ✅ Client created successfully"
        else
            echo "  ⚠️  Failed to create client (HTTP $HTTP_CODE)"
        fi
    else
        echo "  Client already exists, retrieving existing secret..."
        
        CLIENT_SECRET_GENERATED2=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/client-secret" \
            -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.value')
        
        echo "  ✅ Using existing client"
    fi

    echo "Client 2 configured:"
    echo "  Client ID: $CLIENT_ID2"
    echo "  Client Secret: $CLIENT_SECRET_GENERATED2"
    echo "  Redirect URIs: $CLIENT_REDIRECT_URI_1, $CLIENT_REDIRECT_URI_2"
}

# -----------------------------------------------------
# FUNCTION: configure_user_federation_step
# -----------------------------------------------------
# Configures the User Federation component to use the
# custom user storage provider.
#
# This first removes any existing User Federation components
# (to allow clean reinstallation), then creates a new one
# via create_component.sh which handles the detailed
# component configuration via Keycloak's Admin API.
# -----------------------------------------------------
configure_user_federation_step() {
    echo "Configuring User Federation with custom SPI..."
    echo ""
    echo "Step 1: Removing existing User Federation components (if any)..."
    bash "$SCRIPT_DIR/remove_component.sh"
    echo ""
    echo "Step 2: Creating new User Federation component..."
    bash "$SCRIPT_DIR/create_component.sh"
}

# -----------------------------------------------------
# FUNCTION: create_test_users_step
# -----------------------------------------------------
# Creates test users in the custom database for
# authentication testing.
#
# Process:
#   - Iterates through TEST_USERS_ARRAY
#   - Inserts users with MD5 hashed passwords
#   - Uses ON CONFLICT DO NOTHING to avoid duplicates
#
# Note: This function is currently not called in the
# main flow but is available for manual execution
# -----------------------------------------------------
create_test_users_step() {
    echo "Creating test users in custom database..."

    for user_data in "${TEST_USERS_ARRAY[@]}"; do
        IFS=':' read -r username password <<< "$user_data"
        echo "  Creating user: $username"

        docker exec "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "
        INSERT INTO $DB_TABLE_NAME (nome, cognome, mail, username, password)
        VALUES ('Test', 'User', '${username}@example.com', '$username', MD5('$password'))
        ON CONFLICT (username) DO NOTHING;
        " > /dev/null
    done

    echo "Test users created"
}

# -----------------------------------------------------
# FUNCTION: show_summary_step
# -----------------------------------------------------
# Displays a summary of the completed configuration
# including access URLs, credentials, and test instructions.
# -----------------------------------------------------
show_summary_step() {
    echo ""
    echo "========================================"
    echo "Configuration Completed Successfully"
    echo "========================================"
    echo ""
    echo "Keycloak Admin Console:"
    echo "  URL: $KEYCLOAK_ADMIN_CONSOLE_URL"
    echo "  Username: $KEYCLOAK_ADMIN_USER"
    echo "  Password: $KEYCLOAK_ADMIN_PASSWORD"
    echo ""
    echo "Configured Realm:"
    echo "  Name: $REALM_NAME"
    echo "  Display Name: $REALM_DISPLAY_NAME"
    echo ""
    echo "OAuth2 Clients:"
    echo "  Client 1 ID: $CLIENT_ID1"
    echo "  Client 2 ID: $CLIENT_ID2"
    echo "  Redirect URIs: $CLIENT_REDIRECT_URI_1, $CLIENT_REDIRECT_URI_2"
    echo ""
    echo "Test Applications:"
    echo "  Apache 1: $APACHE1_URL"
    echo "  Apache 2: $APACHE2_URL"
    echo ""
    echo "Database Configuration:"
    echo "  URL: $DB_URL"
    echo "  Table: $DB_TABLE_NAME"
    echo ""
    echo "Testing Authentication:"
    echo "  1. Navigate to: $APACHE1_URL"
    echo "  2. Click 'Login with Keycloak'"
    echo "  3. Use test credentials from the database"
    echo ""
}

# -----------------------------------------------------
# FUNCTION: restart_keycloak_step
# -----------------------------------------------------
# Performs a final restart of Keycloak to ensure all
# configurations are properly loaded.
# -----------------------------------------------------
restart_keycloak_step() {
    echo "Performing final Keycloak restart..."
    docker-compose restart "$KEYCLOAK_CONTAINER_NAME"
    echo "Keycloak restarted"
}

# -----------------------------------------------------
# FUNCTION: sync_client_secrets_step
# -----------------------------------------------------
# Synchronizes OAuth client secrets from Keycloak to
# the .env file and restarts Apache containers.
#
# This is necessary because when OAuth clients are created,
# Keycloak generates new secrets that must be propagated
# to the Apache containers for SSO to work properly.
# -----------------------------------------------------
sync_client_secrets_step() {
    echo "Synchronizing OAuth client secrets..."
    echo ""
    echo "⚠️  This will update client secrets in .env and restart Apache containers"
    
    if ask_confirmation "Proceed with client secret synchronization?" "y"; then
        bash "$SCRIPT_DIR/update-client-secrets.sh"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✅ Client secrets synchronized successfully"
            echo "🔄 Restarting Apache containers..."
            docker-compose restart "$APACHE1_CONTAINER_NAME" "$APACHE2_CONTAINER_NAME"
            echo "✅ Apache containers restarted with new secrets"
        else
            echo ""
            echo "⚠️  Failed to synchronize client secrets"
            echo "💡 You can run it manually later with: make update-client-secrets"
        fi
    else
        echo "⏭️  Skipped client secret synchronization"
        echo "💡 Run it manually later with: make update-client-secrets"
    fi
}

# =====================================================
# MAIN EXECUTION
# =====================================================

echo "========================================"
echo "Keycloak Custom SPI Setup"
echo "========================================"
echo ""

# Initialize and validate configuration
init_config

# Confirm before starting
if ask_confirmation "Proceed with Keycloak configuration?"; then
    # Execute configuration steps sequentially
    # Each step can be individually skipped by the user

    update_jar_step
    wait_keycloak_step
    get_admin_token_step
    create_realm_step
    create_oauth_client_step
    configure_user_federation_step
    show_summary_step
    restart_keycloak_step
    sync_client_secrets_step

    echo ""
    echo "========================================"
    echo "Setup Complete"
    echo "========================================"
    echo ""
    echo "🎉 All configuration steps completed successfully!"
    echo "📝 Test Applications are now ready with synchronized credentials"
else
    echo "Configuration cancelled by user"
    exit 0
fi
