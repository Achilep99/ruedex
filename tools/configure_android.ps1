$ErrorActionPreference = "Stop"

$manifestPath = Join-Path $PSScriptRoot "..\android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifestPath)) {
    throw "AndroidManifest.xml introuvable. Lance d'abord flutter create."
}

$content = Get-Content $manifestPath -Raw
$permissions = @(
    '<uses-permission android:name="android.permission.CAMERA" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />'
)

foreach ($permission in $permissions) {
    if (-not $content.Contains($permission)) {
        $content = $content.Replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', "<manifest xmlns:android=`"http://schemas.android.com/apk/res/android`">`r`n    $permission")
    }
}

$cameraFeature = '<uses-feature android:name="android.hardware.camera.any" android:required="true" />'
if (-not $content.Contains($cameraFeature)) {
    $content = $content.Replace('<application', "    $cameraFeature`r`n    <application")
}

$content = $content.Replace('android:label="ruedex_mvp"', 'android:label="RueDex"')
Set-Content -Path $manifestPath -Value $content -Encoding UTF8

function Add-TextRecognitionDependenciesKts($gradleContent) {
    $deps = @(
        '    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")',
        '    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")',
        '    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")',
        '    implementation("com.google.mlkit:text-recognition-korean:16.0.1")'
    )

    foreach ($dep in $deps) {
        if (-not $gradleContent.Contains($dep.Trim())) {
            if ($gradleContent -match "(?m)^dependencies\s*\{") {
                $gradleContent = $gradleContent -replace "(?m)^dependencies\s*\{", "dependencies {`r`n$dep"
            } else {
                $gradleContent = $gradleContent.TrimEnd() + "`r`n`r`ndependencies {`r`n$dep`r`n}`r`n"
            }
        }
    }
    return $gradleContent
}

function Add-TextRecognitionDependenciesGroovy($gradleContent) {
    $deps = @(
        "    implementation 'com.google.mlkit:text-recognition-chinese:16.0.1'",
        "    implementation 'com.google.mlkit:text-recognition-devanagari:16.0.1'",
        "    implementation 'com.google.mlkit:text-recognition-japanese:16.0.1'",
        "    implementation 'com.google.mlkit:text-recognition-korean:16.0.1'"
    )

    foreach ($dep in $deps) {
        if (-not $gradleContent.Contains($dep.Trim())) {
            if ($gradleContent -match "(?m)^dependencies\s*\{") {
                $gradleContent = $gradleContent -replace "(?m)^dependencies\s*\{", "dependencies {`r`n$dep"
            } else {
                $gradleContent = $gradleContent.TrimEnd() + "`r`n`r`ndependencies {`r`n$dep`r`n}`r`n"
            }
        }
    }
    return $gradleContent
}

function Force-NoReleaseShrinkKts($gradleContent) {
    $gradleContent = $gradleContent.Replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')

    if ($gradleContent.Contains('isMinifyEnabled = true')) {
        $gradleContent = $gradleContent.Replace('isMinifyEnabled = true', 'isMinifyEnabled = false')
    }
    if ($gradleContent.Contains('isShrinkResources = true')) {
        $gradleContent = $gradleContent.Replace('isShrinkResources = true', 'isShrinkResources = false')
    }

    if (-not $gradleContent.Contains('isMinifyEnabled = false')) {
        if ($gradleContent -match 'release\s*\{') {
            $gradleContent = $gradleContent -replace 'release\s*\{', "release {`r`n            isMinifyEnabled = false`r`n            isShrinkResources = false"
        } elseif ($gradleContent -match 'buildTypes\s*\{') {
            $gradleContent = $gradleContent -replace 'buildTypes\s*\{', "buildTypes {`r`n        release {`r`n            isMinifyEnabled = false`r`n            isShrinkResources = false`r`n            signingConfig = signingConfigs.getByName(`"debug`")`r`n        }"
        } else {
            $gradleContent = $gradleContent -replace '(?s)(android\s*\{.*?defaultConfig\s*\{.*?\n\s*\})', "`$1`r`n`r`n    buildTypes {`r`n        release {`r`n            isMinifyEnabled = false`r`n            isShrinkResources = false`r`n            signingConfig = signingConfigs.getByName(`"debug`")`r`n        }`r`n    }"
        }
    }

    return Add-TextRecognitionDependenciesKts $gradleContent
}

function Force-NoReleaseShrinkGroovy($gradleContent) {
    $gradleContent = $gradleContent.Replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')

    if ($gradleContent.Contains('minifyEnabled true')) {
        $gradleContent = $gradleContent.Replace('minifyEnabled true', 'minifyEnabled false')
    }
    if ($gradleContent.Contains('shrinkResources true')) {
        $gradleContent = $gradleContent.Replace('shrinkResources true', 'shrinkResources false')
    }

    if (-not $gradleContent.Contains('minifyEnabled false')) {
        if ($gradleContent -match 'release\s*\{') {
            $gradleContent = $gradleContent -replace 'release\s*\{', "release {`r`n            minifyEnabled false`r`n            shrinkResources false"
        } elseif ($gradleContent -match 'buildTypes\s*\{') {
            $gradleContent = $gradleContent -replace 'buildTypes\s*\{', "buildTypes {`r`n        release {`r`n            minifyEnabled false`r`n            shrinkResources false`r`n            signingConfig signingConfigs.debug`r`n        }"
        } else {
            $gradleContent = $gradleContent -replace '(?s)(android\s*\{.*?defaultConfig\s*\{.*?\n\s*\})', "`$1`r`n`r`n    buildTypes {`r`n        release {`r`n            minifyEnabled false`r`n            shrinkResources false`r`n            signingConfig signingConfigs.debug`r`n        }`r`n    }"
        }
    }

    return Add-TextRecognitionDependenciesGroovy $gradleContent
}

$gradleKtsPath = Join-Path $PSScriptRoot "..\android\app\build.gradle.kts"
$gradleGroovyPath = Join-Path $PSScriptRoot "..\android\app\build.gradle"

if (Test-Path $gradleKtsPath) {
    $gradleContent = Get-Content $gradleKtsPath -Raw
    $gradleContent = Force-NoReleaseShrinkKts $gradleContent
    Set-Content -Path $gradleKtsPath -Value $gradleContent -Encoding UTF8
} elseif (Test-Path $gradleGroovyPath) {
    $gradleContent = Get-Content $gradleGroovyPath -Raw
    $gradleContent = Force-NoReleaseShrinkGroovy $gradleContent
    Set-Content -Path $gradleGroovyPath -Value $gradleContent -Encoding UTF8
} else {
    throw "build.gradle introuvable dans android/app."
}

Write-Host "Configuration Android appliquee (camera + GPS + minSdk 24 + ML Kit scripts + release sans R8)." -ForegroundColor Green
