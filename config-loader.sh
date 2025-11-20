#!/bin/bash

# =====================================================
# CONFIGURATION LOADER AND VALIDATOR
# =====================================================
# Centralized configuration management for the entire project.
# This script is sourced by all other bash scripts to ensure
# consistent configuration across all components.
#
# Purpose:
#   - Load environment variables from .env file
#   - Validate required parameters
#   - Derive computed values (URLs, paths)
#   - Provide configuration summary display
#
# Usage:
#   source config-loader.sh
#   init_config
# =====================================================

# -----------------------------------------------------
# FUNCTION: load_config
# -----------------------------------------------------
# Loads all configuration parameters from the .env file
# and exports them as environment variables.
#
# This function also computes derived values like full URLs
# and JDBC connection strings based on the loaded configuration.
#
# Returns:
#   0 on success, exits with 1 if .env file is missing
# -----------------------------------------------------
load_config() {
    # Determine the directory where this script is located
    # This ensures we can find .env regardless of where the script is called from
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="$script_dir/.env"

    # Verify .env file exists
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Configuration file not found: $config_file"
        echo "HINT: Create a .env file based on .env.example"
        exit 1
    fi

    echo "Loading configuration from: $config_file"

    # Load all variables from .env and automatically export them
    # set -a: Mark all subsequently defined variables for export
    # set +a: Disable automatic export after sourcing
    set -a
    source "$config_file"
    set +a

    # ---- Compute Derived Configuration Values ----
    # These values are constructed from the base configuration
    # and provide convenient access to commonly used combinations

    # SPI JAR full path (used for building and deploying the custom provider)
    export SPI_JAR_PATH="$SPI_TARGET_DIR/$SPI_JAR_NAME"

    # Client redirect URIs (used in OAuth2 flow configuration)
    export CLIENT_REDIRECT_URI_1="$CLIENT_REDIRECT_URI1"
    export CLIENT_REDIRECT_URI_2="$CLIENT_REDIRECT_URI2"

    # JDBC connection strings for both databases
    # User database: Custom legacy database with user credentials
    export DB_URL="jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAME"
    # Keycloak database: Internal Keycloak operational database
    export KEYCLOAK_DB_URL="jdbc:postgresql://$KEYCLOAK_DB_HOST:$KEYCLOAK_DB_PORT/$KEYCLOAK_DB_NAME"

    # Service URLs for easy access
    export KEYCLOAK_ADMIN_CONSOLE_URL="http://$KEYCLOAK_HOST:$KEYCLOAK_PORT"
    export APACHE1_URL="http://$KEYCLOAK_HOST:$APACHE1_PORT"
    export APACHE2_URL="http://$KEYCLOAK_HOST:$APACHE2_PORT"

    # Convert comma-separated test users string to array
    # Format: "username1:password1,username2:password2"
    IFS=',' read -ra TEST_USERS_ARRAY <<< "$TEST_USERS"
    export TEST_USERS_ARRAY

    echo "Configuration loaded successfully"
}

# -----------------------------------------------------
# FUNCTION: validate_config
# -----------------------------------------------------
# Validates all loaded configuration parameters to ensure
# they meet requirements before any operations are performed.
#
# Validation checks include:
#   - Required variables are not empty
#   - Port numbers are valid (1-65535)
#   - Port numbers are unique (no conflicts)
#   - Required files exist (pom.xml, schema file)
#   - Test users are properly formatted
#
# Returns:
#   0 if validation passes, 1 if any errors are found
# -----------------------------------------------------
validate_config() {
    echo "Validating configuration..."

    local errors=0

    # ---- Required Variables Check ----
    # These variables must be defined in .env for the system to function
    local required_vars=(
        # Keycloak configuration
        "KEYCLOAK_HOST" "KEYCLOAK_PORT" "KEYCLOAK_ADMIN_USER" "KEYCLOAK_ADMIN_PASSWORD"
        # Custom user database configuration
        "DB_HOST" "DB_PORT" "DB_NAME" "DB_USER" "DB_PASSWORD" "DB_TABLE_NAME"
        # Realm and client configuration
        "REALM_NAME" "CLIENT_ID1" "CLIENT_ID2"
        # SPI configuration
        "SPI_NAME" "SPI_PROVIDER_ID"
        # Test application ports
        "APACHE1_PORT" "APACHE2_PORT"
    )

    # Iterate through required variables and check if they are defined
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo "ERROR: Missing required variable: $var"
            ((errors++))
        fi
    done

    # ---- Port Number Validation ----
    # Ports must be valid integers within the valid range (1-65535)

    # Validate Keycloak port
    if ! [[ "$KEYCLOAK_PORT" =~ ^[0-9]+$ ]] || [ "$KEYCLOAK_PORT" -lt 1 ] || [ "$KEYCLOAK_PORT" -gt 65535 ]; then
        echo "ERROR: KEYCLOAK_PORT must be a valid number between 1-65535"
        ((errors++))
    fi

    # Validate Apache application 1 port
    if ! [[ "$APACHE1_PORT" =~ ^[0-9]+$ ]] || [ "$APACHE1_PORT" -lt 1 ] || [ "$APACHE1_PORT" -gt 65535 ]; then
        echo "ERROR: APACHE1_PORT must be a valid number between 1-65535"
        ((errors++))
    fi

    # Validate Apache application 2 port
    if ! [[ "$APACHE2_PORT" =~ ^[0-9]+$ ]] || [ "$APACHE2_PORT" -lt 1 ] || [ "$APACHE2_PORT" -gt 65535 ]; then
        echo "ERROR: APACHE2_PORT must be a valid number between 1-65535"
        ((errors++))
    fi

    # ---- Port Uniqueness Check ----
    # Ensure no two services are configured to use the same port
    if [ "$KEYCLOAK_PORT" = "$APACHE1_PORT" ] || [ "$KEYCLOAK_PORT" = "$APACHE2_PORT" ] || [ "$APACHE1_PORT" = "$APACHE2_PORT" ]; then
        echo "ERROR: Port conflict detected - all ports must be unique"
        ((errors++))
    fi

    # ---- Test Users Validation ----
    # TEST_USERS should be a non-empty comma-separated list
    if [ -z "$TEST_USERS" ]; then
        echo "ERROR: TEST_USERS cannot be empty"
        ((errors++))
    fi

    # ---- File Existence Checks ----
    # Verify that required project files exist

    # Check for Maven POM file (required for SPI build)
    if [ ! -f "$SPI_SOURCE_DIR/pom.xml" ]; then
        echo "ERROR: pom.xml file not found in $SPI_SOURCE_DIR/"
        ((errors++))
    fi

    # Check for database schema file (required for initialization)
    if [ ! -f "$DB_SCHEMA_FILE" ]; then
        echo "ERROR: Database schema file not found: $DB_SCHEMA_FILE"
        ((errors++))
    fi

    # ---- Final Validation Result ----
    if [ $errors -gt 0 ]; then
        echo "VALIDATION FAILED: Found $errors error(s) in configuration"
        return 1
    fi

    echo "Configuration validation passed"
    return 0
}

# -----------------------------------------------------
# FUNCTION: show_config_summary
# -----------------------------------------------------
# Displays a formatted summary of the current configuration.
# This provides a quick overview of all key system parameters.
#
# Called after successful configuration loading and validation.
# -----------------------------------------------------
show_config_summary() {
    echo ""
    echo "===== CONFIGURATION SUMMARY ====="
    echo ""
    echo "Keycloak Service:"
    echo "   URL: $KEYCLOAK_ADMIN_CONSOLE_URL"
    echo "   Admin User: $KEYCLOAK_ADMIN_USER"
    echo "   Realm: $REALM_NAME"
    echo ""
    echo "User Database:"
    echo "   Host: $DB_HOST:$DB_PORT"
    echo "   Database: $DB_NAME"
    echo "   Table: $DB_TABLE_NAME"
    echo ""
    echo "Custom SPI:"
    echo "   Name: $SPI_NAME"
    echo "   Provider ID: $SPI_PROVIDER_ID"
    echo "   JAR Path: $SPI_JAR_PATH"
    echo ""
    echo "Test Applications:"
    echo "   Apache 1: $APACHE1_URL"
    echo "   Apache 2: $APACHE2_URL"
    echo ""
    echo "=================================="
    echo ""
}

# -----------------------------------------------------
# FUNCTION: init_config
# -----------------------------------------------------
# Main configuration initialization function.
# This is the primary entry point that should be called
# by all scripts that need configuration.
#
# Process:
#   1. Load configuration from .env
#   2. Validate all parameters
#   3. Display configuration summary
#
# Returns:
#   0 on success, exits with 1 on any failure
# -----------------------------------------------------
init_config() {
    load_config
    if validate_config; then
        show_config_summary
        return 0
    else
        echo "ERROR: Configuration initialization failed"
        exit 1
    fi
}

# =====================================================
# SCRIPT EXECUTION
# =====================================================
# If this script is executed directly (not sourced),
# run a configuration test to verify .env file validity.
# This is useful for debugging configuration issues.
#
# Usage: ./config-loader.sh
# =====================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Running configuration test..."
    init_config
    echo "Configuration test completed successfully"
fi 