<#
.SYNOPSIS
Готовит дифф MR для ревью: SHA, список файлов по группам и диффы групп в отдельных файлах.

.DESCRIPTION
Полный дифф большого MR не помещается в вывод команды, а снапшоты и тестовые данные забивают его целиком.
Скрипт делает fetch веток MR, раскладывает файлы на группы code, tests, snapshots и пишет дифф каждой
группы в <OutDir>\<группа>.diff. В консоль – только SHA, ссылка на MR и статистика по группам.
Запускать из корня репозитория, в котором открыт MR. Нужен glab с доступом к GitLab.

.EXAMPLE
Get-MrDiff.ps1 7082
#>
param(
	[Parameter(Mandatory)] [string] $Mr,
	[string] $OutDir
)
$ErrorActionPreference = "Stop"

$id = if ($Mr -match '(\d+)\D*$') { $Matches[1] } else { throw "Не найден номер MR в '$Mr'" }
$info = glab mr view $id -F json | ConvertFrom-Json
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP "mr-$id" }
New-Item -ItemType Directory -Force $OutDir | Out-Null

git fetch -q origin $info.source_branch $info.target_branch
$head = git rev-parse "origin/$($info.source_branch)"
$range = "origin/$($info.target_branch)...$head"

$groups = [ordered]@{ code = @(); tests = @(); snapshots = @() }
foreach ($line in git diff --numstat $range) {
	$added, $deleted, $path = $line -split "`t", 3
	$group = if ($path -match '\.verified\.|__snapshots__|[\\/]TestData[\\/]') { 'snapshots' }
		elseif ($path -match '(?i)tests?[\\/.]|Tests\.cs$|\.(spec|test)\.') { 'tests' }
		else { 'code' }
	$groups[$group] += [pscustomobject]@{ Path = $path; Added = $added; Deleted = $deleted }
}

"MR !$id $($info.web_url)"
"head $head, база origin/$($info.target_branch)"
foreach ($name in $groups.Keys) {
	$files = $groups[$name]
	if ($files.Count -eq 0) { continue }
	$diffFile = Join-Path $OutDir "$name.diff"
	git diff $range -- ($files.Path) | Out-File -Encoding utf8 $diffFile
	""
	"== $name ($($files.Count) файлов) -> $diffFile"
	if ($name -eq 'snapshots') { continue }
	$files | ForEach-Object { "  +$($_.Added) -$($_.Deleted) $($_.Path)" }
}
