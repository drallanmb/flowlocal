<#
.SYNOPSIS
  Instala os motores locais de que o FlowLocal precisa no Windows:
  whisper.cpp (whisper-server.exe + modelo de voz) e, opcionalmente, o Ollama com um modelo de polimento.

.EXAMPLE
  .\setup.ps1                 # detecta a GPU NVIDIA sozinho
  .\setup.ps1 -Gpu cpu        # força a versão para CPU
  .\setup.ps1 -SkipOllama     # só a transcrição, sem polimento por LLM
#>
param(
    [ValidateSet('auto', 'cuda', 'cpu')] [string]$Gpu = 'auto',
    [string]$WhisperModel = 'ggml-large-v3-turbo-q5_0.bin',
    [string]$OllamaModel = 'qwen2.5:3b-instruct',
    [switch]$SkipOllama
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest é muito mais rápido sem a barra de progresso
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$whisperDir = Join-Path $env:LOCALAPPDATA 'FlowLocal\whisper'
$modelDir = Join-Path $env:APPDATA 'FlowLocal\models'
New-Item -ItemType Directory -Force $whisperDir, $modelDir | Out-Null

function Step($message) { Write-Host "==> $message" -ForegroundColor Cyan }

# --- 0. Runtime do Visual C++ (os binários do whisper.cpp dependem dele) -----------------------------------------
if (-not (Test-Path "$env:SystemRoot\System32\vcruntime140_1.dll")) {
    Step 'Instalando o Visual C++ Redistributable'
    winget install -e --id Microsoft.VCRedist.2015+.x64 --accept-package-agreements --accept-source-agreements
}

# --- 1. whisper.cpp ----------------------------------------------------------------------------------------------
Step 'Procurando a versão mais recente do whisper.cpp com binários para Windows'
$releases = Invoke-RestMethod 'https://api.github.com/repos/ggml-org/whisper.cpp/releases?per_page=30' -Headers @{ 'User-Agent' = 'FlowLocal-setup' }

$hasNvidia = [bool](Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' })
$useCuda = ($Gpu -eq 'cuda') -or ($Gpu -eq 'auto' -and $hasNvidia)

function Find-Asset([string[]]$patterns) {
    foreach ($release in $releases) {          # as versões vêm da mais nova para a mais antiga
        foreach ($pattern in $patterns) {
            $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
            if ($asset) { return $asset }
        }
    }
    return $null
}

$asset = $null
if ($useCuda) {
    # O nome do arquivo mudou entre versões: aceita os dois formatos (CUDA 12.4 exige driver NVIDIA recente).
    $asset = Find-Asset @('^whisper-bin-win-cuda-12\.4\.0-x64\.zip$', '^whisper-cublas-12\.4\.0-bin-x64\.zip$')
    if (-not $asset) { Write-Warning 'Binário CUDA não encontrado; usando a versão para CPU.'; $useCuda = $false }
}
if (-not $asset) { $asset = Find-Asset @('^whisper-bin-x64\.zip$') }
if (-not $asset) { throw 'Não encontrei um binário do whisper.cpp para Windows nas versões recentes. Baixe manualmente em https://github.com/ggml-org/whisper.cpp/releases' }

Step ("Baixando {0} ({1:N0} MB){2}" -f $asset.name, ($asset.size / 1MB), $(if ($useCuda) { ' [GPU NVIDIA/CUDA]' } else { ' [CPU]' }))
$zip = Join-Path $env:TEMP $asset.name
Invoke-WebRequest $asset.browser_download_url -OutFile $zip -Headers @{ 'User-Agent' = 'FlowLocal-setup' }

if (Test-Path $whisperDir) { Remove-Item $whisperDir -Recurse -Force }
New-Item -ItemType Directory -Force $whisperDir | Out-Null
Expand-Archive $zip -DestinationPath $whisperDir -Force
Remove-Item $zip -Force

$server = Get-ChildItem $whisperDir -Recurse -Filter 'whisper-server.exe' | Select-Object -First 1
if (-not $server) { throw "whisper-server.exe não veio dentro de $($asset.name). Informe o caminho em FlowLocal > Configurações." }
Write-Host "    whisper-server: $($server.FullName)"

# --- 2. Modelo de voz --------------------------------------------------------------------------------------------
$modelPath = Join-Path $modelDir $WhisperModel
if (Test-Path $modelPath) {
    Step "Modelo já existe: $modelPath"
} else {
    Step "Baixando o modelo $WhisperModel (cerca de 570 MB para o large-v3-turbo-q5_0)"
    # curl.exe vem com o Windows 10+ e mostra o progresso do download.
    & curl.exe -L --fail -o "$modelPath.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WhisperModel"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao baixar o modelo.' }
    Move-Item "$modelPath.part" $modelPath
}

# --- 3. Ollama (polimento por LLM e modo comando) ----------------------------------------------------------------
if (-not $SkipOllama) {
    $ollama = (Get-Command ollama -ErrorAction SilentlyContinue).Source
    if (-not $ollama) { $ollama = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe' }
    if (-not (Test-Path $ollama)) {
        Step 'Instalando o Ollama'
        winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements
        $ollama = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    }
    if (Test-Path $ollama) {
        Step "Baixando o modelo $OllamaModel no Ollama (cerca de 1,9 GB)"
        & $ollama pull $OllamaModel
    } else {
        Write-Warning 'Ollama instalado, mas ollama.exe não foi encontrado. Abra um novo terminal e rode: ollama pull ' + $OllamaModel
    }
}

Write-Host ''
Write-Host 'Pronto! Abra o FlowLocal; o Hub mostra o que ainda faltar.' -ForegroundColor Green
