$ErrorActionPreference = "Stop"

$envFile = Join-Path $PSScriptRoot "..\.env"
$alertmanagerDir = Join-Path $PSScriptRoot "..\config\alertmanager"
$templatePath = Join-Path $alertmanagerDir "alertmanager.yml"
$localConfigPath = Join-Path $alertmanagerDir "alertmanager.local.yml"
$tokenPath = Join-Path $alertmanagerDir "telegram_bot_token"

if (-not (Test-Path $envFile)) {
    throw "Missing .env. Copy .env.example to .env and configure Telegram first."
}

$lines = Get-Content $envFile
$token = (($lines | Where-Object { $_ -match "^TELEGRAM_BOT_TOKEN=" }) -replace "^TELEGRAM_BOT_TOKEN=", "").Trim()
$chatId = (($lines | Where-Object { $_ -match "^TELEGRAM_CHAT_ID=" }) -replace "^TELEGRAM_CHAT_ID=", "").Trim()

if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId) -or $chatId -eq "0") {
    throw "TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be configured in .env."
}

$template = Get-Content $templatePath -Raw
$localConfig = $template -replace "chat_id: 0", ("chat_id: " + $chatId)

Set-Content -Path $tokenPath -Value $token -NoNewline
Set-Content -Path $localConfigPath -Value $localConfig -NoNewline

Write-Output "Generated ignored Alertmanager runtime files."
