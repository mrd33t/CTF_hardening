# ===============================# PvJ CTF Continuous Defense Script (Windows)# ===============================# Run as Administrator# Configuration lists
$ApprovedServices = @("Dnscache", "W32Time", "TermService", "Netlogon") # Update as needed
$ApprovedAdminUsers = @("Administrator", "CTFAdmin") # Update your allowed admins# Optional: Set up alert email (SMTP must be allowed & configured)
$EMailAlerts = $false
$EmailTo = "YOURTEAM@EXAMPLE.COM"
$SMTPServer = "smtp.example.com"

Function Send-Alert($subject, $body) {
    if ($EMailAlerts) {
        Send-MailMessage -To $EmailTo -From $EmailTo -Subject $subject -Body $body -SmtpServer $SMTPServer
    }
    Write-Host "ALERT: $subject $body"
}

# Continuous defense loop
while ($true) {
    Write-Host "`n[ $(Get-Date) ] Starting Blue Team Defense Check..."

    # 1. Patch System
    Try {
        Import-Module PSWindowsUpdate
        Get-WindowsUpdate -Install -AcceptAll -AutoReboot
        Write-Host "[*] Windows patching complete."
    } Catch { Write-Host "[!] Patch module not found or error." }

    # 2. Firewall Enforce/Reset
    netsh advfirewall set allprofiles state on
    netsh advfirewall reset
    Write-Host "[*] Firewall enforced and reset."

    # 3. Port/Service Audit
    $RunningServices = Get-Service | Where-Object {$_.Status -eq 'Running'} | Select-Object -ExpandProperty Name
    $UnapprovedServices = $RunningServices | Where-Object { $ApprovedServices -notcontains $_ }
    if ($UnapprovedServices) {
        $msg = "Unapproved running services: $($UnapprovedServices -join ', ')"
        Send-Alert "Unapproved Services Found" $msg
    } else {
        Write-Host "[*] No unapproved services running."
    }

    # 4. Open Ports Audit
    $AllowedPorts = @(22, 80, 443) # Update as needed
    $ListeningPorts = Get-NetTCPConnection -State Listen | Select-Object -ExpandProperty LocalPort | Sort-Object -Unique
    $UnexpectedPorts = $ListeningPorts | Where-Object { $AllowedPorts -notcontains $_ }
    if ($UnexpectedPorts) { 
        Send-Alert "Unexpected Listening Ports" "Ports: $($UnexpectedPorts -join ', ')" 
    }

    # 5. Account/Admin Audit
    $Admins = Get-LocalGroupMember -Group 'Administrators' | Select-Object -ExpandProperty Name
    $ExtraAdmins = $Admins | Where-Object { $ApprovedAdminUsers -notcontains $_ }
    if ($ExtraAdmins) {
        Send-Alert "Unapproved Administrators" "Users: $($ExtraAdmins -join ', ')"
    } else {
        Write-Host "[*] No unapproved admins detected."
    }

    # 6. Event Log Monitoring (brute-force, user creation, etc.)
    $SuspiciousEventIds = @(4625, 4720, 4722, 4723, 4732, 4740) # Add more as needed
    $SuspiciousEvents = Get-WinEvent -LogName Security -MaxEvents 50 | Where-Object { $SuspiciousEventIds -contains $_.Id }
    if ($SuspiciousEvents) {
        $msg = $SuspiciousEvents | Select-Object -First 5 | ForEach-Object { "$($_.TimeCreated) $($_.Message)" } | Out-String
        Send-Alert "Suspicious Logon or User Activity" $msg
    }

    # 7. Config file hash baseline alert (e.g., for RDP config)
    $ConfigFile = "C:\Windows\System32\GroupPolicy\Machine\Registry.pol"
    if (Test-Path $ConfigFile) {
        $HashFile = "C:\ctf_gp_hash.txt"
        $CurrentHash = (Get-FileHash $ConfigFile).Hash
        if (Test-Path $HashFile) {
            $LastHash = Get-Content $HashFile
            if ($CurrentHash -ne $LastHash) {
                Send-Alert "Registry Policy Changed" "File: $ConfigFile"
            }
        }
        $CurrentHash | Set-Content $HashFile
    }

    # 8. Backup/Snapshot Reminder
    Write-Host "[*] Backup/snapshot as needed!"

    Write-Host "[ $(Get-Date) ] Blue Team Loop Complete. Sleeping 15min..."
    Start-Sleep -Seconds 900  # 15 minutes
}
