# Тесты Format-ChangedCSharp.ps1: во временном git-репозитории проверяет, что CSharpier трогает только измененные строки,
# для LF-файлов и для CRLF-файлов при core.autocrlf=true. Нужен dotnet; csharpier ставится локальным инструментом.
param([string]$CsharpierVersion = "1.3.0")

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "Format-ChangedCSharp.ps1"
$failed = 0

# Строка M длиннее printWidth: CSharpier ее перенес бы, но она не изменена и должна остаться как есть.
$untouched = "    void M(int aaaaaaaaaaaa, int bbbbbbbbbbbb, int cccccccccccc, int dddddddddddd, int eeeeee) { }"
$base = @("class A", "{", $untouched, "    void N() { }", "}")

function Invoke-Case([string]$name, [string]$eol, [string]$autocrlf, [int]$insertAt, [string]$inserted, [scriptblock]$check) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("fmt-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory $dir | Out-Null
    Push-Location $dir
    try {
        git init -q; git config core.autocrlf $autocrlf
        '{ "printWidth": 80, "endOfLine": "auto" }' | Set-Content .csharpierrc -Encoding ascii
        dotnet new tool-manifest | Out-Null
        dotnet tool install csharpier --version $CsharpierVersion | Out-Null
        [IO.File]::WriteAllText("$dir\A.cs", ($base -join $eol) + $eol)
        git add -A; git -c user.name=t -c user.email=t@t commit -qm base
        Remove-Item A.cs; git checkout -q -- A.cs
        $lines = [Collections.Generic.List[string]]([IO.File]::ReadAllText("$dir\A.cs") -split "`r?`n")
        $lines.Insert($insertAt, $inserted)
        [IO.File]::WriteAllText("$dir\A.cs", ($lines -join $eol))

        & $script -Files A.cs | Out-Null
        $text = [IO.File]::ReadAllText("$dir\A.cs")
        $problems = @(& $check $text)
        if ($text.Contains("`r`r")) { $problems += "двойной CR" }
        if ($eol -eq "`r`n" -and $text -match "[^`r]`n") { $problems += "LF в CRLF-файле" }
        if ($problems) { $script:failed++; Write-Host "FAIL ${name}: $($problems -join '; ')" }
        else { Write-Host "ok   $name" }
    }
    finally { Pop-Location; Remove-Item -Recurse -Force $dir }
}

$checkComment = {
    param($text)
    if (-not $text.Contains($untouched)) { "неизмененная строка M переформатирована" }
    if (-not $text.Contains("    // comment")) { "пропал вставленный комментарий" }
}
$longP = "    void P(int aaaaaaaaaaaa, int bbbbbbbbbbbb, int cccccccccccc, int dddddddddddd, int eeeeee) { }"
$checkLong = {
    param($text)
    if (-not $text.Contains($untouched)) { "неизмененная строка M переформатирована" }
    if ($text.Contains($longP)) { "измененная строка P не отформатирована" }
}

foreach ($eolCase in @(@{ Name = "LF"; Eol = "`n"; Autocrlf = "false" }, @{ Name = "CRLF"; Eol = "`r`n"; Autocrlf = "true" })) {
    Invoke-Case "$($eolCase.Name), вставлен комментарий" $eolCase.Eol $eolCase.Autocrlf 3 "    // comment" $checkComment
    Invoke-Case "$($eolCase.Name), вставлена длинная строка" $eolCase.Eol $eolCase.Autocrlf 4 $longP $checkLong
}

if ($failed) { Write-Host "упало: $failed"; exit 1 }
exit 0
