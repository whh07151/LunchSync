param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('apk', 'web')]
  [string]$Target
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$state = Join-Path $repo '.local'
$mapKeyPath = Join-Path $state 'kakao-map-js-key.local'
if (-not (Test-Path -LiteralPath $mapKeyPath)) {
  throw 'Missing .local/kakao-map-js-key.local. Add the JavaScript key of the Kakao app with Maps enabled.'
}
$mapKey = (Get-Content -LiteralPath $mapKeyPath -Raw -Encoding UTF8).Trim()
if ($mapKey -notmatch '^[a-fA-F0-9]{32}$') {
  throw 'Kakao Maps JavaScript key must be 32 hexadecimal characters.'
}

New-Item -ItemType Directory -Force -Path $state | Out-Null
$definePath = Join-Path $state 'flutter-map-define.local.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$defineJson = @{ KAKAO_MAP_JS_KEY = $mapKey } | ConvertTo-Json -Compress
[IO.File]::WriteAllText($definePath, $defineJson, $utf8)

Push-Location $repo
try {
  & flutter build $Target --debug --no-pub "--dart-define-from-file=$definePath"
  if ($LASTEXITCODE -ne 0) { throw "Flutter $Target build failed." }
  Write-Host "Local $Target build completed with the Maps-enabled Kakao app key."
} finally {
  Pop-Location
}
