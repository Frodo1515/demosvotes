param(
  [int]$Port = 8000,
  [string]$Root = (Get-Location).Path
)

$Mime = @{
  ".html"="text/html; charset=utf-8"
  ".htm" ="text/html; charset=utf-8"
  ".js"  ="application/javascript; charset=utf-8"
  ".css" ="text/css; charset=utf-8"
  ".json"="application/json; charset=utf-8"
  ".png" ="image/png"
  ".jpg" ="image/jpeg"
  ".jpeg"="image/jpeg"
  ".gif" ="image/gif"
  ".svg" ="image/svg+xml"
  ".mp4" ="video/mp4"
  ".webm"="video/webm"
}

function Get-ContentType([string]$path) {
  $ext = [IO.Path]::GetExtension($path).ToLower()
  if ($Mime.ContainsKey($ext)) { return $Mime[$ext] }
  return "application/octet-stream"
}

function Send-File($ctx, [string]$filePath) {
  $resp = $ctx.Response
  $resp.Headers["Accept-Ranges"] = "bytes"
  $resp.ContentType = Get-ContentType $filePath
  $fi = Get-Item $filePath
  $length = $fi.Length

  $range = $ctx.Request.Headers["Range"]
  if ($range -and $range -match "bytes=(\d+)-(\d*)") {
    $start = [int64]$matches[1]
    $end = if ($matches[2]) { [int64]$matches[2] } else { $length - 1 }
    if ($start -ge $length) { $resp.StatusCode = 416; $resp.Close(); return }
    if ($end -ge $length) { $end = $length - 1 }
    $count = $end - $start + 1

    $resp.StatusCode = 206
    $resp.Headers["Content-Range"] = "bytes $start-$end/$length"
    $resp.ContentLength64 = $count

    $fs = [IO.File]::OpenRead($filePath)
    try {
      $fs.Position = $start
      $buffer = New-Object byte[] 65536
      $remaining = $count
      while ($remaining -gt 0) {
        $read = $fs.Read($buffer, 0, [int][Math]::Min($buffer.Length, $remaining))
        if ($read -le 0) { break }
        $resp.OutputStream.Write($buffer, 0, $read)
        $remaining -= $read
      }
    } finally {
      $fs.Close()
      $resp.OutputStream.Close()
      $resp.Close()
    }
    return
  }

  $resp.StatusCode = 200
  $resp.ContentLength64 = $length
  $stream = $resp.OutputStream
  $fs2 = [IO.File]::OpenRead($filePath)
  try { $fs2.CopyTo($stream) } finally { $fs2.Close(); $stream.Close(); $resp.Close() }
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Serving on $prefix"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.AbsolutePath
  if ($path -eq "/" -or [string]::IsNullOrWhiteSpace($path)) { $path = "/present.html" }
  $full = Join-Path $Root ($path.TrimStart("/").Replace("/", "\"))
  if (!(Test-Path $full)) { $ctx.Response.StatusCode = 404; $ctx.Response.Close(); continue }
  Send-File $ctx $full
}
