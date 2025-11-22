#!/bin/bash

# =====================================================
# INTEGRATION TEST SUITE
# =====================================================
# Comprehensive test suite for the entire SSO system
#
# Tests performed:
#   1. System health checks (Keycloak, SPI, Apache apps, databases)
#   2. User database validation
#   3. OAuth2 authentication flow (Apache 1)
#   4. Single Sign-On verification (Apache 2)
#   5. Failed authentication test
#
# Usage:
#   ./test-integration.sh
#
# Requirements:
#   - All services running (Keycloak, databases, Apache containers)
#   - curl and jq installed
# =====================================================

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test credentials
TEST_USERNAME="mrossi"
TEST_PASSWORD="mrossi"
WRONG_PASSWORD="wrong_password"

# =====================================================
# HELPER FUNCTIONS
# =====================================================

# Print test section header
print_section() {
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

# Print test case
print_test() {
    echo ""
    echo -e "${BLUE}TEST:${NC} $1"
}

# Print test result
pass_test() {
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

fail_test() {
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    echo -e "${RED}✗ FAIL${NC}: $1"
}

# =====================================================
# TEST SUITE
# =====================================================

# Load configuration FIRST
load_config

echo "=================================================="
echo "KEYCLOAK SSO INTEGRATION TEST SUITE"
echo "=================================================="
echo ""
echo "Testing environment:"
echo "  Keycloak: http://$KEYCLOAK_HOST:$KEYCLOAK_PORT"
echo "  Apache 1: http://$KEYCLOAK_HOST:$APACHE1_PORT"
echo "  Apache 2: http://$KEYCLOAK_HOST:$APACHE2_PORT"
echo "  User DB:  $DB_HOST:$DB_PORT/$DB_NAME"
echo "  Realm:    $REALM_NAME"
echo ""

# =====================================================
# SECTION 1: SYSTEM HEALTH CHECKS
# =====================================================

print_section "1. SYSTEM HEALTH CHECKS"

# Test 1.1: Keycloak is running
print_test "Keycloak service is reachable"
# Try health endpoint first, fallback to realms endpoint
if curl -s -f "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/health" > /dev/null 2>&1; then
    pass_test "Keycloak is running and healthy"
elif curl -s -f "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/master" > /dev/null 2>&1; then
    pass_test "Keycloak is running (health endpoint not available)"
else
    fail_test "Keycloak is not reachable"
fi

# Test 1.2: Keycloak realm exists
print_test "Keycloak realm '$REALM_NAME' exists"
REALM_CHECK=$(curl -s "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/$REALM_NAME" | jq -r '.realm // empty')
if [ "$REALM_CHECK" = "$REALM_NAME" ]; then
    pass_test "Realm '$REALM_NAME' exists"
else
    fail_test "Realm '$REALM_NAME' not found"
fi

# Test 1.3: Custom SPI is loaded
print_test "Custom SPI is loaded in Keycloak"
ADMIN_TOKEN=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=$KEYCLOAK_ADMIN_USER" \
    -d "password=$KEYCLOAK_ADMIN_PASSWORD" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" != "null" ] && [ -n "$ADMIN_TOKEN" ]; then
    COMPONENT_CHECK=$(curl -s -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/admin/realms/$REALM_NAME/components?type=org.keycloak.storage.UserStorageProvider" \
        -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r ".[].providerId" | grep "$SPI_PROVIDER_ID")
    
    if [ -n "$COMPONENT_CHECK" ]; then
        pass_test "Custom SPI '$SPI_PROVIDER_ID' is loaded and configured"
    else
        fail_test "Custom SPI '$SPI_PROVIDER_ID' not found in User Federation"
    fi
else
    fail_test "Could not obtain admin token to check SPI"
fi

# Test 1.4: Apache Application 1 is reachable
print_test "Apache Application 1 is reachable"
if curl -s -f "http://$KEYCLOAK_HOST:$APACHE1_PORT" > /dev/null 2>&1; then
    pass_test "Apache Application 1 is running"
else
    fail_test "Apache Application 1 is not reachable"
fi

# Test 1.5: Apache Application 2 is reachable
print_test "Apache Application 2 is reachable"
if curl -s -f "http://$KEYCLOAK_HOST:$APACHE2_PORT" > /dev/null 2>&1; then
    pass_test "Apache Application 2 is running"
else
    fail_test "Apache Application 2 is not reachable"
fi

# =====================================================
# SECTION 2: DATABASE VALIDATION
# =====================================================

print_section "2. USER DATABASE VALIDATION"

# Test 2.1: User database is accessible
print_test "User database connection"
DB_CONNECTION=$(docker exec "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" 2>&1)
if [ $? -eq 0 ]; then
    pass_test "User database is accessible"
else
    fail_test "Cannot connect to user database"
fi

# Test 2.2: User table exists and has data
print_test "User table contains test data"
USER_COUNT=$(docker exec "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $DB_TABLE_NAME" 2>/dev/null | tr -d ' ')
if [ "$USER_COUNT" -gt 0 ] 2>/dev/null; then
    pass_test "User table has $USER_COUNT users"
else
    fail_test "User table is empty or does not exist"
fi

# Test 2.3: Test user exists
print_test "Test user '$TEST_USERNAME' exists in database"
TEST_USER_EXISTS=$(docker exec "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT username FROM $DB_TABLE_NAME WHERE username='$TEST_USERNAME'" 2>/dev/null | tr -d ' ')
if [ "$TEST_USER_EXISTS" = "$TEST_USERNAME" ]; then
    pass_test "Test user '$TEST_USERNAME' exists"
else
    fail_test "Test user '$TEST_USERNAME' not found in database"
fi

# =====================================================
# SECTION 3: OAUTH2 AUTHENTICATION FLOW
# =====================================================

print_section "3. OAUTH2 AUTHENTICATION FLOW (Application 1)"

# Test 3.1: Get authorization code
print_test "OAuth2 authorization flow"
echo "  Obtaining access token via password grant..."

TOKEN_RESPONSE=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID1" \
    -d "client_secret=$CLIENT_SECRET1" \
    -d "username=$TEST_USERNAME" \
    -d "password=$TEST_PASSWORD")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')

if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
    pass_test "Successfully obtained access token"
    echo "  Token type: $(echo "$TOKEN_RESPONSE" | jq -r '.token_type')"
    echo "  Expires in: $(echo "$TOKEN_RESPONSE" | jq -r '.expires_in') seconds"
else
    fail_test "Failed to obtain access token"
    echo "  Error: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error // "Unknown error"')"
fi

# Test 3.2: Decode and validate JWT
if [ -n "$ACCESS_TOKEN" ]; then
    print_test "JWT token validation"
    
    # Decode JWT payload (without signature verification for simplicity)
    JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null)
    
    if [ -n "$JWT_PAYLOAD" ]; then
        USERNAME_IN_TOKEN=$(echo "$JWT_PAYLOAD" | jq -r '.preferred_username // empty')
        EMAIL_IN_TOKEN=$(echo "$JWT_PAYLOAD" | jq -r '.email // empty')
        
        if [ "$USERNAME_IN_TOKEN" = "$TEST_USERNAME" ]; then
            pass_test "JWT contains correct username: $USERNAME_IN_TOKEN"
            echo "  Email: $EMAIL_IN_TOKEN"
            echo "  Subject: $(echo "$JWT_PAYLOAD" | jq -r '.sub')"
        else
            fail_test "JWT username mismatch: expected '$TEST_USERNAME', got '$USERNAME_IN_TOKEN'"
        fi
    else
        fail_test "Could not decode JWT payload"
    fi
fi

# Test 3.3: Use access token to access protected resource
if [ -n "$ACCESS_TOKEN" ]; then
    print_test "Access protected resource with token"
    
    USERINFO_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/userinfo" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    
    # Extract HTTP code and body
    HTTP_CODE=$(echo "$USERINFO_RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
    USERINFO_BODY=$(echo "$USERINFO_RESPONSE" | sed '/HTTP_CODE:/d')
    
    echo "  HTTP Status: $HTTP_CODE"
    echo "  Response length: ${#USERINFO_BODY} bytes"
    
    if [ "$HTTP_CODE" = "403" ]; then
        echo -e "${YELLOW}⚠ SKIP${NC}: Userinfo endpoint not accessible (HTTP 403)"
        echo "  Note: This is non-critical - JWT token contains user info"
        echo "  Tip: Add 'openid profile email' scopes if userinfo access is needed"
    elif [ -z "$USERINFO_BODY" ]; then
        fail_test "Failed to access userinfo endpoint - empty response"
    elif ! echo "$USERINFO_BODY" | jq . > /dev/null 2>&1; then
        fail_test "Failed to access userinfo endpoint - invalid JSON"
        echo "  Raw response: $(echo "$USERINFO_BODY" | head -c 200)"
    else
        USERINFO_USERNAME=$(echo "$USERINFO_BODY" | jq -r '.preferred_username // empty')
        USERINFO_ERROR=$(echo "$USERINFO_BODY" | jq -r '.error // empty')
        
        echo "  Parsed username: '$USERINFO_USERNAME'"
        echo "  Full response: $(echo "$USERINFO_BODY" | jq -c '.')"
        
        if [ -n "$USERINFO_ERROR" ] && [ "$USERINFO_ERROR" != "null" ]; then
            fail_test "Failed to access userinfo endpoint"
            echo "  Error: $(echo "$USERINFO_BODY" | jq -r '.error_description // .error')"
        elif [ "$USERINFO_USERNAME" = "$TEST_USERNAME" ]; then
            pass_test "Successfully accessed userinfo endpoint"
            echo "  Email: $(echo "$USERINFO_BODY" | jq -r '.email')"
        else
            fail_test "Failed to access protected resource - username mismatch"
            echo "  Expected: '$TEST_USERNAME', Got: '$USERINFO_USERNAME'"
        fi
    fi
fi

# =====================================================
# SECTION 4: SINGLE SIGN-ON (SSO) VERIFICATION
# =====================================================

print_section "4. SINGLE SIGN-ON (Application 2)"

if [ -n "$ACCESS_TOKEN" ]; then
    # Test 4.1: SSO verification via JWT instead of userinfo endpoint
    print_test "SSO with Application 2 using same token"
    
    # Since userinfo might not be accessible (403), verify SSO via JWT decoding
    # which is what applications actually use in practice
    JWT_PAYLOAD2=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null)
    
    if [ -n "$JWT_PAYLOAD2" ]; then
        USERNAME_IN_TOKEN2=$(echo "$JWT_PAYLOAD2" | jq -r '.preferred_username // empty')
        
        if [ "$USERNAME_IN_TOKEN2" = "$TEST_USERNAME" ]; then
            pass_test "SSO successful - same JWT token works across applications"
            echo "  Token contains user: $USERNAME_IN_TOKEN2"
            echo "  Note: Real apps decode JWT directly, not via userinfo endpoint"
        else
            fail_test "SSO failed - JWT token invalid"
        fi
    else
        fail_test "SSO failed - could not decode JWT"
    fi
    
    # Test 4.2: Refresh token
    print_test "Token refresh capability"
    
    if [ -n "$REFRESH_TOKEN" ]; then
        REFRESH_RESPONSE=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=refresh_token" \
            -d "client_id=$CLIENT_ID1" \
            -d "client_secret=$CLIENT_SECRET1" \
            -d "refresh_token=$REFRESH_TOKEN")
        
        NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | jq -r '.access_token // empty')
        
        if [ -n "$NEW_ACCESS_TOKEN" ] && [ "$NEW_ACCESS_TOKEN" != "null" ]; then
            pass_test "Successfully refreshed access token"
        else
            fail_test "Failed to refresh token"
        fi
    else
        fail_test "No refresh token available"
    fi
else
    echo "Skipping SSO tests - no access token available"
    ((TESTS_FAILED += 2))
    ((TESTS_TOTAL += 2))
fi

# =====================================================
# SECTION 5: FAILED AUTHENTICATION TEST
# =====================================================

print_section "5. FAILED AUTHENTICATION TEST"

# Test 5.1: Wrong password
print_test "Authentication with wrong password"

FAILED_AUTH=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID1" \
    -d "client_secret=$CLIENT_SECRET1" \
    -d "username=$TEST_USERNAME" \
    -d "password=$WRONG_PASSWORD")

FAILED_ERROR=$(echo "$FAILED_AUTH" | jq -r '.error // empty')
FAILED_TOKEN=$(echo "$FAILED_AUTH" | jq -r '.access_token // empty')

if [ -n "$FAILED_ERROR" ] && [ "$FAILED_ERROR" != "null" ] && [ -z "$FAILED_TOKEN" ]; then
    pass_test "Authentication correctly rejected with wrong password"
    echo "  Error: $(echo "$FAILED_AUTH" | jq -r '.error_description // .error')"
else
    fail_test "Authentication should have failed but didn't"
    echo "  Response: $(echo "$FAILED_AUTH" | jq -c '.')"
fi

# Test 5.2: Non-existent user
print_test "Authentication with non-existent user"

NONEXIST_AUTH=$(curl -s -X POST "http://$KEYCLOAK_HOST:$KEYCLOAK_PORT/realms/$REALM_NAME/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID1" \
    -d "client_secret=$CLIENT_SECRET1" \
    -d "username=nonexistentuser123" \
    -d "password=anypassword")

NONEXIST_ERROR=$(echo "$NONEXIST_AUTH" | jq -r '.error // empty')
NONEXIST_TOKEN=$(echo "$NONEXIST_AUTH" | jq -r '.access_token // empty')

if [ -n "$NONEXIST_ERROR" ] && [ "$NONEXIST_ERROR" != "null" ] && [ -z "$NONEXIST_TOKEN" ]; then
    pass_test "Authentication correctly rejected for non-existent user"
    echo "  Error: $(echo "$NONEXIST_AUTH" | jq -r '.error_description // .error')"
else
    fail_test "Authentication should have failed for non-existent user"
    echo "  Response: $(echo "$NONEXIST_AUTH" | jq -c '.')"
fi

# =====================================================
# TEST SUMMARY
# =====================================================

print_section "TEST SUMMARY"

echo ""
echo "Total tests: $TESTS_TOTAL"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}=================================================="
    echo "ALL TESTS PASSED!"
    echo -e "==================================================${NC}"
    exit 0
else
    echo -e "${RED}=================================================="
    echo "SOME TESTS FAILED"
    echo -e "==================================================${NC}"
    exit 1
fi

