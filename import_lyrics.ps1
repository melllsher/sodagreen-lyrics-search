# Import Sodagreen lyrics from txt files into songs-data.js
$TxtDir = "C:\Users\70707\Desktop\sodagreen-lyrics\lrc\output_txt"
$Output = Join-Path $PSScriptRoot "songs-data.js"

$GreenPalette = @(
    @("#1b4332", "#40916c"),
    @("#2d6a4f", "#52b788"),
    @("#344e41", "#588157"),
    @("#006d77", "#83c5be"),
    @("#264653", "#2a9d8f"),
    @("#52796f", "#84a98c"),
    @("#606c38", "#a7c957"),
    @("#1d3557", "#457b9d")
)

function Get-Colors($key) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($key)
    $md5 = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
    $idx = [BitConverter]::ToInt32($md5, 0)
    if ($idx -lt 0) { $idx = -$idx }
    return $GreenPalette[$idx % $GreenPalette.Count]
}

function Parse-Filename($filename) {
    $base = $filename -replace '\.txt$', ''
    $suffix = [char]0x82CF + [char]0x6253 + [char]0x7EFF
    $base = $base -replace ("\s*-\s*" + $suffix + "\s*$"), ''
    if ($base -match '\(([^)]+)\)\s*$') {
        $album = $Matches[1].Trim()
    } else {
        $album = "Unknown"
    }
    return @{ title = $base.Trim(); album = $album }
}

function Is-MetadataLine($line) {
    if ($line -match '^\s*\S{1,12}\s*:\s*\S') { return $true }
    $fullColon = [char]0xFF1A
    if ($line.Contains($fullColon)) {
        $parts = $line.Split($fullColon)
        if ($parts.Count -ge 2 -and $parts[0].Trim().Length -le 12 -and $parts[1].Trim().Length -gt 0) {
            return $true
        }
    }
    return $false
}

function Clean-Lyrics($raw) {
    $lines = ($raw -replace "`r`n", "`n" -replace "`r", "`n") -split "`n"
    $cleaned = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $stripped = $line.Trim()
        if ($stripped -eq '') {
            if ($cleaned.Count -gt 0 -and $cleaned[$cleaned.Count - 1] -ne '') {
                [void]$cleaned.Add('')
            }
            continue
        }
        if (Is-MetadataLine $stripped) { continue }
        [void]$cleaned.Add($stripped)
    }
    while ($cleaned.Count -gt 0 -and $cleaned[$cleaned.Count - 1] -eq '') {
        $cleaned.RemoveAt($cleaned.Count - 1)
    }
    return ($cleaned -join "`n")
}

$files = Get-ChildItem -Path $TxtDir -Filter "*.txt" | Sort-Object Name
if ($files.Count -eq 0) { throw "No txt files found in $TxtDir" }

$songs = New-Object System.Collections.Generic.List[object]
$i = 1
$artist = -join @([char]0x82CF, [char]0x6253, [char]0x7EFF)

foreach ($file in $files) {
    $parsed = Parse-Filename $file.Name
    $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $colors = Get-Colors $parsed.title
    [void]$songs.Add([ordered]@{
        id         = "{0:D3}" -f $i
        title      = $parsed.title
        artist     = $artist
        album      = $parsed.album
        cover      = ""
        coverColor = $colors
        lyrics     = (Clean-Lyrics $raw)
    })
    $i++
}

$json = $songs | ConvertTo-Json -Depth 5
$lines = @(
    "// Auto-generated Sodagreen lyrics database"
    "// Source: $TxtDir"
    "// Total: $($songs.Count) songs"
    "// Regenerate: powershell -File import_lyrics.ps1"
    "const SONGS_DATA = $json;"
)
[System.IO.File]::WriteAllLines($Output, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Imported $($songs.Count) songs -> $Output"

$assignScript = Join-Path $PSScriptRoot "assign_covers.ps1"
if (Test-Path $assignScript) {
    & $assignScript
}
