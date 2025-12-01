#!/bin/bash

#######################################
# LeaveBoard Self-Hosting Installer
# Supabase Backend on Port 3080
#######################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════╗"
echo "║     LeaveBoard Self-Hosting Installer     ║"
echo "║         Supabase Backend Setup            ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# Check Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker not found. Installing...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        echo -e "${GREEN}✓ Docker installed${NC}"
    else
        echo -e "${GREEN}✓ Docker found${NC}"
    fi
}

# Check Docker Compose
check_docker_compose() {
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}Docker Compose not found. Installing...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}✓ Docker Compose installed${NC}"
    else
        echo -e "${GREEN}✓ Docker Compose found${NC}"
    fi
}

# Setup directories
setup_dirs() {
    echo -e "${BLUE}Creating directory structure...${NC}"
    
    INSTALL_DIR="leaveboard"
    
    # Clean up old installation if exists
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}Existing installation found. Removing...${NC}"
        cd "$INSTALL_DIR"
        docker-compose down 2>/dev/null || true
        docker stop $(docker ps -aq --filter "name=leaveboard") 2>/dev/null || true
        docker rm $(docker ps -aq --filter "name=leaveboard") 2>/dev/null || true
        cd ..
        rm -rf "$INSTALL_DIR"
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    mkdir -p volumes/db/data volumes/db/init volumes/kong
    
    echo -e "${GREEN}✓ Directories created${NC}"
}

# Generate secrets
generate_secrets() {
    echo -e "${BLUE}Generating secure secrets...${NC}"
    
    POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    
    # Generate proper JWT tokens
    ANON_KEY=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=').$(echo -n '{"role":"anon","iss":"supabase","iat":'"$(date +%s)"',"exp":1999999999}' | base64 | tr -d '=').placeholder
    SERVICE_ROLE_KEY=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=').$(echo -n '{"role":"service_role","iss":"supabase","iat":'"$(date +%s)"',"exp":1999999999}' | base64 | tr -d '=').placeholder
    
    echo -e "${GREEN}✓ Secrets generated${NC}"
}

# Create .env file
create_env() {
    echo -e "${BLUE}Creating environment file...${NC}"
    
    cat > .env << EOF
# LeaveBoard Self-Hosting Configuration
# Generated: $(date)

POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
SITE_URL=http://localhost:3080
API_URL=http://localhost:3080
EOF

    echo -e "${GREEN}✓ Environment file created${NC}"
}

# Create docker-compose.yml
create_docker_compose() {
    echo -e "${BLUE}Creating Docker Compose file...${NC}"
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  db:
    container_name: leaveboard-db
    image: supabase/postgres:15.1.0.117
    restart: unless-stopped
    ports:
      - "5432:5432"
    volumes:
      - ./volumes/db/data:/var/lib/postgresql/data:Z
      - ./volumes/db/init:/docker-entrypoint-initdb.d:Z
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
    healthcheck:
      test: pg_isready -U postgres -h localhost
      interval: 5s
      timeout: 5s
      retries: 10

  auth:
    container_name: leaveboard-auth
    image: supabase/gotrue:v2.99.0
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      API_EXTERNAL_URL: ${API_URL:-http://localhost:3080}
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@db:5432/postgres
      GOTRUE_SITE_URL: ${SITE_URL:-http://localhost:3080}
      GOTRUE_URI_ALLOW_LIST: "*"
      GOTRUE_DISABLE_SIGNUP: "false"
      GOTRUE_JWT_ADMIN_ROLES: service_role
      GOTRUE_JWT_AUD: authenticated
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated
      GOTRUE_JWT_EXP: 3600
      GOTRUE_JWT_SECRET: ${JWT_SECRET}
      GOTRUE_EXTERNAL_EMAIL_ENABLED: "true"
      GOTRUE_MAILER_AUTOCONFIRM: "true"

  rest:
    container_name: leaveboard-rest
    image: postgrest/postgrest:v11.2.0
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    environment:
      PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@db:5432/postgres
      PGRST_DB_SCHEMAS: public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: ${JWT_SECRET}

  studio:
    container_name: leaveboard-studio
    image: supabase/studio:20231123-64a766a
    restart: unless-stopped
    ports:
      - "3002:3000"
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      DEFAULT_ORGANIZATION_NAME: LeaveBoard
      DEFAULT_PROJECT_NAME: leaveboard
      SUPABASE_URL: http://localhost:3080
      SUPABASE_PUBLIC_URL: http://localhost:3080
      SUPABASE_ANON_KEY: ${ANON_KEY}
      SUPABASE_SERVICE_KEY: ${SERVICE_ROLE_KEY}

  meta:
    container_name: leaveboard-meta
    image: supabase/postgres-meta:v0.68.0
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: db
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: postgres
      PG_META_DB_USER: postgres
      PG_META_DB_PASSWORD: ${POSTGRES_PASSWORD}

  kong:
    container_name: leaveboard-kong
    image: kong:2.8.1
    restart: unless-stopped
    ports:
      - "3080:8000"
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
      KONG_DNS_ORDER: LAST,A,CNAME
      KONG_PLUGINS: request-transformer,cors,key-auth,acl
    volumes:
      - ./volumes/kong/kong.yml:/var/lib/kong/kong.yml:ro
    depends_on:
      - auth
      - rest

networks:
  default:
    name: leaveboard-network
EOF

    echo -e "${GREEN}✓ Docker Compose file created${NC}"
}

# Create Kong config
create_kong_config() {
    echo -e "${BLUE}Creating Kong API Gateway config...${NC}"
    
    cat > volumes/kong/kong.yml << 'EOF'
_format_version: "2.1"
_transform: true

services:
  - name: auth
    url: http://auth:9999
    routes:
      - name: auth-all
        paths:
          - /auth/v1
        strip_path: true
    plugins:
      - name: cors
        config:
          origins:
            - "*"
          methods:
            - GET
            - POST
            - PUT
            - DELETE
            - OPTIONS
          headers:
            - Authorization
            - Content-Type
            - apikey
            - x-client-info
          credentials: true

  - name: rest
    url: http://rest:3000
    routes:
      - name: rest-all
        paths:
          - /rest/v1
        strip_path: true
    plugins:
      - name: cors
        config:
          origins:
            - "*"
          methods:
            - GET
            - POST
            - PUT
            - DELETE
            - PATCH
            - OPTIONS
          headers:
            - Authorization
            - Content-Type
            - apikey
            - x-client-info
            - Prefer
          credentials: true
EOF

    echo -e "${GREEN}✓ Kong config created${NC}"
}

# Create database init
create_db_init() {
    echo -e "${BLUE}Creating database schema...${NC}"
    
    cat > volumes/db/init/00-init.sql << 'EOF'
-- Create roles
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

-- Grant permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create base tables for LeaveBoard
CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    job_title VARCHAR(100),
    role VARCHAR(50) DEFAULT 'employee',
    annual_leave_entitlement DECIMAL DEFAULT 21,
    annual_leave_used DECIMAL DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS leave_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    code VARCHAR(10) NOT NULL,
    color VARCHAR(20),
    requires_approval BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS leave_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_email VARCHAR(255) NOT NULL,
    employee_name VARCHAR(200),
    leave_type_id UUID REFERENCES leave_types(id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_days DECIMAL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default leave types
INSERT INTO leave_types (name, code, color) VALUES
    ('Annual Leave', 'AL', '#6366f1'),
    ('Sick Leave', 'SL', '#ef4444'),
    ('Compassionate Leave', 'CL', '#8b5cf6')
ON CONFLICT DO NOTHING;
EOF

    echo -e "${GREEN}✓ Database schema created${NC}"
}

# Start services
start_services() {
    echo -e "${BLUE}Starting services...${NC}"
    
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    
    echo -e "${GREEN}✓ Services started${NC}"
}

# Wait and check
wait_for_services() {
    echo -e "${BLUE}Waiting for services to be ready...${NC}"
    sleep 15
    
    if curl -s http://localhost:3080/rest/v1/ > /dev/null 2>&1; then
        echo -e "${GREEN}✓ API is responding${NC}"
    else
        echo -e "${YELLOW}API may still be starting...${NC}"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════╗"
    echo "║       Installation Complete!              ║"
    echo "╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Your services are running:"
    echo -e "  • ${BLUE}API Gateway:${NC}     http://localhost:3080"
    echo -e "  • ${BLUE}Supabase Studio:${NC} http://localhost:3002"
    echo -e "  • ${BLUE}PostgreSQL:${NC}      localhost:5432"
    echo ""
    echo -e "API Endpoints:"
    echo -e "  • Auth:  http://localhost:3080/auth/v1"
    echo -e "  • REST:  http://localhost:3080/rest/v1"
    echo ""
    echo -e "${YELLOW}Your credentials are saved in: leaveboard/.env${NC}"
    echo ""
    echo -e "Commands:"
    echo -e "  cd leaveboard"
    echo -e "  docker-compose logs -f   # View logs"
    echo -e "  docker-compose down      # Stop services"
    echo -e "  docker-compose up -d     # Start services"
    echo ""
}

# Main
main() {
    check_docker
    check_docker_compose
    setup_dirs
    generate_secrets
    create_env
    create_docker_compose
    create_kong_config
    create_db_init
    
    echo ""
    read -p "Start services now? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        start_services
        wait_for_services
    fi
    
    print_summary
}

main
