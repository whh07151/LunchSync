Add-Type -AssemblyName System.Drawing

$width = 1400
$height = 1000
$bmp = New-Object System.Drawing.Bitmap $width, $height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.Clear([System.Drawing.Color]::White)

function New-RoundedPath {
    param([int]$x, [int]$y, [int]$w, [int]$h, [int]$r)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($x, $y, $r*2, $r*2, 180, 90)
    $path.AddArc($x + $w - $r*2, $y, $r*2, $r*2, 270, 90)
    $path.AddArc($x + $w - $r*2, $y + $h - $r*2, $r*2, $r*2, 0, 90)
    $path.AddArc($x, $y + $h - $r*2, $r*2, $r*2, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-Card {
    param([int]$x, [int]$y, [int]$w, [int]$h, $fill, $border)
    $path = New-RoundedPath $x $y $w $h 16
    $brush = New-Object System.Drawing.SolidBrush $fill
    $pen = New-Object System.Drawing.Pen $border, 2
    $g.FillPath($brush, $path)
    $g.DrawPath($pen, $path)
    $brush.Dispose(); $pen.Dispose(); $path.Dispose()
}

function Draw-Text {
    param([string]$text, [int]$x, [int]$y, [int]$size, $color, [bool]$bold=$false, [string]$align="left")
    if ($bold) { $style = [System.Drawing.FontStyle]::Bold } else { $style = [System.Drawing.FontStyle]::Regular }
    $font = New-Object System.Drawing.Font("Malgun Gothic", $size, $style)
    $brush = New-Object System.Drawing.SolidBrush $color
    $fmt = New-Object System.Drawing.StringFormat
    if ($align -eq "center") { $fmt.Alignment = [System.Drawing.StringAlignment]::Center }
    if ($align -eq "right")  { $fmt.Alignment = [System.Drawing.StringAlignment]::Far }
    $g.DrawString($text, $font, $brush, $x, $y, $fmt)
    $font.Dispose(); $brush.Dispose(); $fmt.Dispose()
}

function Draw-Arrow {
    param([int]$x1, [int]$y1, [int]$x2, [int]$y2, $color)
    $pen = New-Object System.Drawing.Pen $color, 2
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
    $g.DrawLine($pen, $x1, $y1, $x2, $y2)
    $pen.Dispose()
}

function Draw-Badge {
    param([int]$cx, [int]$cy, [int]$radius, [string]$label, $color, $textColor)
    $brush = New-Object System.Drawing.SolidBrush $color
    $g.FillEllipse($brush, $cx - $radius, $cy - $radius, $radius*2, $radius*2)
    $brush.Dispose()
    $font = New-Object System.Drawing.Font("Malgun Gothic", 11, [System.Drawing.FontStyle]::Bold)
    $textBrush = New-Object System.Drawing.SolidBrush $textColor
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF (([float]($cx - $radius)), ([float]($cy - $radius)), ([float]($radius*2)), ([float]($radius*2)))
    $g.DrawString($label, $font, $textBrush, $rect, $fmt)
    $font.Dispose(); $textBrush.Dispose(); $fmt.Dispose()
}

# Colors
$colorRepoFill   = [System.Drawing.Color]::FromArgb(232, 224, 245)
$colorRepoBorder = [System.Drawing.Color]::FromArgb(150, 120, 200)
$colorClientFill   = [System.Drawing.Color]::FromArgb(220, 245, 232)
$colorClientBorder = [System.Drawing.Color]::FromArgb(110, 190, 150)
$colorApiFill   = [System.Drawing.Color]::FromArgb(252, 230, 230)
$colorApiBorder = [System.Drawing.Color]::FromArgb(220, 130, 140)
$colorDbFill   = [System.Drawing.Color]::FromArgb(220, 232, 248)
$colorDbBorder = [System.Drawing.Color]::FromArgb(110, 150, 220)
$colorExtFill   = [System.Drawing.Color]::FromArgb(245, 245, 245)
$colorExtBorder = [System.Drawing.Color]::FromArgb(170, 170, 170)
$dark = [System.Drawing.Color]::FromArgb(50, 50, 50)
$gray = [System.Drawing.Color]::FromArgb(110, 110, 110)
$white = [System.Drawing.Color]::White
$black = [System.Drawing.Color]::Black
$arrowColor = [System.Drawing.Color]::FromArgb(120, 120, 120)

# Development (top left) - Claude Code
$colorDevFill   = [System.Drawing.Color]::FromArgb(252, 240, 228)
$colorDevBorder = [System.Drawing.Color]::FromArgb(220, 140, 80)
$devX = 280; $devY = 40; $devW = 250; $devH = 90
Draw-Card $devX $devY $devW $devH $colorDevFill $colorDevBorder
Draw-Text "Development" ($devX + $devW/2) ($devY + 12) 11 $gray $false "center"
Draw-Badge ($devX + 50) ($devY + 55) 18 "CC" ([System.Drawing.Color]::FromArgb(217, 119, 87)) $white
Draw-Text "Claude Code" ($devX + 80) ($devY + 38) 14 $dark $true "left"
Draw-Text "AI Pair Programming" ($devX + 80) ($devY + 60) 9 $gray $false "left"

# Repository (top right of center)
$repoX = 700; $repoY = 40; $repoW = 250; $repoH = 90
Draw-Card $repoX $repoY $repoW $repoH $colorRepoFill $colorRepoBorder
Draw-Text "Repository" ($repoX + $repoW/2) ($repoY + 12) 11 $gray $false "center"
Draw-Badge ($repoX + 50) ($repoY + 55) 18 "GH" ([System.Drawing.Color]::FromArgb(36, 41, 47)) $white
Draw-Text "GitHub" ($repoX + 80) ($repoY + 45) 16 $dark $true "left"

# Arrow: Claude Code -> GitHub
Draw-Arrow ($devX + $devW) ($devY + $devH/2) $repoX ($repoY + $repoH/2) $arrowColor
Draw-Text "commits" ($devX + $devW + 8) ($devY + 22) 9 $gray $false "left"

# User icon (far left)
$userX = 40; $userY = 340
$brushU = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180, 180, 180))
$g.FillEllipse($brushU, $userX, $userY, 40, 40)
$g.FillEllipse($brushU, ($userX - 5), ($userY + 35), 50, 50)
$brushU.Dispose()
Draw-Text "User" ($userX + 20) ($userY + 95) 11 $gray $true "center"

# Client (left)
$clientX = 160; $clientY = 200; $clientW = 320; $clientH = 320
Draw-Card $clientX $clientY $clientW $clientH $colorClientFill $colorClientBorder
Draw-Text "Client" ($clientX + $clientW/2) ($clientY + 12) 12 $gray $false "center"

Draw-Badge ($clientX + 50) ($clientY + 75) 22 "F" ([System.Drawing.Color]::FromArgb(2, 86, 155)) $white
Draw-Text "Flutter" ($clientX + 90) ($clientY + 55) 16 $dark $true "left"
Draw-Text "Customer App (Web/Mobile)" ($clientX + 90) ($clientY + 80) 10 $gray $false "left"

Draw-Badge ($clientX + 50) ($clientY + 140) 22 "R" ([System.Drawing.Color]::FromArgb(64, 195, 248)) $white
Draw-Text "Riverpod" ($clientX + 90) ($clientY + 120) 16 $dark $true "left"
Draw-Text "State Management" ($clientX + 90) ($clientY + 145) 10 $gray $false "left"

Draw-Badge ($clientX + 50) ($clientY + 205) 22 "N" $black $white
Draw-Text "Next.js" ($clientX + 90) ($clientY + 185) 16 $dark $true "left"
Draw-Text "LSPOS Web (Vercel)" ($clientX + 90) ($clientY + 210) 10 $gray $false "left"

Draw-Badge ($clientX + 50) ($clientY + 270) 22 "FB" ([System.Drawing.Color]::FromArgb(255, 145, 0)) $white
Draw-Text "Firebase Auth + FCM" ($clientX + 90) ($clientY + 250) 14 $dark $true "left"
Draw-Text "Phone OTP / Push" ($clientX + 90) ($clientY + 275) 10 $gray $false "left"

# API Server (center)
$apiX = 540; $apiY = 200; $apiW = 320; $apiH = 380
Draw-Card $apiX $apiY $apiW $apiH $colorApiFill $colorApiBorder
Draw-Text "API Server" ($apiX + $apiW/2) ($apiY + 12) 12 $gray $false "center"

Draw-Badge ($apiX + 50) ($apiY + 75) 22 "Ne" ([System.Drawing.Color]::FromArgb(224, 35, 75)) $white
Draw-Text "NestJS" ($apiX + 90) ($apiY + 55) 16 $dark $true "left"
Draw-Text "17 Modules / DTO Validation" ($apiX + 90) ($apiY + 80) 10 $gray $false "left"

Draw-Badge ($apiX + 50) ($apiY + 140) 22 "J" $black $white
Draw-Text "JWT" ($apiX + 90) ($apiY + 120) 16 $dark $true "left"
Draw-Text "Auth / Permission (48h)" ($apiX + 90) ($apiY + 145) 10 $gray $false "left"

Draw-Badge ($apiX + 50) ($apiY + 205) 22 "Se" ([System.Drawing.Color]::FromArgb(0, 130, 100)) $white
Draw-Text "Helmet + Throttler" ($apiX + 90) ($apiY + 185) 14 $dark $true "left"
Draw-Text "Security Headers / Rate Limit" ($apiX + 90) ($apiY + 210) 10 $gray $false "left"

Draw-Badge ($apiX + 50) ($apiY + 270) 22 "AI" ([System.Drawing.Color]::FromArgb(66, 133, 244)) $white
Draw-Text "Gemini AI" ($apiX + 90) ($apiY + 250) 16 $dark $true "left"
Draw-Text "Menu Auto-gen / Recommend" ($apiX + 90) ($apiY + 275) 10 $gray $false "left"

Draw-Badge ($apiX + 50) ($apiY + 335) 22 "AW" ([System.Drawing.Color]::FromArgb(255, 153, 0)) $white
Draw-Text "AWS EC2 + Vercel" ($apiX + 90) ($apiY + 315) 14 $dark $true "left"
Draw-Text "CI/CD: GitHub Actions" ($apiX + 90) ($apiY + 340) 10 $gray $false "left"

# Database (right)
$dbX = 920; $dbY = 200; $dbW = 320; $dbH = 240
Draw-Card $dbX $dbY $dbW $dbH $colorDbFill $colorDbBorder
Draw-Text "Database" ($dbX + $dbW/2) ($dbY + 12) 12 $gray $false "center"

Draw-Badge ($dbX + 50) ($dbY + 75) 22 "Sb" ([System.Drawing.Color]::FromArgb(62, 207, 142)) $white
Draw-Text "Supabase" ($dbX + 90) ($dbY + 55) 16 $dark $true "left"
Draw-Text "Auth | Realtime | Storage" ($dbX + 90) ($dbY + 80) 10 $gray $false "left"

Draw-Badge ($dbX + 50) ($dbY + 140) 22 "Pg" ([System.Drawing.Color]::FromArgb(51, 103, 145)) $white
Draw-Text "PostgreSQL" ($dbX + 90) ($dbY + 120) 16 $dark $true "left"
Draw-Text "Data Storage / RPC Tx" ($dbX + 90) ($dbY + 145) 10 $gray $false "left"

Draw-Badge ($dbX + 50) ($dbY + 195) 18 "Cr" ([System.Drawing.Color]::FromArgb(120, 60, 180)) $white
Draw-Text "Crawl Module + Menu Seed" ($dbX + 80) ($dbY + 190) 11 $dark $true "left"

# External Services (bottom)
$extX = 280; $extY = 640; $extW = 840; $extH = 200
Draw-Card $extX $extY $extW $extH $colorExtFill $colorExtBorder
Draw-Text "External Services" ($extX + $extW/2) ($extY + 12) 12 $gray $false "center"

function Draw-Service {
    param([int]$col, [int]$row, [string]$name, [string]$desc, $color, [string]$label, $textColor)
    $bx = $extX + 40 + ($col * 270)
    $by = $extY + 60 + ($row * 75)
    Draw-Badge ($bx + 20) ($by + 20) 22 $label $color $textColor
    Draw-Text $name ($bx + 60) ($by + 5) 13 $dark $true "left"
    Draw-Text $desc ($bx + 60) ($by + 28) 10 $gray $false "left"
}

Draw-Service 0 0 "Kakao SDK" "Kakao Login" ([System.Drawing.Color]::FromArgb(254, 229, 0)) "K" $black
Draw-Service 1 0 "Toss Payments" "Payment Module" ([System.Drawing.Color]::FromArgb(50, 90, 240)) "T" $white
Draw-Service 2 0 "FCM" "Push Notification" ([System.Drawing.Color]::FromArgb(255, 152, 0)) "FC" $white
Draw-Service 0 1 "Firebase Phone" "SMS Verification" ([System.Drawing.Color]::FromArgb(255, 196, 0)) "FA" $black
Draw-Service 1 1 "Email OTP" "Email Verify (Supabase)" ([System.Drawing.Color]::FromArgb(150, 100, 200)) "@" $white
Draw-Service 2 1 "Geolocation" "GPS / Map Recommend" ([System.Drawing.Color]::FromArgb(70, 170, 100)) "GP" $white

# Arrows
Draw-Arrow ($repoX + 60) ($repoY + $repoH) ($clientX + $clientW/2) $clientY $arrowColor
Draw-Arrow ($repoX + $repoW/2) ($repoY + $repoH) ($apiX + $apiW/2) $apiY $arrowColor
Draw-Arrow ($repoX + $repoW - 60) ($repoY + $repoH) ($dbX + $dbW/2) $dbY $arrowColor

Draw-Arrow ($clientX + $clientW) ($clientY + 180) $apiX ($apiY + 180) $arrowColor
Draw-Arrow $apiX ($apiY + 220) ($clientX + $clientW) ($clientY + 220) $arrowColor

Draw-Arrow ($apiX + $apiW) ($apiY + 180) $dbX ($dbY + 100) $arrowColor
Draw-Arrow $dbX ($dbY + 140) ($apiX + $apiW) ($apiY + 220) $arrowColor

Draw-Arrow ($apiX + 100) ($apiY + $apiH) ($extX + 200) $extY $arrowColor
Draw-Arrow ($apiX + 220) ($apiY + $apiH) ($extX + 600) $extY $arrowColor

Draw-Arrow ($userX + 45) ($userY + 60) $clientX ($clientY + 200) $arrowColor

# Title
Draw-Text "LunchSync System Architecture" ($width / 2) 880 22 $dark $true "center"
Draw-Text "Flutter + NestJS + Supabase + Gemini AI" ($width / 2) 920 12 $gray $false "center"

# Save
$outPath = "C:\Users\user\StudioProjects\LunchSync\docs\LunchSync_Architecture.png"
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()

Write-Output "Saved: $outPath"
