#!/bin/bash

# =====================================================
# CUSTOM SPI BUILD SCRIPT
# =====================================================
# Automates the build process for the custom Keycloak User Storage Provider.
#
# This script performs the following operations:
#   1. Loads and validates configuration from .env
#   2. Builds the SPI JAR using Maven in a Docker container
#   3. Optionally deploys the JAR to a running Keycloak instance
#
# Build Approach:
#   Uses Docker-based Maven build to eliminate dependency on local JDK/Maven installation.
#   The Maven container mounts the SPI source directory and compiles the code in isolation.
#
# Usage:
#   ./build-spi.sh
#
# Output:
#   custom-user-spi/target/custom-user-spi-1.0.0.jar
#
# Requirements:
#   - Docker daemon running
#   - Valid .env configuration file
#   - SPI source code in custom-user-spi/ directory
# =====================================================

# Load centralized configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config-loader.sh"

echo "========================================"
echo "Building Custom Keycloak SPI"
echo "========================================"
echo ""

# Initialize and validate configuration
init_config

echo "Build Configuration:"
echo "  SPI Name: $SPI_NAME"
echo "  Source Directory: $SPI_SOURCE_DIR"
echo "  Target JAR: $SPI_JAR_PATH"
echo "  Maven Image: $MAVEN_IMAGE"
echo ""

# =====================================================
# PRE-BUILD VALIDATION
# =====================================================

# Check Docker availability
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running"
    echo "HINT: Start Docker daemon before running this script"
    exit 1
fi

# Verify SPI source directory exists
if [ ! -d "$SPI_SOURCE_DIR" ]; then
    echo "ERROR: SPI directory not found: $SPI_SOURCE_DIR"
    echo "HINT: Ensure the custom-user-spi directory exists"
    exit 1
fi

# Verify pom.xml exists
if [ ! -f "$SPI_SOURCE_DIR/pom.xml" ]; then
    echo "ERROR: pom.xml file not found in $SPI_SOURCE_DIR/"
    echo "HINT: The SPI directory must contain a valid Maven project"
    exit 1
fi

# =====================================================
# BUILD PROCESS
# =====================================================
echo "Starting Maven build process..."
echo ""
echo "Build Details:"
echo "  Maven Image: $MAVEN_IMAGE"
echo "  Workspace: $SPI_SOURCE_DIR"
echo "  Build Command: mvn clean package"
echo ""

# Execute Maven build inside Docker container
# This approach ensures consistent build environment regardless of host OS
#
# Explanation of Docker flags:
#   --rm: Automatically remove container after execution
#   -v: Mount host directory into container
#   -w: Set working directory inside container
docker run --rm \
    -v "$(pwd)/$SPI_SOURCE_DIR:/workspace" \
    -w /workspace \
    "$MAVEN_IMAGE" \
    mvn clean package

# Check Maven build exit status
if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Maven build failed"
    echo "HINT: Review Maven output above for compilation errors"
    exit 1
fi

echo ""
echo "Build completed successfully"

# =====================================================
# POST-BUILD VALIDATION
# =====================================================

# Verify JAR artifact was created
if [ ! -f "$SPI_JAR_PATH" ]; then
    echo "ERROR: JAR file not found: $SPI_JAR_PATH"
    echo "HINT: Verify Maven build completed without errors"
    exit 1
fi

# Display JAR information
echo ""
echo "Build Artifacts:"
echo "  JAR Location: $SPI_JAR_PATH"
echo "  JAR Size: $(du -h "$SPI_JAR_PATH" | cut -f1)"
echo "  Destination Name: $SPI_DESTINATION_NAME"
echo ""

# =====================================================
# OPTIONAL: DEPLOY TO RUNNING KEYCLOAK
# =====================================================
# If Keycloak container is running, offer to automatically
# deploy the newly built JAR without requiring manual steps

if docker ps --format "table {{.Names}}" | grep -q "^$KEYCLOAK_CONTAINER_NAME$"; then
    echo "Keycloak container is currently running"
    echo ""
    read -p "Deploy JAR to running Keycloak instance? [y/N]: " response

    case "$response" in
        [yY]|[yY][eE][sS])
            echo ""
            echo "Deploying JAR to Keycloak..."

            # Step 1: Remove existing JAR files to prevent conflicts
            echo "  [1/4] Removing existing JAR files..."
            docker exec "$KEYCLOAK_CONTAINER_NAME" rm -f "$SPI_PROVIDERS_PATH/$SPI_JAR_NAME" 2>/dev/null || true
            docker exec "$KEYCLOAK_CONTAINER_NAME" rm -f "$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME" 2>/dev/null || true

            # Step 2: Copy new JAR to Keycloak providers directory
            echo "  [2/4] Copying new JAR to Keycloak providers directory..."
            docker cp "$SPI_JAR_PATH" "$KEYCLOAK_CONTAINER_NAME:$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME"

            # Step 3: Set appropriate file permissions
            echo "  [3/4] Setting file permissions..."
            docker exec --user root "$KEYCLOAK_CONTAINER_NAME" bash -c "chmod 644 '$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME'"

            # Step 4: Verify deployment
            echo "  [4/4] Verifying deployment..."
            docker exec "$KEYCLOAK_CONTAINER_NAME" ls -la "$SPI_PROVIDERS_PATH"

            echo ""
            echo "JAR deployed successfully"
            echo ""
            echo "IMPORTANT: Restart Keycloak to load the updated provider:"
            echo "  docker-compose restart $KEYCLOAK_CONTAINER_NAME"
            echo ""
            ;;
        *)
            echo ""
            echo "Deployment skipped"
            echo ""
            echo "Manual deployment steps:"
            echo "  1. Remove old JAR:"
            echo "     docker exec $KEYCLOAK_CONTAINER_NAME rm -f $SPI_PROVIDERS_PATH/$SPI_JAR_NAME"
            echo ""
            echo "  2. Copy new JAR:"
            echo "     docker cp $SPI_JAR_PATH $KEYCLOAK_CONTAINER_NAME:$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME"
            echo ""
            echo "  3. Restart Keycloak:"
            echo "     docker-compose restart $KEYCLOAK_CONTAINER_NAME"
            echo ""
            ;;
    esac
else
    echo "Keycloak container is not currently running"
    echo ""
    echo "Deployment steps (run after starting Keycloak):"
    echo "  docker cp $SPI_JAR_PATH $KEYCLOAK_CONTAINER_NAME:$SPI_PROVIDERS_PATH/$SPI_DESTINATION_NAME"
    echo "  docker-compose restart $KEYCLOAK_CONTAINER_NAME"
    echo ""
fi

# =====================================================
# NEXT STEPS
# =====================================================
echo "========================================"
echo "Build Process Complete"
echo "========================================"
echo ""
echo "Next Steps:"
echo "  1. Start services: make up"
echo "  2. Configure SPI: make setup-spi"
echo "  3. Test integration: make test-spi"
echo ""
