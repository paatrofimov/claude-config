# PreToolUse-хук для Bash и PowerShell: перед git commit ищет в добавленных строках индекса кракозябры –
# UTF-8 кириллицу, прочитанную как cp1251 ("РЎРµ") или latin-1 ("Ð¡Ðµ"). Нашел – exit 2, коммит не идет.
# Репозиторий – из первого `cd <путь>` в команде: shell агента стартует в основном checkout, а коммитит в worktree.
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$command = [string]$payload.tool_input.command
if ($command -notmatch 'git\b[^;&|]*\bcommit\b') { exit 0 }

$repo = [string]$payload.cwd
if ($command -match '(?:^|[;&]\s*)cd\s+(?:/d\s+)?["'']?([^"'';&|]+?)["'']?\s*(?:;|&&|$)') { $repo = $Matches[1].Trim() }
if ($repo -match '^/([a-z])/(.*)$') { $repo = "$($Matches[1]):/$($Matches[2])" }
if (-not (Test-Path $repo)) { exit 0 }

$pattern = '(?:[РС][\u0080-¿Ѐ-џ‐-›]){3,}|(?:[ÐÑ][\u0080-¿]){2,}'
$hits = git -C $repo -c core.quotepath=false diff --cached --no-color -U0 |
	Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') -and $_ -cmatch $pattern } |
	Select-Object -First 5
if (-not $hits) { exit 0 }

[Console]::Error.WriteLine("В индексе кракозябры (UTF-8, прочитанный как cp1251/latin-1). Исправь файлы через Edit и закоммить снова:")
$hits | ForEach-Object { [Console]::Error.WriteLine($_.Substring(0, [Math]::Min(160, $_.Length))) }
exit 2
