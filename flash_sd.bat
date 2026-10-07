@echo off
:: Batch script to write FreeDOS image to SD card with Admin rights
:: Request admin privileges
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
pushd "%CD%"
CD /D "%~dp0"

powershell -ExecutionPolicy Bypass -NoProfile -Command " & { $img = Join-Path (Get-Location) 'FDOS-128M.img'; $zip = Join-Path (Get-Location) 'FDOS-128M.zip'; if (!(Test-Path $img) -and (Test-Path $zip)) { Write-Host 'Extracting FDOS-128M.zip...' -ForegroundColor Cyan; Expand-Archive -Path $zip -DestinationPath (Split-Path $img) -Force }; if (!(Test-Path $img)) { Write-Host 'Image not found!' -ForegroundColor Red; pause; exit 1 }; $disk = Get-Disk | Where-Object { $_.Number -gt 0 -and ($_.FriendlyName -match 'Card Reader|Realtek|SD|Storage|USB' -or $_.Bustype -eq 'USB') -and $_.Size -gt 10000000000 -and $_.Size -lt 64000000000 }; if (!$disk) { Write-Host 'SD card not found! Please insert it.' -ForegroundColor Red; pause; exit 1 }; if ($disk.Count -gt 1) { Write-Host 'Multiple SD cards found. Please leave only one inserted.' -ForegroundColor Red; pause; exit 1 }; Write-Host \"Target: Disk $($disk.Number) ($($disk.FriendlyName), $([math]::Round($disk.Size / 1GB, 2)) GB)\" -ForegroundColor Green; Write-Host \"WARNING: THIS WILL ERASE ALL DATA ON THIS DISK!\" -ForegroundColor Yellow; $confirm = Read-Host 'Type YES to continue'; if ($confirm -cne 'YES') { Write-Host 'Aborted.' -ForegroundColor Red; pause; exit 1 }; try { Clear-Disk -Number $disk.Number -RemoveData -Confirm:$false -ErrorAction SilentlyContinue; $src = [System.IO.File]::OpenRead($img); $dst = [System.IO.File]::Open(\"\\.\PhysicalDrive$($disk.Number)\", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite); $buf = New-Object byte[] (1024 * 1024); $total = $src.Length; $written = 0; while (($read = $src.Read($buf, 0, $buf.Length)) -gt 0) { $dst.Write($buf, 0, $read); $written += $read; Write-Progress -Activity 'Writing FreeDOS to SD card' -Status \"$([math]::Round($written/1MB)) MB / $([math]::Round($total/1MB)) MB\" -PercentComplete (($written / $total) * 100) }; $dst.Flush(); $dst.Close(); $src.Close(); Update-Disk -Number $disk.Number -ErrorAction SilentlyContinue; Write-Host 'SUCCESS! Image written.' -ForegroundColor Green; } catch { Write-Host \"ERROR: $_\" -ForegroundColor Red }; Write-Host 'Press Enter to exit.'; pause; }"

