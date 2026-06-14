# Assign album covers; album names use （苏打绿版） reissue titles only.
$ProjectRoot = $PSScriptRoot
$desktop = [Environment]::GetFolderPath('Desktop')
$coverFolderName = -join @([char]0x4E13, [char]0x8F91, [char]0x5C01, [char]0x9762)
$CoverSource = Join-Path $desktop $coverFolderName
$CoverDest = Join-Path $ProjectRoot "covers"
$MapFile = Join-Path $ProjectRoot "album-map.json"
$SongsFile = Join-Path $ProjectRoot "songs-data.js"

if (-not (Test-Path $CoverSource)) { throw "Cover folder not found: $CoverSource" }
if (-not (Test-Path $MapFile)) { throw "Mapping file not found: $MapFile" }

$map = Get-Content $MapFile -Raw -Encoding UTF8 | ConvertFrom-Json
$defaultCoverAlbum = ($map.albumCovers.PSObject.Properties | Select-Object -Index 1).Name
$storyAlbum = $map.storyOrchestralAlbum

New-Item -ItemType Directory -Force -Path $CoverDest | Out-Null
Get-ChildItem $CoverSource -Filter "*.jpg" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $CoverDest $_.Name) -Force
}

function Normalize-Title([string]$title) {
    $t = $title.Trim()
    $artistSuffix = ([char]0x82CF).ToString() + ([char]0x6253).ToString() + ([char]0x7EFF).ToString()
    $t = $t -replace ("\s*-\s*" + $artistSuffix + ".*$"), ''
    return $t.Trim()
}

function Normalize-Apostrophe([string]$text) {
    return $text.Replace([char]0x2019, "'").Replace([char]0x2018, "'").Replace([char]0x2032, "'")
}

function Strip-TrailingParenGroups([string]$text) {
    $t = $text
    $openFw = [char]0xFF08
    $closeFw = [char]0xFF09
    $changed = $true
    while ($changed) {
        $changed = $false
        if ($t -match '\([^)]*\)\s*$') {
            $t = ($t -replace '\([^)]*\)\s*$', '').Trim()
            $changed = $true
            continue
        }
        if ($t.EndsWith($closeFw)) {
            $idx = $t.LastIndexOf($openFw)
            if ($idx -ge 0) {
                $t = $t.Substring(0, $idx).Trim()
                $changed = $true
            }
        }
    }
    return $t
}

function Get-BaseTitle([string]$title) {
    $t = Normalize-Apostrophe (Normalize-Title $title)
    return (Strip-TrailingParenGroups $t)
}

function Get-VersionTag([string]$title) {
    $t = Normalize-Apostrophe (Normalize-Title $title)
    if ($t -match '\(([^)]+)\)\s*$') { return $Matches[1].Trim() }
    $openFw = [char]0xFF08
    $closeFw = [char]0xFF09
    if ($t.EndsWith($closeFw)) {
        $idx = $t.LastIndexOf($openFw)
        if ($idx -ge 0) {
            return $t.Substring($idx + 1, $t.Length - $idx - 2).Trim()
        }
    }
    return ''
}

function Test-LiveInSummer([string]$title, [string]$version) {
    $hay = (Normalize-Apostrophe $title) + ' ' + (Normalize-Apostrophe $version)
    if ($hay -match 'Live in summer') { return $true }
    return $false
}

function Resolve-VersionRule([string]$base, [string]$version) {
    if ($map.storyVersionMarker -and $version -like "*$($map.storyVersionMarker)*") {
        return $storyAlbum
    }
    foreach ($rule in $map.versionRules) {
        if ($version -like "*$($rule.match)*") {
            if ($rule.bases) {
                if ($rule.bases -contains $base) { return $rule.album }
            } else {
                return $rule.album
            }
        }
    }
    return $null
}

function Resolve-Album([string]$title) {
    $base = Get-BaseTitle $title
    $version = Get-VersionTag $title

    $ruleAlbum = Resolve-VersionRule $base $version
    if ($ruleAlbum) { return $ruleAlbum }

    if (Test-LiveInSummer $title $version) {
        if ($map.liveInSummer.PSObject.Properties.Name -contains $base) {
            return $map.liveInSummer.$base
        }
    }

    if ($map.songs.PSObject.Properties.Name -contains $base) {
        return $map.songs.$base
    }

    return $defaultCoverAlbum
}

function Resolve-CoverPath([string]$albumKey) {
    if ($map.albumCovers.PSObject.Properties.Name -contains $albumKey) {
        $fileName = $map.albumCovers.$albumKey
    } else {
        $fileName = $map.albumCovers.$defaultCoverAlbum
    }
    return "covers/$fileName"
}

$content = [System.IO.File]::ReadAllText($SongsFile, [System.Text.Encoding]::UTF8)
$marker = "const SONGS_DATA = "
$start = $content.IndexOf($marker)
if ($start -lt 0) { throw "SONGS_DATA marker not found" }
$json = $content.Substring($start + $marker.Length).TrimEnd()
if ($json.EndsWith(";")) { $json = $json.Substring(0, $json.Length - 1) }
$songs = $json | ConvertFrom-Json

$unmapped = New-Object System.Collections.Generic.List[string]
foreach ($song in $songs) {
    $albumKey = Resolve-Album $song.title
    $base = Get-BaseTitle $song.title
    $version = Get-VersionTag $song.title
    $isLive = Test-LiveInSummer $song.title $version
    $inLiveMap = $map.liveInSummer.PSObject.Properties.Name -contains $base
    $inSongMap = $map.songs.PSObject.Properties.Name -contains $base
    $hasRule = Resolve-VersionRule $base $version

    if (-not $hasRule -and -not $inSongMap -and (-not $isLive -or -not $inLiveMap)) {
        [void]$unmapped.Add($song.title)
    }

    $song.album = $albumKey
    $song.cover = Resolve-CoverPath $albumKey
}

$newJson = $songs | ConvertTo-Json -Depth 6
$header = "// Auto-generated Sodagreen lyrics database`n"
$header += "// Album names: reissue editions with （苏打绿版） suffix`n"
$header += "// Live in summer is a version tag, not an album name`n"
$header += "// Total: $($songs.Count) songs`n"
$header += "// Regenerate lyrics: powershell -File import_lyrics.ps1`n"
$header += "// Assign covers: powershell -File assign_covers.ps1`n"
$header += "const SONGS_DATA = $newJson;"
[System.IO.File]::WriteAllText($SongsFile, $header + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host "Assigned covers to $($songs.Count) songs"
Write-Host "Cover images copied to: $CoverDest"
if ($unmapped.Count -gt 0) {
    Write-Host "Unmapped songs ($($unmapped.Count)):"
    $unmapped | ForEach-Object { Write-Host "  - $_" }
}
