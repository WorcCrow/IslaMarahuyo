# Receive-StudioBackup.ps1
# Receives a backup posted by Export-FromStudio.luau (run inside Roblox Studio) and writes it
# into one backup folder. Listens on localhost only, accepts base64 bodies at
#   POST /file?path=<relative path>[&part=<i>&parts=<n>]   and   POST /done   (stops it)
# Studio caps a post at 1 MB, so big files arrive as numbered base64 parts, joined here.
# and refuses any path that would land outside -Root. Exits on /done or after the timeout.
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [int]$Port = 8765,
    [int]$TimeoutMinutes = 10
)
$ErrorActionPreference = 'Stop'

$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
New-Item -ItemType Directory -Force -Path $rootFull | Out-Null

$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Output "listening on http://localhost:$Port/ -> $rootFull"

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$files = 0
$bytes = 0
$errors = @()
$done = $false
$partial = @{} # [relative path] = StringBuilder of the base64 parts received so far
try {
    while (-not $done) {
        $pending = $listener.GetContextAsync()
        while (-not $pending.Wait(1000)) {
            if ((Get-Date) -ge $deadline) { throw "timed out after $TimeoutMinutes minutes" }
        }
        $ctx = $pending.Result
        $status = 200
        $reply = 'ok'
        try {
            if ($ctx.Request.Url.AbsolutePath -eq '/done') {
                $done = $true
            } else {
                $rel = $ctx.Request.QueryString['path']
                if (-not $rel -or $rel.Contains('..') -or [IO.Path]::IsPathRooted($rel)) { throw "bad path: $rel" }
                $target = [IO.Path]::GetFullPath((Join-Path $rootFull $rel))
                if (-not $target.StartsWith($rootFull + '\')) { throw "outside root: $rel" }
                $reader = [IO.StreamReader]::new($ctx.Request.InputStream, [Text.Encoding]::ASCII)
                $text = $reader.ReadToEnd()
                $qPart = $ctx.Request.QueryString['part']
                $qParts = $ctx.Request.QueryString['parts']
                $part = if ($qPart) { [int]$qPart } else { 1 }
                $parts = if ($qParts) { [int]$qParts } else { 1 }
                if ($parts -gt 1) {
                    if ($part -eq 1) { $partial[$rel] = [Text.StringBuilder]::new() }
                    if (-not $partial.ContainsKey($rel)) { throw "part $part of $rel arrived without part 1" }
                    [void]$partial[$rel].Append($text)
                    if ($part -lt $parts) {
                        $reply = "part $part/$parts"
                    } else {
                        $text = $partial[$rel].ToString()
                        $partial.Remove($rel)
                    }
                }
                if ($parts -le 1 -or $part -eq $parts) {
                    $data = [Convert]::FromBase64String($text)
                    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
                    [IO.File]::WriteAllBytes($target, $data)
                    $files++
                    $bytes += $data.Length
                    $reply = "$($data.Length)"
                }
            }
        } catch {
            $status = 400
            $reply = $_.Exception.Message
            $errors += $reply
        }
        $out = [Text.Encoding]::UTF8.GetBytes($reply)
        $ctx.Response.StatusCode = $status
        $ctx.Response.OutputStream.Write($out, 0, $out.Length)
        $ctx.Response.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
Write-Output ("received {0} files, {1:N0} bytes, {2} errors" -f $files, $bytes, $errors.Count)
$errors | ForEach-Object { Write-Output "  error: $_" }
