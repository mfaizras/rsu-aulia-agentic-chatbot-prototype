# Deployment RSU Aulia

Deployment menggunakan dua stack terpisah:

- `reverse-proxy/compose.yaml`: satu Traefik global untuk seluruh domain di VPS, HTTPS Let's Encrypt, dan routing aplikasi non-Docker.
- `compose.yaml`: PostgreSQL + pgvector, web service RSU Aulia, dan Telegram agent.

Repo aplikasi `rsu-aulia-agentic` dan `rsu-aulia-web-service` dikelola sebagai **git submodule**.

Hanya Traefik yang membuka port publik `80/443`. Gunicorn dan PostgreSQL hanya tersedia melalui jaringan internal Docker.

### Akses lokal tanpa Traefik

Service `web` juga memublikasikan port ke host (`localhost:5000`, bisa diubah lewat `WEB_PORT` di `.env`), sehingga stack bisa dijalankan dan diuji hanya di satu mesin tanpa reverse proxy:

```bash
cp .env.example .env   # isi minimal DOMAIN, OPENAI_API_KEY, TELEGRAM_BOT_TOKEN
docker compose up -d --build
```

Akses di browser: <http://localhost:5000>. Jika Traefik ikut dijalankan, domain tetap dilayani di port 80/443 dan tidak bertabrakan karena keduanya berbagi network `proxy`.

## Instalasi cepat

### Linux / server VPS

```bash
git clone --recurse-submodules https://github.com/mfaizras/rsu-aulia-agentic-chatbot-prototype.git && cd rsu-aulia-agentic-chatbot-prototype

./install.sh
```

Instaler akan mengecek prasyarat, mengambil submodule, membuat file `.env` secara interaktif, lalu menjalankan reverse proxy dan stack aplikasi.

### Windows (Docker Desktop)

```bat
git clone --recurse-submodules https://github.com/mfaizras/rsu-aulia-agentic-chatbot-prototype.git && cd rsu-aulia-agentic-chatbot-prototype

install.bat
```

> Pastikan port `80/443` pada mesin tidak dipakai program lain sebelum menjalankan Traefik.

## Pembaruan submodule aplikasi

```bash
git submodule update --init --recursive   # jika clone tanpa --recurse-submodules
git submodule update --remote             # mengambil versi terbaru branch dari masing-masing repo
```

Untuk mengganti branch yang dilacak submodule:

```bash
git config -f .gitmodules submodule.rsu-aulia-agentic.branch main
git config -f .gitmodules submodule.rsu-aulia-web-service.branch main
git submodule update --remote
```

## 1. Menjalankan reverse proxy global

Reverse proxy cukup disiapkan sekali untuk satu VPS:

```bash
cd reverse-proxy
cp .env.example .env
```

Isi alamat email Let's Encrypt pada `reverse-proxy/.env`, lalu jalankan:

```bash
docker compose up -d
docker compose ps
cd ..
```

Stack ini otomatis membuat shared Docker network bernama `proxy`. Port `80` dan `443` VPS harus bebas dan terbuka pada firewall.

## 2. Menjalankan aplikasi RSU Aulia

```bash
cp .env.example .env
```

Isi minimal nilai berikut dalam `.env`:

- `DOMAIN`, tanpa `http://` atau `https://`;
- `POSTGRES_PASSWORD` dan `SECRET_KEY`;
- `OPENAI_API_KEY` dan `TELEGRAM_BOT_TOKEN`.

Pastikan DNS record `A`/`AAAA` untuk `DOMAIN` sudah mengarah ke VPS. Jalankan aplikasi dengan satu perintah:

```bash
docker compose up -d --build
```

Traefik mendeteksi label service `web`, meneruskan domain ke Gunicorn port `5000`, mengalihkan HTTP ke HTTPS, dan mengelola sertifikat Let's Encrypt secara otomatis.

## Aplikasi non-Docker

Contoh routing tersedia di `reverse-proxy/dynamic/app-native.yaml.disabled`.

1. Sesuaikan domain dan port upstream.
2. Pastikan aplikasi native dapat dijangkau dari jaringan Docker melalui `host.docker.internal`.
3. Ubah nama file menjadi `app-native.yaml`; Traefik akan memuatnya otomatis.
4. Jangan buka port aplikasi native ke internet; hanya port `80/443` yang perlu publik.

## Perintah operasional

```bash
# Status aplikasi
docker compose ps

# Log aplikasi
docker compose logs -f

# Log reverse proxy
docker compose -f reverse-proxy/compose.yaml logs -f

# Membuat admin pertama
docker compose exec web python scripts/create_admin.py admin ganti-password-ini

# Mengimpor data informasi sekali jika diperlukan
docker compose exec web python scripts/add_data.py

# Menghentikan aplikasi tanpa menghentikan proxy global
docker compose down
```

Jangan menjalankan `docker compose down` pada folder `reverse-proxy` ketika domain aplikasi lain masih menggunakan Traefik.
