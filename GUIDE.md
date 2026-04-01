# 🛵 Vespa Catalog — Panduan Deployment 5 Langkah

> **Untuk siapa?** Developer yang baru belajar DevSecOps dan ingin memahami
> bagaimana frontend, backend, database, dan cloud terhubung satu sama lain.

---

## Gambaran Arsitektur

```
[Browser]  ──→  [Nginx / EC2]  ──→  [Node.js / Express]  ──→  [PostgreSQL / RDS]
                index.html           server.js                   tabel: users
                     ↑
               [Gambar Vespa]
               [AWS S3 Bucket]
```

**Alur request login:**
1. User klik "Login" di browser → `fetch POST /login` ke Express
2. Express cari email di RDS → `bcrypt.compare(password, hash)`
3. Jika cocok → response `{ name, email }` kembali ke browser

---

## Langkah 1 — Setup AWS S3 (Penyimpanan Gambar)

S3 adalah tempat kita menyimpan gambar Vespa agar bisa diakses publik via URL.

### 1.1 Buat Bucket

1. Buka [AWS Console → S3](https://s3.console.aws.amazon.com/s3/)
2. Klik **Create bucket**
3. Isi konfigurasi:
   ```
   Bucket name : vespa-catalog-images-[nama-kamu]   ← harus unik global
   Region      : ap-southeast-1 (Singapore)
   ```
4. **Block Public Access** → uncheck `Block all public access`
   > ⚠️ Ini aman untuk gambar publik. Jangan lakukan ini untuk data sensitif!
5. Klik **Create bucket**

### 1.2 Tambah Bucket Policy

Tanpa policy ini, gambar tidak bisa diakses dari browser.

1. Masuk ke bucket → tab **Permissions** → **Bucket policy**
2. Paste JSON berikut (ganti `NAMA-BUCKET-KAMU`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::NAMA-BUCKET-KAMU/*"
    }
  ]
}
```

### 1.3 Upload Gambar

```bash
# Struktur folder di S3:
products/
  ├── primavera.jpg
  ├── sprint.jpg
  ├── gts300.jpg
  ├── lx125.jpg
  ├── 946.jpg
  └── elettrica.jpg
```

Upload via AWS Console (drag & drop) atau CLI:
```bash
aws s3 cp ./images/ s3://NAMA-BUCKET-KAMU/products/ --recursive
```

### 1.4 Update URL di index.html

Ganti semua `BUCKET_NAME` dan `REGION` di `index.html`:
```
Sebelum : https://BUCKET_NAME.s3.REGION.amazonaws.com/products/primavera.jpg
Sesudah : https://vespa-catalog-images-kamu.s3.ap-southeast-1.amazonaws.com/products/primavera.jpg
```

> **DevSecOps Note:** URL S3 itu publik — siapapun bisa akses gambar langsung.
> Untuk data sensitif (dokumen, KTP, dll), gunakan **Pre-signed URL** bukan public bucket.

---

## Langkah 2 — Setup AWS RDS PostgreSQL (Database)

RDS adalah database terkelola — AWS yang handle backup, patch, dan ketersediaannya.

### 2.1 Buat Database

1. Buka [AWS Console → RDS](https://console.aws.amazon.com/rds/)
2. Klik **Create database** → pilih **Standard create**
3. Konfigurasi:

```yaml
Engine               : PostgreSQL
Version              : 15.x (latest stable)
Template             : Free tier

DB instance identifier : vespa-catalog-db
Master username        : postgres
Master password        : [BUAT PASSWORD KUAT — min. 12 karakter]

Instance class         : db.t3.micro  (free tier)
Storage                : 20 GB gp2

Connectivity:
  Public access        : Yes  (untuk development dari laptop)
  VPC Security Group   : Buat baru → nama: vespa-rds-sg

Initial DB name        : vespa_catalog
Backup retention       : 7 days
```

4. Klik **Create database** (tunggu ±5 menit)

### 2.2 Inisialisasi Tabel

Setelah RDS aktif, copy **Endpoint** dari console RDS, lalu jalankan:

```bash
# Dari laptop kamu
psql -h ENDPOINT_RDS -U postgres -d vespa_catalog -f init.sql

# Contoh:
psql -h vespa-catalog-db.abc123.ap-southeast-1.rds.amazonaws.com \
     -U postgres -d vespa_catalog -f init.sql
```

Verifikasi tabel berhasil dibuat:
```sql
\d users       -- Lihat struktur tabel
SELECT * FROM users;  -- Harusnya kosong (belum ada user)
```

> **DevSecOps Note:** Di production, aktifkan **Encryption at rest** dan
> gunakan **IAM Database Authentication** agar tidak perlu simpan password sama sekali.

---

## Langkah 3 — Konfigurasi Security Groups (Firewall AWS)

Security Group adalah firewall virtual yang mengontrol siapa boleh masuk/keluar.

### 3.1 Security Group untuk RDS (`vespa-rds-sg`)

| Tipe | Protokol | Port | Source | Keterangan |
|------|----------|------|--------|------------|
| PostgreSQL | TCP | 5432 | IP Laptop kamu | Akses dari developer |
| PostgreSQL | TCP | 5432 | Security Group EC2 | Akses dari backend |

**Cara set:**
1. EC2 Console → **Security Groups** → pilih `vespa-rds-sg`
2. Tab **Inbound rules** → **Edit inbound rules**
3. Tambah rule sesuai tabel di atas

> ⚠️ **JANGAN** set source `0.0.0.0/0` untuk port 5432!
> Itu artinya database kamu bisa diakses siapapun di internet.

### 3.2 Security Group untuk EC2 (`vespa-app-sg`)

| Tipe | Protokol | Port | Source | Keterangan |
|------|----------|------|--------|------------|
| SSH | TCP | 22 | IP Laptop kamu | Untuk remote server |
| HTTP | TCP | 80 | 0.0.0.0/0 | Web publik |
| Custom TCP | TCP | 3000 | 0.0.0.0/0 | Node.js API |

> **DevSecOps Note:** Port 22 (SSH) hanya buka dari IP kamu sendiri.
> Jika IP kamu dinamis (berubah-ubah), pertimbangkan AWS Systems Manager Session Manager
> sebagai alternatif SSH yang lebih aman (tidak perlu port 22 sama sekali).

### 3.3 Kenapa ini penting?

```
Internet → EC2 (port 80, 3000) ✅ boleh
Internet → RDS (port 5432)     ❌ TIDAK boleh
EC2      → RDS (port 5432)     ✅ boleh (EC2 SG sebagai source)
```

---

## Langkah 4 — Setup GitHub Secrets (Untuk CI/CD)

GitHub Secrets adalah tempat menyimpan kredensial sensitif yang dipakai GitHub Actions.
Tersimpan terenkripsi dan tidak pernah muncul di log.

### 4.1 Secret yang Diperlukan

| Secret Name | Nilai | Cara Mendapatkan |
|-------------|-------|-----------------|
| `EC2_HOST` | IP publik EC2 | EC2 Console → instance → Public IPv4 |
| `EC2_USER` | `ubuntu` | Default untuk AMI Ubuntu |
| `EC2_SSH_KEY` | Isi file `.pem` | Paste seluruh isi file key pair kamu |

### 4.2 Cara Menambah Secret

1. Buka repo GitHub kamu
2. **Settings** → **Secrets and variables** → **Actions**
3. Klik **New repository secret**
4. Isi **Name** dan **Value** → **Add secret**

Untuk `EC2_SSH_KEY`:
```bash
# Tampilkan isi file .pem di terminal
cat my-ec2-key.pem
# Copy SEMUA outputnya termasuk baris -----BEGIN RSA PRIVATE KEY-----
```

### 4.3 Cara Kerja CI/CD Pipeline

```
Developer push ke branch main
        ↓
GitHub Actions aktif (deploy.yml)
        ↓
[Step 1] actions/checkout → ambil kode terbaru
        ↓
[Step 2] appleboy/scp-action → copy file ke EC2 via SCP
        ↓
[Step 3] appleboy/ssh-action → SSH ke EC2, jalankan commands:
          - Install Nginx (jika belum)
          - Copy index.html ke /var/www/html/
          - Restart Nginx
          - npm install & pm2 restart backend
```

> **DevSecOps Note:** Prinsip ini disebut **GitOps** — Git sebagai single source of truth.
> Setiap perubahan code otomatis terdeploy. Tidak ada deploy manual yang bisa lupa dicatat.

---

## Langkah 5 — Menjalankan Aplikasi

### 5.1 Setup di EC2 (Manual — Pertama Kali)

```bash
# SSH ke EC2
ssh -i my-ec2-key.pem ubuntu@IP_EC2_KAMU

# Clone repository
git clone https://github.com/USERNAME/vespa-catalog.git
cd vespa-catalog

# Copy dan isi .env
cp .env.example .env
nano .env
# Isi dengan nilai RDS kamu:
#   DB_HOST = endpoint RDS
#   DB_USER = postgres
#   DB_PASSWORD = password yang dibuat di langkah 2

# Install dependencies
npm install

# Jalankan backend (PM2 agar tetap hidup walau terminal ditutup)
npm install -g pm2
pm2 start server.js --name vespa-api
pm2 save
pm2 startup  # Auto-start setelah EC2 reboot
```

### 5.2 Verifikasi

```bash
# Cek backend berjalan
pm2 status
curl http://localhost:3000/health   # Harus return: {"status":"ok"}

# Cek Nginx berjalan
sudo systemctl status nginx
curl http://localhost/              # Harus return HTML halaman Vespa

# Test register dari CLI
curl -X POST http://localhost:3000/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@email.com","password":"password123"}'
# Response: {"message":"Akun berhasil dibuat."}

# Test login
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@email.com","password":"password123"}'
# Response: {"message":"Login berhasil.","name":"Test User","email":"test@email.com"}
```

### 5.3 Setelah Semua Selesai

Buka browser dan akses: `http://IP_EC2_KAMU`

Kamu akan melihat katalog Vespa dengan gambar dari S3, dan bisa mencoba
fitur Login / Daftar yang terhubung ke RDS.

---

## Troubleshooting Cepat

| Masalah | Kemungkinan Penyebab | Solusi |
|---------|---------------------|--------|
| Gambar tidak muncul | Bucket policy belum diset | Cek langkah 1.2 |
| `ECONNREFUSED` saat login | Backend tidak jalan | `pm2 status`, `pm2 logs vespa-api` |
| `connect ECONNREFUSED 5432` | Security Group RDS | Tambah IP EC2 ke inbound SG RDS |
| GitHub Actions gagal | Secret belum diset | Cek langkah 4.2 |
| `relation "users" does not exist` | init.sql belum dijalankan | Jalankan langkah 2.2 |

---

## Ringkasan Konsep DevSecOps yang Dipelajari

| Konsep | Implementasi di Project Ini |
|--------|-----------------------------|
| **Secrets Management** | `.env` file, tidak pernah di-commit ke Git |
| **Least Privilege** | Security Group RDS hanya terima dari EC2, bukan internet |
| **Password Hashing** | bcrypt di `server.js` — bukan MD5 atau plain text |
| **SQL Injection Prevention** | Parameterized query `$1, $2` di semua query |
| **CI/CD Automation** | GitHub Actions deploy otomatis saat push ke main |
| **Infrastructure as Code** | Deployment dikonfigurasi di `deploy.yml`, bukan manual |

---

*Dibuat untuk tujuan pembelajaran DevSecOps. Happy hacking! 🛵*
