@echo off
setlocal enabledelayedexpansion

:: All status output goes to stderr (>&2) so stdout stays clean for MCP JSON-RPC

:: 1. Ensure Docker Desktop is running
docker info >nul 2>&1
if NOT ERRORLEVEL 1 goto compose_up

echo [claude-context] Docker not running -- launching Docker Desktop... >&2
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"

set /a attempts=0
:wait_docker
timeout /t 3 /nobreak >nul
docker info >nul 2>&1
if NOT ERRORLEVEL 1 goto docker_ready
set /a attempts+=1
if %attempts% LSS 20 goto wait_docker
echo [claude-context] ERROR: Docker Desktop did not start in time. >&2
exit /b 1

:docker_ready
echo [claude-context] Docker is ready. >&2

:: 2. Start Milvus stack (etcd + minio + milvus) if not already running
:compose_up
docker compose -f "C:\Fran\claude-context\docker-compose.yml" up -d >nul 2>&1
if ERRORLEVEL 1 (
    docker-compose -f "C:\Fran\claude-context\docker-compose.yml" up -d >nul 2>&1
    if ERRORLEVEL 1 (
        echo [claude-context] ERROR: docker compose up failed. >&2
        exit /b 1
    )
)

:: 3. Wait until Milvus health endpoint returns 200
echo [claude-context] Waiting for Milvus to be ready... >&2
:wait_milvus
powershell -Command "try { $r = Invoke-WebRequest -Uri http://127.0.0.1:9091/healthz -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop; if ($r.StatusCode -eq 200) { exit 0 } } catch { }; exit 1" >nul 2>&1
if ERRORLEVEL 1 (
    timeout /t 2 /nobreak >nul
    goto wait_milvus
)
echo [claude-context] Milvus is ready. >&2

:: 4. Set env vars — force correct values regardless of inherited environment
set MILVUS_ADDRESS=127.0.0.1:19530
set EMBEDDING_PROVIDER=Ollama
set OLLAMA_MODEL=unclemusclez/jina-embeddings-v2-base-code
set OLLAMA_HOST=http://127.0.0.1:11434
echo [claude-context] Using model: %OLLAMA_MODEL% >&2

:: 5. Start the MCP server (stdout/stdin passed through cleanly for JSON-RPC)
npx -y @zilliz/claude-context-mcp@latest
