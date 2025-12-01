#!/bin/bash

#######################################
# LeaveBoard Self-Hosting Installer
# Complete deployment with one command
#######################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║     ██╗     ███████╗ █████╗ ██╗   ██╗███████╗    ║"
    echo "║     ██║     ██╔════╝██╔══██╗██║   ██║██╔════╝    ║"
    echo "║     ██║     █████╗  ███████║██║   ██║█████╗      ║"
    echo "║     ██║     ██╔══╝  ██╔══██║╚██╗ ██╔╝██╔══╝      ║"
    echo "║     ███████╗███████╗██║  ██║ ╚████╔╝ ███████╗    ║"
    echo "║     ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝    ║"
    echo "║                 BOARD                            ║"
    echo "║                                                  ║"
    echo "║          Self-Hosting Installer v1.0             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found. Installing..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        log_success "Docker installed"
    else
        log_success "Docker found"
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null 2>&1; then
        if ! command -v docker-compose &> /dev/null; then
            log_warn "Docker Compose not found. Installing..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            log_success "Docker Compose installed"
        fi
    else
        log_success "Docker Compose found"
    fi
    
    # Check available ports
    for port in 80 3080 5432 6379; do
        if lsof -i:$port &> /dev/null 2>&1; then
            log_warn "Port $port is in use"
        fi
    done
}

# Generate secure secrets
generate_secrets() {
    log_info "Generating secure secrets..."
    
    DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 48)
    
    log_success "Secrets generated"
}

# Create directory structure
setup_directories() {
    log_info "Setting up directory structure..."
    
    INSTALL_DIR="leaveboard"
    
    # Clean existing installation
    if [ -d "$INSTALL_DIR" ]; then
        log_warn "Existing installation found"
        read -p "Remove and reinstall? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd "$INSTALL_DIR" 2>/dev/null && docker compose down -v 2>/dev/null || true
            cd ..
            rm -rf "$INSTALL_DIR"
        else
            log_error "Installation cancelled"
            exit 1
        fi
    fi
    
    mkdir -p "$INSTALL_DIR"/{data/{postgres,redis},init/db,nginx,ssl}
    cd "$INSTALL_DIR"
    
    log_success "Directories created"
}

# Create configuration files
create_configs() {
    log_info "Creating configuration files..."
    
    # .env file
    cat > .env << EOF
# LeaveBoard Configuration
# Generated: $(date)

# Database
DB_USER=leaveboard
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=leaveboard
DB_PORT=5432

# Redis
REDIS_PORT=6379

# Application
APP_URL=http://localhost:3080
API_PORT=3080
WEB_PORT=80
JWT_SECRET=${JWT_SECRET}

# Email (configure for notifications)
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=noreply@leaveboard.local
EOF

    # docker-compose.yml
    cat > docker-compose.yml << 'COMPOSEOF'
version: '3.8'

services:
  db:
    container_name: leaveboard-db
    image: postgres:15-alpine
    restart: unless-stopped
    ports:
      - "${DB_PORT:-5432}:5432"
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
      - ./init/db:/docker-entrypoint-initdb.d
    environment:
      POSTGRES_USER: ${DB_USER:-leaveboard}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME:-leaveboard}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-leaveboard}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    container_name: leaveboard-redis
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - ./data/redis:/data
    command: redis-server --appendonly yes

  api:
    container_name: leaveboard-api
    image: node:20-alpine
    restart: unless-stopped
    working_dir: /app
    ports:
      - "${API_PORT:-3080}:3080"
    volumes:
      - ./app:/app
    environment:
      NODE_ENV: production
      PORT: 3080
      DATABASE_URL: postgres://${DB_USER:-leaveboard}:${DB_PASSWORD}@db:5432/${DB_NAME:-leaveboard}
      REDIS_URL: redis://redis:6379
      JWT_SECRET: ${JWT_SECRET}
      APP_URL: ${APP_URL:-http://localhost:3080}
    depends_on:
      db:
        condition: service_healthy
    command: node server/index.js

networks:
  default:
    name: leaveboard-network
COMPOSEOF

    log_success "Configuration files created"
}

# Create database init script
create_db_schema() {
    log_info "Creating database schema..."
    
    cat > init/db/01-schema.sql << 'SQLEOF'
-- LeaveBoard Database Schema

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    full_name VARCHAR(200),
    role VARCHAR(50) DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Employees
CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    job_title VARCHAR(100),
    team_id UUID,
    department_id UUID,
    role VARCHAR(50) DEFAULT 'employee',
    manager_email VARCHAR(255),
    annual_leave_entitlement DECIMAL DEFAULT 21,
    annual_leave_used DECIMAL DEFAULT 0,
    annual_leave_pending DECIMAL DEFAULT 0,
    sick_leave_used DECIMAL DEFAULT 0,
    bradford_factor_score INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Leave Types
CREATE TABLE IF NOT EXISTS leave_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    code VARCHAR(10) NOT NULL,
    color VARCHAR(20),
    requires_approval BOOLEAN DEFAULT TRUE,
    affects_bradford_factor BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Leave Requests
CREATE TABLE IF NOT EXISTS leave_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_email VARCHAR(255) NOT NULL,
    employee_name VARCHAR(200),
    leave_type_id UUID REFERENCES leave_types(id),
    leave_type_name VARCHAR(100),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_days DECIMAL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    approver_email VARCHAR(255),
    approval_date TIMESTAMP,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Locations
CREATE TABLE IF NOT EXISTS locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    region VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Departments
CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    location_id UUID REFERENCES locations(id),
    manager_email VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Teams
CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    department_id UUID REFERENCES departments(id),
    manager_email VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Notifications
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_email VARCHAR(255) NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert defaults
INSERT INTO leave_types (name, code, color, requires_approval, affects_bradford_factor) VALUES
    ('Annual Leave', 'AL', '#6366f1', true, false),
    ('Sick Leave', 'SL', '#ef4444', false, true),
    ('Compassionate Leave', 'CL', '#8b5cf6', true, false)
ON CONFLICT DO NOTHING;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_employees_email ON employees(user_email);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(employee_email);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);
SQLEOF

    log_success "Database schema created"
}

# Start services
start_services() {
    log_info "Starting services..."
    
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    
    log_success "Services started"
}

# Wait for services
wait_for_ready() {
    log_info "Waiting for services to be ready..."
    
    for i in {1..30}; do
        if docker exec leaveboard-db pg_isready -U leaveboard &> /dev/null; then
            log_success "Database is ready"
            break
        fi
        sleep 2
    done
}

# Print completion message
print_complete() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗"
    echo "║         Installation Complete!                   ║"
    echo "╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Your LeaveBoard instance is running!"
    echo ""
    echo -e "  ${CYAN}API Endpoint:${NC}    http://localhost:3080"
    echo -e "  ${CYAN}Database:${NC}        localhost:5432"
    echo -e "  ${CYAN}Redis:${NC}           localhost:6379"
    echo ""
    echo -e "Configuration saved in: ${YELLOW}leaveboard/.env${NC}"
    echo ""
    echo -e "Useful commands:"
    echo -e "  cd leaveboard"
    echo -e "  docker compose logs -f    # View logs"
    echo -e "  docker compose down       # Stop services"
    echo -e "  docker compose up -d      # Start services"
    echo ""
}

# Main
main() {
    print_banner
    check_requirements
    generate_secrets
    setup_directories
    create_configs
    create_db_schema
    
    echo ""
    read -p "Start services now? (Y/n) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        start_services
        wait_for_ready
    fi
    
    print_complete
}

main "$@"
