-- ─────────────────────────────────────────────────────────────────────────────
-- init.sql — Inisialisasi Database Vespa Catalog
-- ─────────────────────────────────────────────────────────────────────────────
-- Cara pakai:
--   psql -h <RDS_ENDPOINT> -U postgres -d vespa_catalog -f init.sql
-- ─────────────────────────────────────────────────────────────────────────────

-- Aktifkan ekstensi pgcrypto (opsional, untuk gen_random_uuid jika dibutuhkan)
-- CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── TABEL USERS ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id            SERIAL        PRIMARY KEY,
  name          VARCHAR(100)  NOT NULL,
  email         VARCHAR(255)  NOT NULL UNIQUE,  -- UNIQUE mencegah duplikat email
  password_hash VARCHAR(255)  NOT NULL,          -- Selalu simpan hash, BUKAN plain text!
  created_at    TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- Komentar kolom untuk dokumentasi
COMMENT ON COLUMN users.password_hash IS 'bcrypt hash. JANGAN simpan plain text password di sini.';
COMMENT ON COLUMN users.email IS 'Email unik per user, digunakan sebagai username login.';

-- Index pada email mempercepat query WHERE email = $1 saat login
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

-- ─────────────────────────────────────────────────────────────────────────────
-- Catatan DevSecOps:
--
--   1. password_hash — Kolom ini berisi output bcrypt, bukan password asli.
--      Jika database bocor (data breach), attacker tetap tidak bisa login
--      karena mereka butuh waktu jutaan tahun untuk crack bcrypt (cost 10).
--
--   2. UNIQUE constraint pada email — Ini enforce di level database,
--      lapisan pertahanan kedua setelah validasi di aplikasi.
--
--   3. TIMESTAMP DEFAULT NOW() — Memudahkan audit kapan akun dibuat.
--      Sangat berguna untuk investigasi insiden keamanan.
-- ─────────────────────────────────────────────────────────────────────────────
