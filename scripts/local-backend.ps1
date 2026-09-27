$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$state = Join-Path $repo '.local'
$status = Get-Content -LiteralPath (Join-Path $state 'supabase-status.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (([Uri]$status.API_URL).Host -notin @('127.0.0.1','localhost','::1')) { throw 'Local Supabase URL required.' }
if (-not $status.SERVICE_ROLE_KEY) { throw 'Local Supabase service-role key unavailable.' }
# This child process reads no backend/.env and clears externally configured service settings.
$example = Get-Content -LiteralPath (Join-Path $repo 'backend\.env.example') -Encoding UTF8
foreach ($line in $example) {
  if ($line -match '^([A-Z][A-Z0-9_]*)=') { [Environment]::SetEnvironmentVariable($Matches[1],$null,'Process') }
}
foreach ($name in @('FIREBASE_PROJECT_ID','FIREBASE_ADMIN_KEY_PATH','GOOGLE_APPLICATION_CREDENTIALS','GEMINI_API_KEY','GEMINI_MODEL','FIREBASE_AUTH_EMULATOR_HOST')) {
  [Environment]::SetEnvironmentVariable($name,$null,'Process')
}
$env:NODE_ENV = 'development'
$env:LUNCHSYNC_LOCAL_RUNTIME = 'true'
$env:SUPABASE_URL = $status.API_URL
$env:SUPABASE_SERVICE_ROLE_KEY = $status.SERVICE_ROLE_KEY
$env:SUPABASE_ANON_KEY = $status.ANON_KEY
$jwtPath = Join-Path $state 'jwt-secret.local'
if (-not (Test-Path -LiteralPath $jwtPath)) {
  $random = New-Object byte[] 48
  $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $generator.GetBytes($random) } finally { $generator.Dispose() }
  [IO.File]::WriteAllText($jwtPath,[Convert]::ToBase64String($random))
}
$env:JWT_SECRET = [IO.File]::ReadAllText($jwtPath)
$env:KAKAO_APP_ID = '1534395'
$env:PORT = '3000'
$env:ALLOW_SIMULATED_PAYMENTS = 'true'
$env:DEV_PROMOTE_ENABLED = 'false'
Push-Location (Join-Path $repo 'backend')
try {
  & npm.cmd run build
  if ($LASTEXITCODE -ne 0) { throw 'Backend build failed; refusing stale dist.' }
  & node.exe dist/main.js
  if ($LASTEXITCODE -ne 0) { throw 'Local backend exited unsuccessfully.' }
} finally { Pop-Location }
