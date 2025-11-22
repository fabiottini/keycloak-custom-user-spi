# =====================================================
# PARAMETERIZED MAKEFILE FOR SSO PROJECT
# =====================================================
# Makefile for complete project management with centralized configuration

# Include configuration (if exists)
CONFIG_FILE := .env
ifneq (,$(wildcard $(CONFIG_FILE)))
    include $(CONFIG_FILE)
else
    $(warning ⚠️  Configuration file $(CONFIG_FILE) not found - using default values)
endif

# Default values if .env is not available
DB_CONTAINER ?= user-postgres
DB_NAME ?= user
DB_USER ?= user
DB_PASSWORD ?= user_password
DB_SCHEMA_FILE ?= user_db_schema_data.sql
KEYCLOAK_CONTAINER_NAME ?= keycloak
APACHE1_CONTAINER_NAME ?= apache-php-1
APACHE2_CONTAINER_NAME ?= apache-php-2
ADMINER_CONTAINER_NAME ?= adminer
KEYCLOAK_HOST ?= localhost
KEYCLOAK_PORT ?= 8080
APACHE1_PORT ?= 8083
ADMINER_PORT ?= 8084
MAX_WAIT_ATTEMPTS ?= 120
WAIT_INTERVAL ?= 5

# Colors for output
GREEN=\033[0;32m
YELLOW=\033[1;33m
RED=\033[0;31m
BLUE=\033[0;34m
NC=\033[0m # No Color

.PHONY: help config check-config build up down logs clean setup-spi remove-spi test-spi restart status build-spi logs-keycloak logs-user-db logs-apache1 logs-apache2 logs-adminer update-client-secrets

help: ## Show this help message
	@echo "$(BLUE)=====================================================$(NC)"
	@echo "$(BLUE)           PARAMETERIZED SSO PROJECT MAKEFILE$(NC)"
	@echo "$(BLUE)=====================================================$(NC)"
	@echo ""
	@echo "$(YELLOW)📋 Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "}; /^[a-zA-Z_-]+:.*?## / {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort
	@echo ""
	@echo "$(YELLOW)🔧 Current configuration:$(NC)"
	@echo "   Database: $(DB_CONTAINER_NAME) ($(DB_USER)@$(DB_NAME))"
	@echo "   Keycloak: $(KEYCLOAK_HOST):$(KEYCLOAK_PORT)"
	@echo "   Apache 1: $(KEYCLOAK_HOST):$(APACHE1_PORT)"
	@echo ""

config: ## Show complete loaded configuration
	@echo "$(BLUE)🔧 Testing and displaying configuration...$(NC)"
	@./scripts/config-loader.sh

check-config: ## Verify that configuration file is valid
	@echo "$(YELLOW)🔍 Checking configuration...$(NC)"
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		echo "$(RED)❌ Configuration file $(CONFIG_FILE) not found!$(NC)"; \
		echo "$(YELLOW)💡 Suggestion: The file should exist in the current directory$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ Configuration file $(CONFIG_FILE) found$(NC)"
	@./scripts/config-loader.sh > /dev/null && echo "$(GREEN)✅ Configuration is valid$(NC)" || echo "$(RED)❌ Configuration is not valid$(NC)"

build: check-config ## Build Docker containers
	@echo "$(YELLOW)🏗️  Building Docker containers...$(NC)"
	rm -rf custom-user-spi/target/*
	docker-compose build

up: check-config ## Start all services
	@echo "$(YELLOW)🚀 Starting all services...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)✅ Services started!$(NC)"
	@echo "$(BLUE)🌐 Available URLs:$(NC)"
	@echo "   Keycloak: http://$(KEYCLOAK_HOST):$(KEYCLOAK_PORT)"
	@echo "   Apache 1: http://$(KEYCLOAK_HOST):$(APACHE1_PORT)"

down: ## Stop all services
	@echo "$(YELLOW)🛑 Stopping all services...$(NC)"
	docker-compose down
	@echo "$(GREEN)✅ Services stopped!$(NC)"

down-clean: ## Stop all services and clean everything
	@echo "$(YELLOW)🛑 Stopping all services...$(NC)"
	docker-compose down -v
	@echo "$(GREEN)✅ Services stopped and cleaned!$(NC)"

logs: ## Show logs of all services
	@echo "$(YELLOW)📋 Logs of all services...$(NC)"
	docker-compose logs -f

clean: ## Clean everything (containers, volumes, images)
	@echo "$(RED)🧹 Complete project cleanup...$(NC)"
	@echo "$(YELLOW)⚠️  This will remove all persistent data!$(NC)"
	@read -p "Are you sure? [y/N]: " confirm && [ "$$confirm" = "y" ] || exit 1
	docker-compose down -v --rmi all
# docker system prune -f
	@echo "$(GREEN)✅ Cleanup completed!$(NC)"

setup-spi: check-config ## Configure custom SPI in Keycloak (removes old one if exists)
	@echo "$(YELLOW)🚀 Configuring custom SPI...$(NC)"
	@./scripts/setup-spi.sh

remove-spi: check-config ## Remove User Federation component from Keycloak
	@echo "$(YELLOW)🗑️  Removing User Federation component...$(NC)"
	@./scripts/remove_component.sh
	@echo "$(GREEN)✅ User Federation component removed!$(NC)"

test-spi: check-config ## Test SPI integration
	@echo "$(YELLOW)🧪 Testing SPI integration...$(NC)"
	@echo "$(BLUE)1. Checking if Keycloak is running:$(NC)"
	@curl -s http://$(KEYCLOAK_HOST):$(KEYCLOAK_PORT)/health > /dev/null && \
		echo "$(GREEN)✅ Keycloak reachable$(NC)" || \
		echo "$(RED)❌ Keycloak not reachable$(NC)"
	@echo ""
	@echo "$(BLUE)2. Checking if user database is accessible:$(NC)"
	@docker exec $(DB_CONTAINER_NAME) psql -U $(DB_USER) -d $(DB_NAME) -c "SELECT COUNT(*) FROM $(DB_TABLE_NAME);" 2>/dev/null && \
		echo "$(GREEN)✅ User database accessible$(NC)" || \
		echo "$(RED)❌ User database not accessible$(NC)"
	@echo ""
	@echo "$(BLUE)3. Authentication test available:$(NC)"
	@echo "   🌐 Go to: http://$(KEYCLOAK_HOST):$(APACHE1_PORT)"
	@echo "   👤 Test users configured in database"

restart: down up ## Restart all services

status: ## Show services status
	@echo "$(BLUE)📊 Services status:$(NC)"
	@docker-compose ps

# Development-specific commands
build-spi: check-config ## Build only the custom SPI
	@echo "$(YELLOW)🔨 Building custom SPI...$(NC)"
	@./scripts/build-spi.sh

update-jar: check-config ## Update JAR in running Keycloak without rebuilding
	@echo "$(YELLOW)🔄 Updating JAR in Keycloak...$(NC)"
	@set -a; source .env; set +a; \
	if ! docker ps --format "table {{.Names}}" | grep -q "^$(KEYCLOAK_CONTAINER_NAME)$$"; then \
		echo "$(RED)❌ Keycloak container '$(KEYCLOAK_CONTAINER_NAME)' is not running$(NC)"; \
		echo "$(YELLOW)💡 Start services first with: make up$(NC)"; \
		exit 1; \
	fi; \
	SPI_JAR_PATH="$$SPI_TARGET_DIR/$$SPI_JAR_NAME"; \
	if [ ! -f "$$SPI_JAR_PATH" ]; then \
		echo "$(RED)❌ JAR file not found: $$SPI_JAR_PATH$(NC)"; \
		echo "$(YELLOW)💡 Build SPI first with: make build-spi$(NC)"; \
		exit 1; \
	fi; \
	echo "$(BLUE)🗑️  Removing existing JAR...$(NC)"; \
	docker exec $(KEYCLOAK_CONTAINER_NAME) rm -f "$$SPI_PROVIDERS_PATH/$$SPI_JAR_NAME" 2>/dev/null || true; \
	docker exec $(KEYCLOAK_CONTAINER_NAME) rm -f "$$SPI_PROVIDERS_PATH/$$SPI_DESTINATION_NAME" 2>/dev/null || true; \
	echo "$(BLUE)📥 Copying new JAR ($$SPI_JAR_PATH)...$(NC)"; \
	docker cp "$$SPI_JAR_PATH" "$(KEYCLOAK_CONTAINER_NAME):$$SPI_PROVIDERS_PATH/$$SPI_DESTINATION_NAME"; \
	echo "$(BLUE)🔐 Setting permissions...$(NC)"; \
	docker exec --user root $(KEYCLOAK_CONTAINER_NAME) bash -c "chmod 644 '$$SPI_PROVIDERS_PATH/$$SPI_DESTINATION_NAME'"; \
	echo "$(GREEN)✅ JAR updated successfully!$(NC)"; \
	echo "$(YELLOW)🔄 Restart Keycloak to load changes:$(NC)"; \
	echo "   make restart-keycloak"
	make restart-keycloak

restart-keycloak: check-config ## Restart only Keycloak container
	@echo "$(YELLOW)🔄 Restarting Keycloak...$(NC)"
	docker-compose restart $(KEYCLOAK_CONTAINER_NAME)
	@echo "$(GREEN)✅ Keycloak restarted!$(NC)"

update-client-secrets: check-config ## Download client secrets from Keycloak and update .env file, then restart Apache containers
	@echo "$(YELLOW)🔑 Updating client secrets from Keycloak...$(NC)"
	@./scripts/update-client-secrets.sh
	@echo "$(YELLOW)🔄 Restarting Apache containers with new client secrets...$(NC)"
	docker-compose down $(APACHE1_CONTAINER_NAME) $(APACHE2_CONTAINER_NAME) && docker-compose up -d $(APACHE1_CONTAINER_NAME) $(APACHE2_CONTAINER_NAME)
	@echo "$(GREEN)✅ Client secrets updated and Apache containers restarted!$(NC)"

logs-keycloak: ## Keycloak logs
	@echo "$(YELLOW)📋 Keycloak logs...$(NC)"
	docker-compose logs -f $(KEYCLOAK_CONTAINER_NAME)

logs-user-db: ## User database logs
	@echo "$(YELLOW)📋 User database logs...$(NC)"
	docker-compose logs -f $(DB_CONTAINER_NAME)

logs-apache1: ## First Apache logs
	@echo "$(YELLOW)📋 First Apache logs...$(NC)"
	docker-compose logs -f $(APACHE1_CONTAINER_NAME)

logs-apache2: ## Second Apache logs
	@echo "$(YELLOW)📋 Second Apache logs...$(NC)"
	docker-compose logs -f $(APACHE2_CONTAINER_NAME)

logs-adminer: ## Adminer database tool logs
	@echo "$(YELLOW)📋 Adminer logs...$(NC)"
	docker-compose logs -f $(ADMINER_CONTAINER_NAME)

# User database management commands
db-setup: check-config ## Create database and apply schema
	@echo "$(YELLOW)🗄️  Setting up user database...$(NC)"
	@docker exec $(DB_CONTAINER_NAME) psql -U $(DB_USER) -d postgres -c "CREATE DATABASE $(DB_NAME);" 2>/dev/null || echo "Database $(DB_NAME) already exists"
	@docker exec -i $(DB_CONTAINER_NAME) psql -U $(DB_USER) -d $(DB_NAME) < $(DB_SCHEMA_FILE)
	@echo "$(GREEN)✅ Database schema applied successfully$(NC)"

db-clean: check-config ## Clean user database (remove all tables)
	@echo "$(YELLOW)🧹 Cleaning user database...$(NC)"
	@docker exec $(DB_CONTAINER_NAME) psql -U $(DB_USER) -d $(DB_NAME) -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || echo "$(RED)❌ Error cleaning database$(NC)"
	@echo "$(GREEN)✅ User database cleaned$(NC)"

db-reset: db-clean db-setup ## Complete database reset (clean and recreate)

db-show-users: check-config ## Show all users in database
	@echo "$(YELLOW)👥 Users in database:$(NC)"
	@docker exec $(DB_CONTAINER_NAME) psql -U $(DB_USER) -d $(DB_NAME) -c "SELECT username, mail, nome, cognome FROM $(DB_TABLE_NAME);" 2>/dev/null || echo "$(RED)❌ Users table not found$(NC)"

db-shell: check-config ## Open SQL shell in user database
	@echo "$(YELLOW)🐚 Opening database shell...$(NC)"
	@docker exec -it $(DB_CONTAINER_NAME) psql -U $(DB_USER) -d $(DB_NAME)

# Advanced commands
dev-full-reset: clean up setup-spi ## Complete development environment reset
	@echo "$(GREEN)🎉 Development environment completely reset and configured!$(NC)"

dev-update-spi: build-spi ## Update only SPI during development
	@echo "$(YELLOW)🔄 Updating SPI in development environment...$(NC)"
	@if docker ps --format "table {{.Names}}" | grep -q "^$(KEYCLOAK_CONTAINER_NAME)$$"; then \
		echo "$(BLUE)♻️  Restarting Keycloak with new SPI...$(NC)"; \
		docker-compose restart $(KEYCLOAK_CONTAINER_NAME); \
		echo "$(GREEN)✅ SPI updated!$(NC)"; \
	else \
		echo "$(RED)❌ Keycloak is not running$(NC)"; \
		echo "$(YELLOW)💡 Start services first with: make up$(NC)"; \
	fi

show-urls: check-config ## Show all available URLs
	@echo "$(BLUE)🌐 Available URLs:$(NC)"
	@echo "$(GREEN)🔧 Keycloak Admin Console:$(NC)"
	@echo "   http://$(KEYCLOAK_HOST):$(KEYCLOAK_PORT)/admin"
	@echo "   Username: $(KEYCLOAK_ADMIN_USER)"
	@echo ""
	@echo "$(GREEN)🌐 Test Applications:$(NC)"
	@echo "   Apache 1: http://$(KEYCLOAK_HOST):$(APACHE1_PORT)"
	@echo "   Apache 2: http://$(KEYCLOAK_HOST):$(APACHE2_PORT)"
	@echo ""
	@echo "$(GREEN)🗄️ Database Management (Adminer):$(NC)"
	@echo "   URL: http://$(KEYCLOAK_HOST):$(ADMINER_PORT)"
	@echo "   Keycloak DB: keycloak-db (user: keycloak, db: keycloak)"
	@echo "   Custom User DB: user-db (user: user, db: user)"
	@echo ""
	@echo "$(GREEN)🔍 Health Check:$(NC)"
	@echo "   Keycloak: http://$(KEYCLOAK_HOST):$(KEYCLOAK_PORT)/health"

# Configuration info
info: config show-urls ## Show all configuration information and URLs

wait_keycloak_step:
	@echo "⏳ Waiting for Keycloak to be ready..."
	@attempt=0; until curl -s "http://$(KEYCLOAK_HOST):$(KEYCLOAK_PORT)/health" > /dev/null 2>&1; do \
		echo "Keycloak not ready yet, waiting... (attempt $$(expr $$attempt + 1)/$(MAX_WAIT_ATTEMPTS))"; \
		attempt=$$(expr $$attempt + 1); \
		if [ $$attempt -ge "$(MAX_WAIT_ATTEMPTS)" ]; then \
			echo "❌ Timeout: Keycloak not responding after $(MAX_WAIT_ATTEMPTS) attempts"; \
			exit 1; \
		fi; \
		sleep "$(WAIT_INTERVAL)"; \
	done
	@echo "✅ Keycloak is ready!"

create-component: check-config ## Create component in Keycloak
	@echo "$(YELLOW)🔧 Creating component in Keycloak...$(NC)"
	@./scripts/create_component.sh


setup-from-scratch: ## Setup from scratch all services 
	make down-clean
	make clean
	make build
	make build-spi
	make up
	make wait_keycloak_step
	make setup-spi
	make db-setup
	make db-show-users
	make show-urls