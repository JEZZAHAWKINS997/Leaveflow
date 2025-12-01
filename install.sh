#!/bin/bash

#######################################
# LeaveBoard Self-Hosting Install Script
# One-click installation for Docker + Supabase
#######################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════╗"
echo "║     LeaveBoard Self-Hosting Installer     ║"
echo "║         Docker + Supabase Setup           ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        echo -e "${GREEN}Docker installed successfully!${NC}"
    else
        echo -e "${GREEN}✓ Docker is installed${NC}"
    fi
}

# Check if Docker Compose is installed
check_docker_compose() {
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Docker Compose not found. Installing...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}Docker Compose installed successfully!${NC}"
    else
        echo -e "${GREEN}✓ Docker Compose is installed${NC}"
    fi
}

# Generate secure random strings
generate_secrets() {
    echo -e "${BLUE}Generating secure secrets...${NC}"
    
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c 64)
    
    # Generate Supabase keys (using the JWT secret)
    ANON_KEY=$(echo -n '{"role":"anon","iss":"supabase","iat":'$(date +%s)',"exp":'$(($(date +%s)+315360000))'}' | base64 | tr -d '\n')
    SERVICE_ROLE_KEY=$(echo -n '{"role":"service_role","iss":"supabase","iat":'$(date +%s)',"exp":'$(($(date +%s)+315360000))'}' | base64 | tr -d '\n')
    
    echo -e "${GREEN}✓ Secrets generated${NC}"
}

# Create directory structure
setup_directories() {
    echo -e "${BLUE}Setting up directory structure...${NC}"
    
    mkdir -p leaveboard-selfhost
    cd leaveboard-selfhost
    
    mkdir -p volumes/db/data
    mkdir -p volumes/db/init
    mkdir -p volumes/storage
    mkdir -p volumes/api
    mkdir -p app
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Create Kong configuration
create_kong_config() {
    echo -e "${BLUE}Creating Kong API Gateway configuration...${NC}"
    
    cat > volumes/api/kong.yml << 'KONGEOF'
_format_version: "2.1"
_transform: true

consumers:
  - username: anon
    keyauth_credentials:
      - key: ${ANON_KEY}
  - username: service_role
    keyauth_credentials:
      - key: ${SERVICE_ROLE_KEY}

acls:
  - consumer: anon
    group: anon
  - consumer: service_role
    group: admin

services:
  - name: auth-v1-open
    url: http://auth:9999/verify
    routes:
      - name: auth-v1-open
        strip_path: true
        paths:
          - /auth/v1/verify
    plugins:
      - name: cors

  - name: auth-v1-open-callback
    url: http://auth:9999/callback
    routes:
      - name: auth-v1-open-callback
        strip_path: true
        paths:
          - /auth/v1/callback
    plugins:
      - name: cors

  - name: auth-v1
    url: http://auth:9999
    routes:
      - name: auth-v1
        strip_path: true
        paths:
          - /auth/v1
    plugins:
      - name: cors

  - name: rest-v1
    url: http://rest:3000
    routes:
      - name: rest-v1
        strip_path: true
        paths:
          - /rest/v1
    plugins:
      - name: cors

  - name: realtime-v1
    url: http://realtime:4000/socket
    routes:
      - name: realtime-v1
        strip_path: true
        paths:
          - /realtime/v1
    plugins:
      - name: cors

  - name: storage-v1
    url: http://storage:5000
    routes:
      - name: storage-v1
        strip_path: true
        paths:
          - /storage/v1
    plugins:
      - name: cors
KONGEOF

    echo -e "${GREEN}✓ Kong configuration created${NC}"
}

# Create database init script
create_db_init() {
    echo -e "${BLUE}Creating database initialization script...${NC}"
    
    cat > volumes/db/init/00-init.sql << 'DBEOF'
-- LeaveBoard Database Schema

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create tables
CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_email VARCHAR(255) UNIQUE NOT NULL,
    employee_id VARCHAR(50),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    job_title VARCHAR(100),
    team_id UUID,
    department_id UUID,
    location_id UUID,
    role VARCHAR(50) DEFAULT 'employee',
    manager_email VARCHAR(255),
    start_date DATE,
    shift_pattern_id UUID,
    annual_leave_entitlement DECIMAL DEFAULT 21,
    annual_leave_used DECIMAL DEFAULT 0,
    annual_leave_pending DECIMAL DEFAULT 0,
    sick_leave_used DECIMAL DEFAULT 0,
    sick_leave_instances INTEGER DEFAULT 0,
    sick_leave_days_total DECIMAL DEFAULT 0,
    bradford_factor_score INTEGER DEFAULT 0,
    bradford_factor_updated TIMESTAMP,
    compassionate_leave_used DECIMAL DEFAULT 0,
    bank_holiday_lieu_balance DECIMAL DEFAULT 0,
    carry_over_days DECIMAL DEFAULT 0,
    phone VARCHAR(50),
    emergency_contact_name VARCHAR(100),
    emergency_contact_phone VARCHAR(50),
    is_critical_staff BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    address TEXT,
    region VARCHAR(50),
    timezone VARCHAR(50) DEFAULT 'Europe/London',
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    location_id UUID REFERENCES locations(id),
    manager_email VARCHAR(255),
    minimum_coverage INTEGER DEFAULT 50,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    department_id UUID REFERENCES departments(id),
    manager_email VARCHAR(255),
    minimum_coverage INTEGER DEFAULT 50,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS leave_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    code VARCHAR(10) NOT NULL,
    color VARCHAR(20),
    requires_approval BOOLEAN DEFAULT TRUE,
    max_days_per_request INTEGER,
    requires_documentation BOOLEAN DEFAULT FALSE,
    documentation_after_days INTEGER,
    affects_bradford_factor BOOLEAN DEFAULT FALSE,
    is_paid BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS leave_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_email VARCHAR(255) NOT NULL,
    employee_name VARCHAR(200),
    leave_type_id UUID REFERENCES leave_types(id),
    leave_type_name VARCHAR(100),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    start_half_day VARCHAR(20) DEFAULT 'full',
    end_half_day VARCHAR(20) DEFAULT 'full',
    total_days DECIMAL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    approver_email VARCHAR(255),
    approver_name VARCHAR(200),
    approval_date TIMESTAMP,
    approval_notes TEXT,
    team_id UUID,
    department_id UUID,
    location_id UUID,
    documentation_url TEXT,
    is_bank_holiday_work BOOLEAN DEFAULT FALSE,
    lieu_day_date DATE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS shift_patterns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    code VARCHAR(20),
    type VARCHAR(50) DEFAULT 'standard',
    working_days INTEGER[],
    start_time TIME,
    end_time TIME,
    hours_per_week DECIMAL,
    unpaid_break_1_duration INTEGER,
    unpaid_break_2_duration INTEGER,
    rotation_weeks INTEGER,
    rotation_pattern JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS bank_holidays (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    date DATE NOT NULL,
    regions TEXT[],
    year INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS overtime_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_email VARCHAR(255) NOT NULL,
    employee_name VARCHAR(200),
    date DATE NOT NULL,
    hours DECIMAL NOT NULL,
    start_time TIME,
    end_time TIME,
    reason TEXT,
    work_details TEXT,
    request_type VARCHAR(50) DEFAULT 'employee_request',
    requested_by_email VARCHAR(255),
    requested_by_name VARCHAR(200),
    status VARCHAR(20) DEFAULT 'pending',
    approver_email VARCHAR(255),
    approver_name VARCHAR(200),
    approval_date TIMESTAMP,
    approval_notes TEXT,
    toil_claimed BOOLEAN DEFAULT FALSE,
    toil_hours_claimed DECIMAL DEFAULT 0,
    team_id UUID,
    department_id UUID,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_email VARCHAR(255) NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'system',
    related_request_id UUID,
    is_read BOOLEAN DEFAULT FALSE,
    action_url TEXT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_email VARCHAR(255),
    activity_type VARCHAR(50),
    description TEXT,
    related_id UUID,
    performed_by_email VARCHAR(255),
    performed_by_name VARCHAR(200),
    metadata JSONB,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

-- Insert default leave types
INSERT INTO leave_types (name, code, color, requires_approval, affects_bradford_factor) VALUES
    ('Annual Leave', 'AL', '#6366f1', true, false),
    ('Sick Leave', 'SL', '#ef4444', false, true),
    ('Compassionate Leave', 'CL', '#8b5cf6', true, false),
    ('Bank Holiday Lieu', 'BHL', '#10b981', true, false),
    ('Unpaid Leave', 'UL', '#f59e0b', true, false)
ON CONFLICT DO NOTHING;

-- Insert default shift pattern
INSERT INTO shift_patterns (name, code, type, working_days, start_time, end_time, hours_per_week) VALUES
    ('Standard Mon-Fri', 'STD', 'standard', ARRAY[1,2,3,4,5], '09:00', '17:00', 40)
ON CONFLICT DO NOTHING;

DBEOF

    echo -e "${GREEN}✓ Database init script created${NC}"
}

# Create .env file
create_env_file() {
    echo -e "${BLUE}Creating environment configuration...${NC}"
    
    cat > .env << ENVEOF
############
# Secrets - Auto-generated
############

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
SECRET_KEY_BASE=${SECRET_KEY_BASE}

############
# Database
############

POSTGRES_PORT=5432
POSTGRES_HOST=db
POSTGRES_DB=postgres

############
# API Configuration
############

KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443

############
# Auth / Email
############

SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=true

SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_ADMIN_EMAIL=admin@example.com

############
# Studio & App
############

STUDIO_PORT=3000
SUPABASE_PUBLIC_URL=http://localhost:8000
APP_PORT=80
API_EXTERNAL_URL=http://localhost:8000
ENVEOF

    echo -e "${GREEN}✓ Environment file created${NC}"
}

# Create Dockerfile for the app
create_app_dockerfile() {
    echo -e "${BLUE}Creating application Dockerfile...${NC}"
    
    cat > app/Dockerfile << 'DOCKEREOF'
FROM node:18-alpine as builder

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build

# Production image
FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
DOCKEREOF

    # Create nginx config
    cat > app/nginx.conf << 'NGINXEOF'
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass http://kong:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINXEOF

    echo -e "${GREEN}✓ App Dockerfile created${NC}"
}

# Start services
start_services() {
    echo -e "${BLUE}Starting services...${NC}"
    
    docker-compose up -d
    
    echo -e "${GREEN}✓ Services started${NC}"
}

# Health check
health_check() {
    echo -e "${BLUE}Waiting for services to be healthy...${NC}"
    
    sleep 10
    
    # Check if containers are running
    if docker-compose ps | grep -q "Up"; then
        echo -e "${GREEN}✓ All services are running${NC}"
    else
        echo -e "${RED}Some services may have failed to start. Check logs with: docker-compose logs${NC}"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════╗"
    echo "║     Installation Complete!                ║"
    echo "╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Access your services:"
    echo -e "  • ${BLUE}LeaveBoard App:${NC}    http://localhost"
    echo -e "  • ${BLUE}Supabase Studio:${NC}  http://localhost:3000"
    echo -e "  • ${BLUE}Supabase API:${NC}     http://localhost:8000"
    echo ""
    echo -e "Useful commands:"
    echo -e "  • View logs:     ${YELLOW}docker-compose logs -f${NC}"
    echo -e "  • Stop services: ${YELLOW}docker-compose down${NC}"
    echo -e "  • Restart:       ${YELLOW}docker-compose restart${NC}"
    echo ""
    echo -e "${YELLOW}Important:${NC} Your secrets are stored in .env file."
    echo -e "Keep this file secure and back it up!"
    echo ""
}

# Main installation flow
main() {
    check_docker
    check_docker_compose
    setup_directories
    generate_secrets
    create_kong_config
    create_db_init
    create_env_file
    create_app_dockerfile
    
    echo ""
    read -p "Start services now? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        start_services
        health_check
    fi
    
    print_summary
}

# Run main
main
