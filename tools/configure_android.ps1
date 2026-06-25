$ErrorActionPreference = "Stop"

$manifestPath = Join-Path $PSScriptRoot "..\android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifestPath)) {
    throw "AndroidManifest.xml introuvable. Lance d'abord PREPARER_PROJET_WINDOWS.bat"
}

$content = Get-Content $manifestPath -Raw
$permissions = @(
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />'
)

foreach ($permission in $permissions) {
    if (-not $content.Contains($permission)) {
        $content = $content.Replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', "<manifest xmlns:android=`"http://schemas.android.com/apk/res/android`">`r`n    $permission")
    }
}

$content = $content.Replace('android:label="ruedex_mvp"', 'android:label="RueDex"')
Set-Content -Path $manifestPath -Value $content -Encoding UTF8

$gradleKtsPath = Join-Path $PSScriptRoot "..\android\app\build.gradle.kts"
$gradleGroovyPath = Join-Path $PSScriptRoot "..\android\app\build.gradle"

if (Test-Path $gradleKtsPath) {
    $gradleContent = Get-Content $gradleKtsPath -Raw
    $gradleContent = $gradleContent.Replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    Set-Content -Path $gradleKtsPath -Value $gradleContent -Encoding UTF8
} elseif (Test-Path $gradleGroovyPath) {
    $gradleContent = Get-Content $gradleGroovyPath -Raw
    $gradleContent = $gradleContent.Replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
    Set-Content -Path $gradleGroovyPath -Value $gradleContent -Encoding UTF8
}

Write-Host "Configuration Android appliquee (GPS + minSdk 24)." -ForegroundColor Green
