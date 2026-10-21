# Подключает скиллы и правила из этого репо в ~/.claude через junction:
# правки в репо сразу видны Claude Code, копировать ничего не нужно.
param(
    # Рабочая папка для очередей /conveyor; по умолчанию – рядом с репо.
    [string]$WorkDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "claude-config-work")
)

$ErrorActionPreference = "Stop"
$claudeDir = Join-Path $HOME ".claude"

function Connect-Junction([string]$link, [string]$target, [string]$label) {
    if (Test-Path $link) {
        $existing = Get-Item $link -Force
        if ($existing.LinkType -eq "Junction" -and $existing.Target -contains $target) {
            Write-Host "уже подключен: $label"
            return
        }
        # Чужую папку с тем же именем не трогаем – пусть решает человек.
        Write-Warning "пропущен ${label}: $link уже существует и не ссылается сюда"
        return
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Host "подключен: $label -> $target"
}

# Скиллы – папки, поэтому каждый подключается отдельно и не мешает скиллам из других мест.
$skillsDir = Join-Path $claudeDir "skills"
New-Item -ItemType Directory -Force $skillsDir | Out-Null
foreach ($skill in Get-ChildItem (Join-Path $PSScriptRoot "skills") -Directory) {
    Connect-Junction (Join-Path $skillsDir $skill.Name) $skill.FullName "skills/$($skill.Name)"
}

# Правила – файлы, а junction бывает только на папку: подключается вся папка rules целиком.
# Hard link на файл не годится: git при обновлении пересоздает файл, и ссылка отрывается.
Connect-Junction (Join-Path $claudeDir "rules") (Join-Path $PSScriptRoot "rules") "rules"

New-Item -ItemType Directory -Force $WorkDir | Out-Null
$WorkDir = (Resolve-Path $WorkDir).Path
[Environment]::SetEnvironmentVariable("CONVEYOR_WORK_DIR", $WorkDir, "User")
Write-Host "CONVEYOR_WORK_DIR = $WorkDir (переменная пользователя; перезапустите Claude Code, чтобы он ее увидел)"
