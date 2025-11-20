-- =====================================================
-- CUSTOM USER DATABASE SCHEMA AND TEST DATA
-- =====================================================
--
-- Purpose:
--   Defines the database schema for the custom user storage system
--   and populates it with test data for demonstration purposes.
--
-- Database: PostgreSQL 15+
-- Table: utenti (users)
--
-- Security Note:
--   This schema uses MD5 password hashing for demonstration purposes ONLY.
--   MD5 is cryptographically broken and must NOT be used in production.
--   Production systems should use bcrypt, scrypt, or Argon2.
--
-- Usage:
--   This script is automatically executed when the user-db PostgreSQL
--   container initializes for the first time.
-- =====================================================

-- -----------------------------------------------------
-- TABLE: utenti (Users Table)
-- -----------------------------------------------------
-- Stores user account information for authentication via
-- the Custom User Storage Provider SPI.
--
-- Schema Design:
--   - id: Auto-incrementing primary key
--   - nome: User's first name
--   - cognome: User's last name
--   - mail: Email address (unique constraint enforced)
--   - username: Login username (unique constraint enforced)
--   - password: MD5 hash of the user's password (32 characters)
--
-- Constraints:
--   - PRIMARY KEY on id
--   - UNIQUE constraint on mail (prevents duplicate email addresses)
--   - UNIQUE constraint on username (prevents duplicate usernames)
--   - NOT NULL on all fields (all user data is required)
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS utenti (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    cognome VARCHAR(50) NOT NULL,
    mail VARCHAR(100) NOT NULL UNIQUE,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(32) NOT NULL  -- MD5 hash (exactly 32 hexadecimal characters)
);

-- -----------------------------------------------------
-- TEST DATA: Sample User Accounts
-- -----------------------------------------------------
-- Inserts fictitious user accounts for testing the authentication flow.
--
-- Password Hashing:
--   The MD5() function is used to hash passwords at insertion time.
--   In this demo setup, usernames are used as passwords for simplicity.
--
-- Test Credentials:
--   username: mrossi,    password: mrossi
--   username: lverdi,    password: lverdi
--   username: abianchi,  password: abianchi
--   username: gneri,     password: gneri
--   username: mferrari,  password: mferrari
--   username: sromano,   password: sromano
--   username: aricci,    password: aricci
--   username: emarino,   password: emarino
--   username: dgreco,    password: dgreco
--   username: fbruno,    password: fbruno
-- -----------------------------------------------------
INSERT INTO utenti (nome, cognome, mail, username, password) VALUES
('Mario', 'Rossi', 'mario.rossi@email.com', 'mrossi', MD5('mrossi')),
('Luigi', 'Verdi', 'luigi.verdi@email.com', 'lverdi', MD5('lverdi')),
('Anna', 'Bianchi', 'anna.bianchi@email.com', 'abianchi', MD5('abianchi')),
('Giulia', 'Neri', 'giulia.neri@email.com', 'gneri', MD5('gneri')),
('Marco', 'Ferrari', 'marco.ferrari@email.com', 'mferrari', MD5('mferrari')),
('Sara', 'Romano', 'sara.romano@email.com', 'sromano', MD5('sromano')),
('Andrea', 'Ricci', 'andrea.ricci@email.com', 'aricci', MD5('aricci')),
('Elena', 'Marino', 'elena.marino@email.com', 'emarino', MD5('emarino')),
('Davide', 'Greco', 'davide.greco@email.com', 'dgreco', MD5('dgreco')),
('Francesca', 'Bruno', 'francesca.bruno@email.com', 'fbruno', MD5('fbruno'));

-- -----------------------------------------------------
-- ADDITIONAL TEST USER
-- -----------------------------------------------------
-- Special test user with a more complex password for
-- integration testing scenarios.
--
-- Test Credentials:
--   username: testuser
--   password: testuser1!
-- -----------------------------------------------------
INSERT INTO utenti (nome, cognome, mail, username, password) VALUES
('Test', 'User', 'test@example.com', 'testuser', MD5('testuser1!'));

-- -----------------------------------------------------
-- VERIFICATION QUERY (Optional)
-- -----------------------------------------------------
-- Uncomment the query below to verify that all users
-- have been inserted correctly with their MD5 password hashes.
-- -----------------------------------------------------
-- SELECT id, nome, cognome, mail, username, password FROM utenti;
