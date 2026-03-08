param(
    [switch]$KillJava,
    [switch]$SkipClean
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..')
Set-Location $repoRoot

Write-Host "Repo: $repoRoot"

if ($KillJava) {
    Write-Host 'Killing java.exe processes to release locked Gradle files...'
    try {
        taskkill /F /IM java.exe /T | Out-Null
    } catch {
        Write-Host 'No java.exe process needed to kill.'
    }
}

Write-Host 'Stopping Gradle daemons...'
Push-Location (Join-Path $repoRoot 'android')
try {
    .\gradlew.bat --stop | Out-Host
} finally {
    Pop-Location
}

if (-not $SkipClean) {
    Write-Host 'Removing Flutter/Gradle build directories...'
    $pathsToDelete = @(
        (Join-Path $repoRoot 'build'),
        (Join-Path $repoRoot 'android\app\build'),
        (Join-Path $repoRoot '.dart_tool')
    )

    foreach ($p in $pathsToDelete) {
        if (Test-Path $p) {
            try {
                Remove-Item -Recurse -Force $p
                Write-Host "Deleted: $p"
            } catch {
                Write-Warning "Could not delete $p. Trying cmd rmdir..."
                cmd /c "rmdir /s /q \"$p\"" | Out-Null
            }
        }
    }

    Write-Host 'Running flutter clean...'
    flutter clean | Out-Host
}

Write-Host 'Running flutter pub get...'
flutter pub get | Out-Host

Write-Host 'Building release APK...'
flutter build apk --release | Out-Host

$apkPath = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path $apkPath) {
    $sizeMb = [math]::Round((Get-Item $apkPath).Length / 1MB, 2)
    Write-Host "APK built successfully: $apkPath ($sizeMb MB)"
} else {
    throw 'Build finished but APK was not found at expected path.'
}
