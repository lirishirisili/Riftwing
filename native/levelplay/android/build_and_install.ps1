# Builds the RIFTSTRIKE LevelPlay Godot Android v2 plugin AAR and installs it
# (plus the .gdap descriptor) into res://android/plugins so the Godot gradle
# export picks it up. Run from anywhere:
#   pwsh native/levelplay/android/build_and_install.ps1
#
# Requires: JDK 17 on PATH/JAVA_HOME, internet access (Maven Central + Google),
# and the Godot Android build template already installed (res://android/build).

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..\..")
$pluginsDir = Join-Path $repoRoot "android\plugins"
$distDir = Join-Path $scriptDir "dist"

Write-Host "== Building LevelPlay plugin AAR (release) =="
Push-Location $scriptDir
try {
    # Reuse the Godot template's Gradle wrapper if this project has none.
    $gradlew = Join-Path $scriptDir "gradlew.bat"
    if (-not (Test-Path $gradlew)) {
        $templateWrapper = Join-Path $repoRoot "android\build\gradlew.bat"
        if (Test-Path $templateWrapper) {
            Copy-Item $templateWrapper $gradlew -Force
            Copy-Item (Join-Path $repoRoot "android\build\gradlew") (Join-Path $scriptDir "gradlew") -Force
            New-Item -ItemType Directory -Force -Path (Join-Path $scriptDir "gradle\wrapper") | Out-Null
            Copy-Item (Join-Path $repoRoot "android\build\gradle\wrapper\gradle-wrapper.jar") (Join-Path $scriptDir "gradle\wrapper\gradle-wrapper.jar") -Force
            Copy-Item (Join-Path $repoRoot "android\build\gradle\wrapper\gradle-wrapper.properties") (Join-Path $scriptDir "gradle\wrapper\gradle-wrapper.properties") -Force
        }
    }
    & $gradlew ":plugin:assembleRelease" --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Gradle build failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$aar = Join-Path $scriptDir "plugin\build\outputs\aar\RiftstrikeLevelPlay.release.aar"
if (-not (Test-Path $aar)) { throw "AAR not found at $aar" }

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Copy-Item $aar (Join-Path $distDir "RiftstrikeLevelPlay.aar") -Force

New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null
Copy-Item (Join-Path $distDir "RiftstrikeLevelPlay.aar") (Join-Path $pluginsDir "RiftstrikeLevelPlay.aar") -Force
Copy-Item (Join-Path $distDir "RiftstrikeLevelPlay.gdap") (Join-Path $pluginsDir "RiftstrikeLevelPlay.gdap") -Force

Write-Host "== Installed plugin to $pluginsDir =="
Get-ChildItem $pluginsDir | Select-Object Name, Length
