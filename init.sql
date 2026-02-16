-- Initial setup for test database
-- This file runs automatically when the container is first created

-- Create a non-deterministic case+accent insensitive collation (level1 = base characters only)
-- This must be created on template1 so all databases inherit it
-- Create on template1 so future databases inherit it
\c template1
CREATE COLLATION IF NOT EXISTS ci (provider = icu, locale = 'und-u-ks-level1', deterministic = false);

-- Create on the current database (already created before init scripts run)
\c test
CREATE COLLATION IF NOT EXISTS ci (provider = icu, locale = 'und-u-ks-level1', deterministic = false);

-- Create extensions if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create clients table
CREATE TABLE clients (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) COLLATE ci NOT NULL,
    email VARCHAR(255) COLLATE ci,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_clients_name ON clients (name);

-- Seed clients data
\i /docker-entrypoint-initdb.d/seed_clients.data

-- Log successful initialization
SELECT 'test database initialized successfully' as status;
