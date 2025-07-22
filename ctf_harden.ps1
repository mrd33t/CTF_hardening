# ======================
# Windows CTF Hardening Script WITH Password Logging
# ======================
# Run as Administrator!

# File to save new passwords (readable by admins)
$pwFile = "C:\ctf_pw_reset.txt"
"" | Set-Content $pwFile  # Clean previous

# 1. Set password policy
secedit /export /cfg C:\secpol.cfg
(gc C:\secpol.cfg) -replace 'MinimumPasswordLength = \d+', 'MinimumPasswordLength = 12' | Out-File C:\secpol.cfg
(gc C:\secpol.cfg) -replace 'PasswordComplexity = \d+', 'PasswordComplexity = 1' | Out-File C:\secpol.cfg
secedit /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY

# 2. Change all local account passwords, LOG them
Get-LocalUser | Where-Object { $_.Enabled -eq $true } | ForEach-Object {
    $randpw = -join ((33..126) | Get-Random -Count 16 | % {[char]$_})
    $_ | Set-LocalUser -Password (ConvertTo-SecureString $randpw -AsPlainText -Force)
    "$($_.Name): $randpw" | Add-Content $pwFile
}

# 3. Disable Guest and Defaultaccount users
$toDisable = @("Guest","DefaultAccount")
foreach ($user in $toDisable) {
    If (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Disable-LocalUser -Name $user
        Add-Content $pwFile "$user: DISABLED"
    }
}

# 4. Disable RDP
# Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1

# 5. Enable Windows Firewall in all profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# 6. Disable unnecessary services (Telnet, RemoteRegistry, SMBv1)
$disableServices = @("Telnet","RemoteRegistry")
foreach ($svc in $disableServices) {
    if (Get-Service $svc -ErrorAction SilentlyContinue) {
        Stop-Service $svc -Force
        Set-Service $svc -StartupType Disabled
    }
}

# 7. Disable SMBv1 (if applicable)
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

# 8. Apply pending updates if any, force reboot
# (Optionally: Uncomment after PSWindowsUpdate is installed)
# Install-WindowsUpdate -AcceptAll -AutoReboot

# 9. Turn on basic auditing
auditpol /set /category:* /success:enable /failure:enable

Write-Host "`n==> New passwords are saved in $pwFile <==`n"
Write-Host "Windows CTF Baseline Hardening Applied!"
