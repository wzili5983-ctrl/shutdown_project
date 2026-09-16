$ErrorActionPreference = 'Stop'
$nightTask = 'DailyPower_Night'
$wakeTask = 'DailyPower_Wake'

function Read-Time([string]$prompt) {
    while ($true) {
        $value = Read-Host $prompt
        if ($value -cmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$') {
            return [datetime]::Today.Add([timespan]::Parse($value))
        }
        Write-Host 'Enter a 24-hour time, for example 23:00 or 07:30.'
    }
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Right-click DailyPower.bat and select Run as administrator.'
    }
    :MainMenu while ($true) {
        try {
            Write-Host ''
            Write-Host '1. Daily SHUTDOWN (power-on must be configured in BIOS/UEFI)'
            Write-Host '2. Daily SLEEP and scheduled WAKE (requires hardware support)'
            Write-Host '3. Remove schedules created by this script'
            Write-Host '4. Show schedules'
            Write-Host '5. Cancel a pending shutdown'
            Write-Host '0. Exit'
            $choice = Read-Host 'Choose'
            switch ($choice) {
                '0' { return }
                '3' {
                    foreach ($name in @($nightTask, $wakeTask)) {
                        if (Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue) {
                            Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false
                        }
                    }
                    Write-Host 'Schedules removed. A shutdown already counting down must be cancelled with option 5.'
                    continue MainMenu
                }
                '4' {
                    Get-ScheduledTask -TaskName 'DailyPower_*' -TaskPath '\' -ErrorAction SilentlyContinue |
                        Select-Object TaskName, State | Format-Table -AutoSize
                    continue MainMenu
                }
                '5' {
                    & "$env:SystemRoot\System32\shutdown.exe" /a
                    continue MainMenu
                }
                '1' { $mode = 'shutdown' }
                '2' { $mode = 'sleep' }
                default { throw 'Invalid choice. No changes made.' }
            }
    
            $night = Read-Time 'Daily shutdown/sleep time (HH:mm)'
            if ($mode -eq 'sleep') {
                $wake = Read-Time 'Daily wake time (HH:mm)'
                if ($night -eq $wake) { throw 'Sleep and wake times must differ.' }
            }
            Write-Host "Mode: $mode; daily night time: $($night.ToString('HH:mm'))"
            if ($mode -eq 'sleep') {
                Write-Host "Daily wake time: $($wake.ToString('HH:mm'))"
                Write-Host 'Enable wake timers in Windows power options. Sleep/wake support depends on your PC.'
            } else {
                Write-Host 'WARNING: shutdown uses a 60-second countdown, which can forcibly close apps.'
                Write-Host 'Save your work before the scheduled time. Windows cannot power on a fully shut-down PC.'
            }
            if ((Read-Host 'Type YES to install/replace these schedules') -cne 'YES') {
                Write-Host 'Cancelled. No changes made.'
                continue MainMenu
            }
    
            $account = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            # Do not run missed triggers at next startup; do not wake the PC just to shut it down.
            $nightSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
            if ($mode -eq 'shutdown') {
                $nightAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\shutdown.exe" -Argument '/s /t 60'
            } else {
                # Embed the command in the task so moving this folder cannot break the schedule.
                $sleepCode = 'Add-Type -AssemblyName System.Windows.Forms; if (-not [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false)) { exit 1 }'
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($sleepCode))
                $nightAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -EncodedCommand $encoded"
                $wakeSettings = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
                $wakeAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument '/c exit 0'
                Register-ScheduledTask -TaskName $wakeTask -TaskPath '\' -Action $wakeAction -Trigger (New-ScheduledTaskTrigger -Daily -At $wake) -Settings $wakeSettings -Principal $account -Force | Out-Null
            }
            Register-ScheduledTask -TaskName $nightTask -TaskPath '\' -Action $nightAction -Trigger (New-ScheduledTaskTrigger -Daily -At $night) -Settings $nightSettings -Principal $account -Force | Out-Null
            if ($mode -eq 'shutdown' -and (Get-ScheduledTask -TaskName $wakeTask -TaskPath '\' -ErrorAction SilentlyContinue)) {
                Unregister-ScheduledTask -TaskName $wakeTask -TaskPath '\' -Confirm:$false
            }
            Write-Host 'Schedule installed. Times follow the Windows local clock. Returning to main menu.'
        } catch {
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host 'If installation failed partway through, use option 4 to inspect or option 3 to remove schedules.'
        }
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'If installation failed partway through, use option 4 to inspect or option 3 to remove schedules.'
    exit 1
}
