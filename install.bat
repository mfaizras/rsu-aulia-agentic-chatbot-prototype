@echo off
REM ===========================================================================
REM  Instaler RSU Aulia - Deployment Stack (Windows / Docker Desktop)
REM ===========================================================================
REM  Stack:
REM    - reverse-proxy\ : Traefik global (HTTPS Let's Encrypt, port 80/443)
REM    - compose.yaml   : PostgreSQL+pgvector, web service, Telegram agent
REM  Repo aplikasi (submodule git):
REM    - rsu-aulia-agentic
REM    - rsu-aulia-web-service
REM ===========================================================================
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "GREEN=[92m"
set "CYAN=[96m"
set "YELLOW=[93m"
set "RED=[91m"
set "RESET=[0m"

echo.
echo  ======================================================
echo   Instaler RSU Aulia - Deployment Stack
echo  ======================================================
echo.

REM ---------------------------------------------------------------------------
REM 1. Cek prasyarat
REM ---------------------------------------------------------------------------
echo %CYAN%[INFO]%RESET% Memeriksa prasyarat...

where docker >nul 2>nul
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Docker tidak ditemukan. Install Docker Desktop.
  echo   https://www.docker.com/products/docker-desktop/
  exit /b 1
)
where git >nul 2>nul
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Git tidak ditemukan. Install Git.
  echo   https://git-scm.com/download/win
  exit /b 1
)
docker compose version >nul 2>nul
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Docker Compose v2 tidak ditemukan. Perbarui Docker Desktop.
  exit /b 1
)
docker info >nul 2>nul
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Docker Desktop tidak berjalan. Jalankan Docker Desktop dahulu.
  exit /b 1
)

set "DOCKER_VER="
for /f "tokens=3" %%v in ('docker --version') do set "DOCKER_VER=%%v"
set "COMPOSE_VER="
for /f "delims=" %%v in ('docker compose version') do set "COMPOSE_VER=%%v"
echo %GREEN%[OK]%RESET% Docker !DOCKER_VER! - !COMPOSE_VER!

REM ---------------------------------------------------------------------------
REM 2. Submodule aplikasi
REM ---------------------------------------------------------------------------
if /i "%SKIP_SUBMODULES%"=="1" goto :sub_done
if exist "rsu-aulia-agentic\.git" if exist "rsu-aulia-web-service\.git" goto :sub_update

echo %CYAN%[INFO]%RESET% Menginisialisasi submodule aplikasi rsu-aulia-agentic + rsu-aulia-web-service...
git submodule update --init --recursive
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Gagal mengambil submodule. Periksa koneksi internet.
  exit /b 1
)
goto :sub_done

:sub_update
echo %CYAN%[INFO]%RESET% Memperbarui submodule aplikasi...
git submodule update --init --recursive

:sub_done
echo %GREEN%[OK]%RESET% Submodule aplikasi siap.

REM ---------------------------------------------------------------------------
REM 3. Membuat / melengkapi file .env
REM ---------------------------------------------------------------------------
if not exist ".env" (
  echo %YELLOW%[WARN]%RESET% .env belum ada, membuat dari .env.example...
  copy /y ".env.example" ".env" >nul
)
if not exist "reverse-proxy\.env" (
  echo %YELLOW%[WARN]%RESET% reverse-proxy\.env belum ada, membuat dari .env.example...
  copy /y "reverse-proxy\.env.example" "reverse-proxy\.env" >nul
)

REM Generate random string via PowerShell (32 hex chars)
for /f %%p in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')"') do set "RAND_PW=%%p"

set "DEFAULT_DOMAIN=contoh.domain.com"
for /f "tokens=1,* delims==" %%a in ('findstr /b "DOMAIN=" .env') do if "%%a"=="DOMAIN" set "DEFAULT_DOMAIN=%%b"
if not defined DEFAULT_DOMAIN set "DEFAULT_DOMAIN=contoh.domain.com"

set "WEB_PORT=5000"
for /f "tokens=1,* delims==" %%a in ('findstr /b "WEB_PORT=" .env') do if "%%a"=="WEB_PORT" set "WEB_PORT=%%b"
if not defined WEB_PORT set "WEB_PORT=5000"

echo.
echo %CYAN%[INFO]%RESET% Konfigurasi aplikasi .env:
set /p "DOMAIN=Domain tanpa http/https [%DEFAULT_DOMAIN%]: "
if "%DOMAIN%"=="" set "DOMAIN=%DEFAULT_DOMAIN%"

set "POSTGRES_PASSWORD="
set "SECRET_KEY="
set "OPENAI_API_KEY="
set "TELEGRAM_BOT_TOKEN="

set /p "USE_RANDOM=Gunakan password database acak? [Y/n]: "
if /i "%USE_RANDOM%"=="Y" set "PW_SET=1"
if /i "%USE_RANDOM%"=="" set "PW_SET=1"
if not defined PW_SET set /p "POSTGRES_PASSWORD=Password database PostgreSQL: "
if not defined POSTGRES_PASSWORD set "POSTGRES_PASSWORD=%RAND_PW%"
set /p "SECRET_KEY=Secret key aplikasi, kosong = acak: "
if not defined SECRET_KEY set "SECRET_KEY=%RAND_PW%"
set /p "OPENAI_API_KEY=OpenAI API Key: "
set /p "TELEGRAM_BOT_TOKEN=Telegram bot token: "

REM Tulis ke .env lewat PowerShell (nilai dikirim sebagai env var)
powershell -NoProfile -Command ^
  "$c = Get-Content '.env'; foreach($e in @('DOMAIN','POSTGRES_PASSWORD','SECRET_KEY','OPENAI_API_KEY','TELEGRAM_BOT_TOKEN')){ $c = $c | Where-Object { $_ -notmatch ('^'+$e+'=') } }; $c += 'DOMAIN='+$env:DOMAIN; $c += 'POSTGRES_PASSWORD='+$env:POSTGRES_PASSWORD; $c += 'SECRET_KEY='+$env:SECRET_KEY; $c += 'OPENAI_API_KEY='+$env:OPENAI_API_KEY; $c += 'TELEGRAM_BOT_TOKEN='+$env:TELEGRAM_BOT_TOKEN; Set-Content '.env' $c"
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Gagal menulis .env.
  exit /b 1
)
echo %GREEN%[OK]%RESET% File .env siap.

set "DEFAULT_ACME=admin@domain-anda.com"
for /f "tokens=1,* delims==" %%a in ('findstr /b "ACME_EMAIL=" reverse-proxy\.env') do if "%%a"=="ACME_EMAIL" set "DEFAULT_ACME=%%b"
if not defined DEFAULT_ACME set "DEFAULT_ACME=admin@domain-anda.com"

echo.
echo %CYAN%[INFO]%RESET% Konfigurasi reverse proxy reverse-proxy\.env:
set /p "ACME_EMAIL=Email Let's Encrypt [%DEFAULT_ACME%]: "
if "%ACME_EMAIL%"=="" set "ACME_EMAIL=%DEFAULT_ACME%"
powershell -NoProfile -Command "$c = Get-Content 'reverse-proxy\.env' | Where-Object { $_ -notmatch '^ACME_EMAIL=' }; $c += 'ACME_EMAIL='+$env:ACME_EMAIL; Set-Content 'reverse-proxy\.env' $c"
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Gagal menulis reverse-proxy\.env.
  exit /b 1
)
echo %GREEN%[OK]%RESET% File reverse-proxy\.env siap.

REM ---------------------------------------------------------------------------
REM 4. Jaringan proxy, dibuat otomatis oleh stack Traefik
REM ---------------------------------------------------------------------------
docker network inspect proxy >nul 2>nul
if errorlevel 1 (
  echo %CYAN%[INFO]%RESET% Shared network 'proxy' akan dibuat oleh stack Traefik.
) else (
  echo %GREEN%[OK]%RESET% Shared network 'proxy' sudah ada.
)

REM ---------------------------------------------------------------------------
REM 5. Menjalankan stack
REM ---------------------------------------------------------------------------
echo %CYAN%[INFO]%RESET% Menjalankan reverse proxy Traefik...
docker compose -f reverse-proxy\compose.yaml up -d
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Gagal menjalankan reverse proxy.
  exit /b 1
)

echo %CYAN%[INFO]%RESET% Menjalankan stack aplikasi database + web + agent...
docker compose up -d --build
if errorlevel 1 (
  echo %RED%[ERROR]%RESET% Gagal menjalankan stack aplikasi.
  exit /b 1
)

echo %CYAN%[INFO]%RESET% Menunggu service siap, maks 120 detik...
for /L %%i in (1,1,24) do (
  timeout /t 5 /nobreak >nul
  docker compose ps --format "{{.Service}}={{.Health}}" > "%TEMP%\rsu-ps.txt" 2>nul
  set "UNHEALTHY="
  for /f "delims=" %%l in ('type "%TEMP%\rsu-ps.txt"') do (
    echo %%l | findstr /v "healthy" >nul && set "UNHEALTHY=1"
  )
  if not defined UNHEALTHY goto :healthy
)
:healthy

echo.
docker compose ps

REM ---------------------------------------------------------------------------
REM 6. Membuat admin pertama
REM ---------------------------------------------------------------------------
if not exist "rsu-aulia-web-service\scripts\create_admin.py" goto :done
echo.
echo %CYAN%[INFO]%RESET% Membuat user admin web service.
set "ADMIN_USER=admin"
set /p "ADMIN_USER=Username admin [%ADMIN_USER%]: "
if "%ADMIN_USER%"=="" set "ADMIN_USER=admin"
set /p "ADMIN_PASS=Password admin, min 8 karakter: "
docker compose exec -T web python scripts\create_admin.py "%ADMIN_USER%" "%ADMIN_PASS%"
if errorlevel 1 (
  echo %YELLOW%[WARN]%RESET% Gagal membuat admin. Buat manual:
  echo   docker compose exec web python scripts\create_admin.py ^<user^> ^<pass^>
  goto :done
)
echo %GREEN%[OK]%RESET% Admin %ADMIN_USER% dibuat.

:done
echo.
echo %GREEN%[OK]%RESET% ======================================================
echo %GREEN%[OK]%RESET%  Instalasi selesai!
echo %GREEN%[OK]%RESET%  Domain          : https://%DOMAIN%
echo %GREEN%[OK]%RESET%  Akses lokal     : http://localhost:%WEB_PORT%
echo %GREEN%[OK]%RESET% ======================================================
echo %CYAN%[INFO]%RESET% Perintah berguna:
echo   docker compose ps
echo   docker compose logs -f
echo   docker compose -f reverse-proxy\compose.yaml ps
echo   docker compose exec web python scripts\add_data.py

endlocal
exit /b 0
