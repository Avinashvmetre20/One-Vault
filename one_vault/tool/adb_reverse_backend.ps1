$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    Write-Error "adb not found at $adb"
    exit 1
}

& $adb start-server | Out-Null
$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match 'device$' }
if (-not $devices) {
    Write-Error "No Android device connected. Plug in the phone with USB debugging on."
    exit 1
}

& $adb reverse tcp:3000 tcp:3000
Write-Host "Phone localhost:3000 now tunnels to this PC backend."
& $adb reverse --list
