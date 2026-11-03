param([switch]$Start)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$state = Join-Path $repo '.local'
$stack = Join-Path $state 'supabase-stack'
$configDir = Join-Path $stack 'supabase'
New-Item -ItemType Directory -Force -Path $configDir,(Join-Path $configDir 'templates') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'supabase\migrations') -Destination $configDir -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repo 'supabase\seed.sql') -Destination (Join-Path $configDir 'seed.sql') -Force
$text = Get-Content -LiteralPath (Join-Path $repo 'supabase\config.toml') -Raw -Encoding UTF8
$text = $text -replace '(?m)^project_id = .*$', 'project_id = "lunchsync-local"'
$text = $text -replace '(?m)^email_sent = 2$', 'email_sent = 30'
$text += @'

[auth.email.template.confirmation]
subject = "LunchSync local verification"
content_path = "./supabase/templates/otp.html"

[auth.email.template.magic_link]
subject = "LunchSync local verification"
content_path = "./supabase/templates/otp.html"
'@
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $configDir 'config.toml'),$text,$utf8)
[IO.File]::WriteAllText((Join-Path $configDir 'templates\otp.html'),'<h2>LunchSync local verification</h2><p>Your code: <strong>{{ .Token }}</strong></p>',$utf8)
if (-not $Start) { Write-Host 'Local isolated Supabase configuration prepared.'; exit 0 }
Push-Location $repo
try {
  $network = 'lunchsync-loopback'
  $existingNetwork = & docker.exe network ls --filter "name=^$network`$" --format '{{.Name}}'
  if ($existingNetwork -ne $network) {
    & docker.exe network create --driver bridge --opt com.docker.network.bridge.host_binding_ipv4=127.0.0.1 $network | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Loopback Docker network creation failed.' }
  }
  $networkState = ((& docker.exe network inspect $network) -join "`n") | ConvertFrom-Json
  if ($networkState[0].Options.'com.docker.network.bridge.host_binding_ipv4' -ne '127.0.0.1') { throw 'Docker network must bind to loopback.' }
  $ids = @(& docker.exe ps --filter 'label=com.supabase.cli.project=lunchsync-local' --format '{{.ID}}')
  $unsafeBinding = $false
  foreach ($id in $ids) {
    $container = ((& docker.exe inspect $id) -join "`n") | ConvertFrom-Json
    foreach ($property in $container[0].NetworkSettings.Ports.PSObject.Properties) {
      foreach ($mapping in $property.Value) {
        if ($mapping.HostIp -notin @('127.0.0.1','::1')) { $unsafeBinding = $true }
      }
    }
  }
  # start/status operate only on the generated local workdir. No remote link/push/reset.
  # Windows PowerShell 5 treats ordinary native stderr as ErrorRecords.
  # Preserve exit-code checking without converting CLI progress into exceptions.
  $previousErrorPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    if ($unsafeBinding) {
      # Stop only our isolated project, preserving named database/storage volumes.
      & npx.cmd --yes supabase@2.109.1 stop --project-id lunchsync-local *> (Join-Path $state 'supabase-stop.private.log')
      if ($LASTEXITCODE -ne 0) { throw 'Local stack stop failed; no reset attempted.' }
    }
    & npx.cmd --yes supabase@2.109.1 start --workdir $stack --network-id $network *> (Join-Path $state 'supabase-start.private.log')
    $startExit = $LASTEXITCODE
    $status = & npx.cmd --yes supabase@2.109.1 status --workdir $stack -o json 2> (Join-Path $state 'supabase-status.private.log')
    $statusExit = $LASTEXITCODE
  } finally { $ErrorActionPreference = $previousErrorPreference }
  if ($startExit -ne 0) { throw 'Local Supabase startup failed; inspect .local/supabase-start.private.log locally.' }
  if ($statusExit -ne 0) { throw 'Local Supabase status failed.' }
  $values = ($status -join "`n") | ConvertFrom-Json
  if (-not $values.API_URL -or ([Uri]$values.API_URL).Host -notin @('127.0.0.1','localhost','::1')) { throw 'Nonlocal Supabase rejected.' }
  [IO.File]::WriteAllText((Join-Path $state 'supabase-status.json'),($values | ConvertTo-Json -Depth 8),$utf8)
  & node.exe (Join-Path $PSScriptRoot 'bind-local-containers.cjs')
  if ($LASTEXITCODE -ne 0) { throw 'Local port binding verification failed.' }
  Write-Host 'Local Supabase ready. API localhost:54321, inbox localhost:54324. Keys remain in ignored .local files.'
} finally { Pop-Location }
