# Подключает скиллы и агентов из этого репо в ~/.claude через junction:
# правки в репо сразу видны Claude Code, копировать ничего не нужно.
param(
    # Рабочая папка для очередей /conveyor; по умолчанию – рядом с репо.
    [string]$WorkDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "claude-skills-work")
)

$ErrorActionPreference = "Stop"
$claudeDir = Join-Path $HOME ".claude"

foreach ($kind in "skills", "agents") {
    $source = Join-Path $PSScriptRoot $kind
    if (-not (Test-Path $source)) { continue }
    $target = Join-Path $claudeDir $kind
    New-Item -ItemType Directory -Force $target | Out-Null

    foreach ($item in Get-ChildItem $source) {
        $link = Join-Path $target $item.Name
        if (Test-Path $link) {
            $existing = Get-Item $link -Force
            if ($existing.LinkType -eq "Junction" -and $existing.Target -contains $item.FullName) {
                Write-Host "уже подключен: $kind/$($item.Name)"
                continue
            }
            # Чужую папку или файл с тем же именем не трогаем – пусть решает человек.
            Write-Warning "пропущен $kind/$($item.Name): $link уже существует и не ссылается сюда"
            continue
        }
        if ($item.PSIsContainer) {
            New-Item -ItemType Junction -Path $link -Target $item.FullName | Out-Null
        } else {
            # Агенты – одиночные .md-файлы, junction для файла невозможен; hard link не требует прав администратора.
            New-Item -ItemType HardLink -Path $link -Target $item.FullName | Out-Null
        }
        Write-Host "подключен: $kind/$($item.Name) -> $($item.FullName)"
    }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
$WorkDir = (Resolve-Path $WorkDir).Path
[Environment]::SetEnvironmentVariable("CONVEYOR_WORK_DIR", $WorkDir, "User")
Write-Host "CONVEYOR_WORK_DIR = $WorkDir (переменная пользователя; перезапустите Claude Code, чтобы он ее увидел)"
