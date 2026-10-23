# IsDead WoW - publish a client update (for the server admin, not players).
#
# Put the new client files in .\files (laid out exactly like a World of Warcraft
# folder), then run publish.bat. This writes manifest.json, rebuilds
# IsDead-Launcher.zip and pushes everything to GitHub. Every player's launcher
# picks the update up the next time they start the game.

param(
    [string]$Message = '',  # commit message (default: "Client <version>")
    [switch]$NoPush         # build the manifest and zip only
)

$ErrorActionPreference = 'Stop'
$Here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Files = Join-Path $Here 'files'
$Utf8  = New-Object System.Text.UTF8Encoding($false)

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail([string]$text) { Say $text 'Red'; exit 1 }

$cfg = Get-Content -LiteralPath (Join-Path $Here 'config.json') -Raw | ConvertFrom-Json
if (-not $cfg.owner -or $cfg.owner -eq 'YOUR-GITHUB-NAME') { Fail 'Open config.json and put your GitHub user name in "owner" first.' }
$branch = 'main'
if ($cfg.branch) { $branch = [string]$cfg.branch }

# 1. the launcher reads from this repository
$launcher = Join-Path $Files 'IsDeadLauncher.ps1'
$text = [IO.File]::ReadAllText($launcher)
$text = [regex]::Replace($text, "(?m)^\`$Owner\s*=\s*'[^']*'", ("`$Owner  = '" + $cfg.owner + "'"))
$text = [regex]::Replace($text, "(?m)^\`$Repo\s*=\s*'[^']*'", ("`$Repo   = '" + $cfg.repo + "'"))
$text = [regex]::Replace($text, "(?m)^\`$Branch\s*=\s*'[^']*'", ("`$Branch = '" + $branch + "'"))
[IO.File]::WriteAllText($launcher, $text, $Utf8)

# 2. the version: the World Tiers addon's
$version = '0'
$toc = Join-Path $Files 'Interface/AddOns/WorldTiers/WorldTiers.toc'
if (Test-Path -LiteralPath $toc) {
    $m = Select-String -LiteralPath $toc -Pattern '^## Version:\s*(\S+)' | Select-Object -First 1
    if ($m) { $version = $m.Matches[0].Groups[1].Value }
}

# 3. the file list
$list = @()
$mpqs = @()
foreach ($f in (Get-ChildItem -LiteralPath $Files -Recurse -File | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($Files.Length).TrimStart('\', '/').Replace('\', '/')
    if ($rel -eq 'IsDead Launcher.bat' -or $rel -like '*.part') { continue }   # the .bat is running while the launcher works: never replaced
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
    $entry = [ordered]@{ path = $rel; size = $f.Length; sha256 = $sha }
    if ($rel -like 'Data/enUS/*') { $entry.localized = $true }    # goes to the player's own language folder
    $list += $entry
    if ($rel -like '*.MPQ') { $mpqs += $sha }
}
if ($list.Count -eq 0) { Fail 'The files folder is empty.' }

# the Cache folder only needs clearing when a patch file changes
$sha = [Security.Cryptography.SHA256]::Create()
$cache = -join ($sha.ComputeHash($Utf8.GetBytes(($mpqs -join ','))) | ForEach-Object { $_.ToString('x2') })
$cache = $cache.Substring(0, 16)

$managed = @()
foreach ($d in @('Interface/AddOns/WorldTiers', 'Interface/AddOns/Atlas')) {
    if (Test-Path -LiteralPath (Join-Path $Files $d)) { $managed += $d }
}

$manifest = [ordered]@{
    version      = $version
    cacheVersion = $cache
    realmlist    = [string]$cfg.realmlist
    news         = [string]$cfg.news
    managedDirs  = $managed
    files        = $list
}
[IO.File]::WriteAllText((Join-Path $Here 'manifest.json'), ($manifest | ConvertTo-Json -Depth 5), $Utf8)
Say ("manifest.json: version {0}, {1} files." -f $version, $list.Count) 'Green'

# 4. what players download once
$zip = Join-Path $Here 'IsDead-Launcher.zip'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('isdead-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath $launcher -Destination $stage
Copy-Item -LiteralPath (Join-Path $Files 'IsDead Launcher.bat') -Destination $stage
Copy-Item -LiteralPath (Join-Path $Here 'PLAYER-SETUP.txt') -Destination $stage
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item -LiteralPath $stage -Recurse -Force
Say 'IsDead-Launcher.zip rebuilt.' 'Green'

if ($NoPush) { exit 0 }

# 5. GitHub
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'Git is not installed. Get it from https://git-scm.com/download/win and run this again.' }
Push-Location $Here
try {
    $url = "https://github.com/$($cfg.owner)/$($cfg.repo).git"
    if (-not (Test-Path -LiteralPath (Join-Path $Here '.git'))) {
        git init | Out-Null
        git symbolic-ref HEAD "refs/heads/$branch"
        git config core.autocrlf false
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            gh repo view "$($cfg.owner)/$($cfg.repo)" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { gh repo create "$($cfg.owner)/$($cfg.repo)" --public --description 'IsDead WoW client files' | Out-Null }
        }
        git remote add origin $url
    }
    git config core.autocrlf false
    if (-not $Message) { $Message = "Client $version" }
    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { Say 'Nothing changed since the last publish.' 'Yellow'; exit 0 }
    git commit -m $Message | Out-Null
    git push -u origin $branch
    if ($LASTEXITCODE -ne 0) { Fail "The push failed. Does https://github.com/$($cfg.owner)/$($cfg.repo) exist (Public)? Create it on github.com (no README), then run publish.bat again." }
    Say ''
    Say "Published client $version. Players get it next time they start the IsDead Launcher." 'Green'
    Say "Launcher download for new players: https://github.com/$($cfg.owner)/$($cfg.repo)/raw/$branch/IsDead-Launcher.zip" 'Cyan'
} finally { Pop-Location }
