-- LeaveBoard Database Schema
-- Auto-generated for self-hosting

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    full_name VARCHAR(200),
    role VARCHAR(50) DEFAULT 'user',
    email_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Employees table
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

-- Locations table
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

-- Departments table
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

-- Teams table
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

-- Leave types table
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

-- Leave requests table
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

-- Shift patterns table
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

-- Bank holidays table
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

-- Overtime requests table
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

-- Lieu day requests table
CREATE TABLE IF NOT EXISTS lieu_day_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_email VARCHAR(255) NOT NULL,
    employee_name VARCHAR(200),
    work_date DATE NOT NULL,
    work_type VARCHAR(50),
    lieu_date DATE NOT NULL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    approver_email VARCHAR(255),
    approver_name VARCHAR(200),
    approval_date TIMESTAMP,
    approval_notes TEXT,
    team_id UUID,
    department_id UUID,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

-- Day swap requests table
CREATE TABLE IF NOT EXISTS day_swap_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    requester_email VARCHAR(255) NOT NULL,
    requester_name VARCHAR(200),
    swap_with_email VARCHAR(255) NOT NULL,
    swap_with_name VARCHAR(200),
    requester_work_date DATE NOT NULL,
    requester_off_date DATE NOT NULL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'pending_colleague',
    colleague_approved BOOLEAN DEFAULT FALSE,
    colleague_response_date TIMESTAMP,
    manager_email VARCHAR(255),
    manager_name VARCHAR(200),
    manager_approval_date TIMESTAMP,
    manager_notes TEXT,
    team_id UUID,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

-- Notifications table
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

-- Activity logs table
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

-- Approval delegations table
CREATE TABLE IF NOT EXISTS approval_delegations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    delegator_email VARCHAR(255) NOT NULL,
    delegate_email VARCHAR(255) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

-- Blocked dates table
CREATE TABLE IF NOT EXISTS blocked_dates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    date DATE NOT NULL,
    reason TEXT,
    team_id UUID,
    department_id UUID,
    location_id UUID,
    created_by_email VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255)
);

-- Insert default data
INSERT INTO leave_types (name, code, color, requires_approval, affects_bradford_factor) VALUES
    ('Annual Leave', 'AL', '#6366f1', true, false),
    ('Sick Leave', 'SL', '#ef4444', false, true),
    ('Compassionate Leave', 'CL', '#8b5cf6', true, false),
    ('Bank Holiday Lieu', 'BHL', '#10b981', true, false),
    ('Unpaid Leave', 'UL', '#f59e0b', true, false)
ON CONFLICT DO NOTHING;

INSERT INTO shift_patterns (name, code, type, working_days, start_time, end_time, hours_per_week) VALUES
    ('Standard Mon-Fri', 'STD', 'standard', ARRAY[1,2,3,4,5], '09:00', '17:00', 40)
ON CONFLICT DO NOTHING;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_employees_email ON employees(user_email);
CREATE INDEX IF NOT EXISTS idx_employees_team ON employees(team_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(employee_email);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_leave_requests_dates ON leave_requests(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_email, is_read);
CREATE INDEX IF NOT EXISTS idx_activity_logs_employee ON activity_logs(employee_email);
