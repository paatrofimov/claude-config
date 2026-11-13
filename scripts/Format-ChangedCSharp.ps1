# Форматирует CSharpier только строки, измененные относительно -Base. Новые файлы форматируются целиком.
# CSharpier переписывает файл целиком, а в неотформатированном репо это дает в диффе чужие строки:
# скрипт оставляет только те правки CSharpier, что задевают измененные строки, остальные откатывает.
param(
    # Файлы .cs; по умолчанию – все измененные и новые .cs в рабочей копии.
    [string[]]$Files,
    [string]$Base = "HEAD",
    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$utf8 = New-Object Text.UTF8Encoding($false)
$hunkPattern = '^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@'

function Read-Lines([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = $utf8.GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [Collections.Generic.List[string]]($text -split "`r?`n")
    $trailing = $lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq ""
    if ($trailing) { $lines.RemoveAt($lines.Count - 1) }
    [pscustomobject]@{ Lines = $lines; Bom = $bom; Newline = $newline; Trailing = $trailing }
}

function Get-Hunks([string[]]$diff) {
    $hunks = @(); $current = $null
    foreach ($line in $diff) {
        if ($line -match $hunkPattern) {
            $current = [pscustomobject]@{
                OldStart = [int]$Matches[1]; OldCount = $(if ($Matches[2] -ne $null -and $Matches[2] -ne '') { [int]$Matches[2] } else { 1 })
                NewStart = [int]$Matches[3]; NewCount = $(if ($Matches[4] -ne $null -and $Matches[4] -ne '') { [int]$Matches[4] } else { 1 })
                Added = [Collections.Generic.List[string]]::new()
            }
            $hunks += $current
        }
        elseif ($current -and $line.StartsWith('+')) { $current.Added.Add($line.Substring(1).TrimEnd("`r")) }
    }
    $hunks
}

function Test-FileInBase([string]$file) {
    [bool](git -C $Repo ls-tree --name-only $Base -- $file)
}

if (-not $Files) {
    $Files = @(git -C $Repo diff --name-only --diff-filter=AM $Base -- '*.cs') + @(git -C $Repo ls-files --others --exclude-standard -- '*.cs')
}
$Files = $Files | Where-Object { $_ } | ForEach-Object { $_ -replace '\\', '/' } | Sort-Object -Unique
if (-not $Files) { Write-Host "нет измененных .cs"; return }

foreach ($file in $Files) {
    $path = Join-Path $Repo $file
    if (-not (Test-FileInBase $file)) {
        Push-Location $Repo; try { dotnet csharpier format $path | Out-Null } finally { Pop-Location }
        Write-Host "новый, отформатирован целиком: $file"
        continue
    }

    # Строки рабочей копии, измененные относительно -Base; у удаления – соседние строки.
    $touched = [Collections.Generic.HashSet[int]]::new()
    foreach ($h in Get-Hunks (git -C $Repo -c core.autocrlf=false diff --no-color -U0 $Base -- $file)) {
        if ($h.NewCount -gt 0) { $h.NewStart..($h.NewStart + $h.NewCount - 1) | ForEach-Object { [void]$touched.Add($_) } }
        else { [void]$touched.Add($h.NewStart); [void]$touched.Add($h.NewStart + 1) }
    }

    $pre = Read-Lines $path
    $preCopy = [IO.Path]::GetTempFileName()
    $postCopy = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::Copy($path, $preCopy, $true)
        Push-Location $Repo; try { dotnet csharpier format $path | Out-Null } finally { Pop-Location }
        [IO.File]::Copy($path, $postCopy, $true)
        $hunks = Get-Hunks (git -c core.autocrlf=false diff --no-index --no-color -U0 -- $preCopy $postCopy)
    }
    finally { Remove-Item $preCopy, $postCopy -ErrorAction SilentlyContinue }

    $result = [Collections.Generic.List[string]]::new()
    $pos = 1; $kept = 0; $dropped = 0
    foreach ($h in $hunks) {
        $range = if ($h.OldCount -gt 0) { $h.OldStart..($h.OldStart + $h.OldCount - 1) } else { @($h.OldStart, ($h.OldStart + 1)) }
        if (-not ($range | Where-Object { $touched.Contains($_) })) { $dropped++; continue }
        $kept++
        $copyUntil = if ($h.OldCount -gt 0) { $h.OldStart - 1 } else { $h.OldStart }
        for (; $pos -le $copyUntil; $pos++) { $result.Add($pre.Lines[$pos - 1]) }
        $result.AddRange($h.Added)
        $pos = if ($h.OldCount -gt 0) { $h.OldStart + $h.OldCount } else { $h.OldStart + 1 }
    }
    for (; $pos -le $pre.Lines.Count; $pos++) { $result.Add($pre.Lines[$pos - 1]) }

    $text = ($result -join $pre.Newline) + $(if ($pre.Trailing) { $pre.Newline } else { "" })
    $bytes = $utf8.GetBytes($text)
    if ($pre.Bom) { $bytes = [byte[]](0xEF, 0xBB, 0xBF) + $bytes }
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Host "${file}: правок CSharpier применено $kept, откачено $dropped"
}
