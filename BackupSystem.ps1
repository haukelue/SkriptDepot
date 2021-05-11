function Backup-FolderTo() {
    param
    (
        [string]$source,
        [string]$destination,
        [string]$logpath = "",
        [string]$exclude = ""
    )

    $options = @()

    if ($logpath.Length -gt 0) {
        $datum = Get-Date -Format "yyyy-MM-dd"
        $logfile = Join-Path $logpath "Backup-${datum}.log"
        $options += '/UNILOG+:"' + ${logfile} + '"'
    }
    else {
        $options += "/NJH", "/NJS"
    }

    if ($exclude.Length -gt 0) {
        $options += "/XF", $exclude
    }

    robocopy.exe "${source}" "${destination}" /MIR /NP /TEE /XJ /NDL /R:5 /W:10 @options
}

function Backup-Programmconfigurations() {
    $profilePfad = "D:\Sonstiges\Profile"
    Backup-FolderTo (Join-Path $env:APPDATA "TS3Client") (Join-Path $profilePfad "TS3Client")
    Backup-FolderTo (Join-Path $env:APPDATA "XnViewMP") (Join-Path $profilePfad "XnViewMP")
    Backup-FolderTo (Join-Path $env:LOCALAPPDATA "Microsoft\SyncToy\2.0") (Join-Path $profilePfad "SyncToy")
    Backup-FolderTo (Join-Path $env:USERPROFILE ".vscode") (Join-Path $profilePfad ".vscode")
    Copy-Item (Join-Path $env:APPDATA WinSCP.ini) D:\Sonstiges\Profile\ -Force
}

function Restore-Programmconfigurations() {
    $profilePfad = "D:\Sonstiges\Profile"
    Backup-FolderTo (Join-Path $profilePfad "TS3Client") (Join-Path $env:APPDATA "TS3Client")
    Backup-FolderTo (Join-Path $profilePfad "XnViewMP") (Join-Path $env:APPDATA "XnViewMP")
    Backup-FolderTo (Join-Path $profilePfad "SyncToy") (Join-Path $env:LOCALAPPDATA "Microsoft\SyncToy\2.0")
    Backup-FolderTo (Join-Path $profilePfad ".vscode") (Join-Path $env:USERPROFILE ".vscode")
    Copy-Item D:\Sonstiges\Profile\WinSCP.ini $env:APPDATA -Force
}

function Backup-Full() {
    $BackupPfad = "B:\Backup"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Sonstiges" (Join-Path $BackupPfad "Sonstiges") $BackupPfad
        Backup-FolderTo "D:\OneDrive" (Join-Path $BackupPfad "OneDrive") $BackupPfad ".849C9593-D756-4E56-8D6E-42412F2A707B"
        Backup-FolderTo "D:\Programme" (Join-Path $BackupPfad "Programme") $BackupPfad
        Backup-FolderTo "D:\Gespeicherte Spiele" (Join-Path $BackupPfad "Gespeicherte Spiele") $BackupPfad
        Backup-FolderTo "D:\Downloads" (Join-Path $BackupPfad "Downloads") $BackupPfad
        Backup-FolderTo "D:\Desktop" (Join-Path $BackupPfad "Desktop") $BackupPfad
        Backup-FolderTo "D:\Bilder" (Join-Path $BackupPfad "Bilder") $BackupPfad
        Backup-FolderTo "D:\Dokumente" (Join-Path $BackupPfad "Dokumente") $BackupPfad
        Backup-FolderTo "D:\Musik" (Join-Path $BackupPfad "Musik") $BackupPfad
        Backup-FolderTo "D:\Lesestoff" (Join-Path $BackupPfad "Lesestoff") $BackupPfad
        Backup-FolderTo "D:\Spiele" (Join-Path $BackupPfad "Spiele") $BackupPfad
    }
    
    $BackupPfad = "A:\"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Sonstiges\Software" (Join-Path $BackupPfad "Software")
        Backup-FolderTo "D:\Programme" (Join-Path $BackupPfad "Programme")
    }
    
    $BackupPfad = "\\Schatzkiste\Backup"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Desktop" (Join-Path $BackupPfad "Desktop") $BackupPfad
        Backup-FolderTo "D:\Dokumente" (Join-Path $BackupPfad "Dokumente") $BackupPfad
        Backup-FolderTo "D:\Gespeicherte Spiele" (Join-Path $BackupPfad "Gespeicherte Spiele") $BackupPfad
        Backup-FolderTo "D:\Programme" (Join-Path $BackupPfad "Programme") $BackupPfad
        Backup-FolderTo "D:\Sonstiges" (Join-Path $BackupPfad "Sonstiges") $BackupPfad
        Backup-FolderTo "D:\Spiele" (Join-Path $BackupPfad "Spiele") $BackupPfad
    }
    
    $BackupPfad = "\\Schatzkiste\Multimedia"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Bilder" (Join-Path $BackupPfad "Bilder")
        Backup-FolderTo "D:\Lesestoff" (Join-Path $BackupPfad "Lesestoff")
        Backup-FolderTo "D:\Musik" (Join-Path $BackupPfad "Musik")
        # Offen: Videos
        robocopy.exe "D:\Videos" (Join-Path $BackupPfad "Videos") /NP /TEE /XJ /NDL /R:5 /W:10 /NJH /NJS
    }
}

function Get-MemoryValues() {
    $memoryInfo = Get-CimInstance CIM_OperatingSystem

    Write-Output $memoryInfo | Format-Table @{Name = "Name"; Expression = { $PSItem.CSName } }, @{Name = "Total Memory"; Expression = { "{0,6:N2} GB" -f ($PSItem.TotalVisibleMemorySize / 1MB) }; align = "right" }, @{Name = " Free Memory"; Expression = { "{0,6:N2} GB" -f ($PSItem.FreePhysicalMemory / 1MB) }; align = "right" } -AutoSize
}

function Get-DiskSpaceInfo() {
    $diskInfo = Get-CimInstance CIM_LogicalDisk | Where-Object DriveType -eq 3 | Sort-Object DeviceID

    Write-Output $diskInfo | Format-Table @{Label = "Laufwerk"; Expression = { $_.DeviceID } }, @{Label = "Total (GB)"; Expression = { "{0,6:N2}" -f ($PSItem.Size / 1GB) }; align = "right" }, @{Label = "Frei (GB)"; Expression = { "{0,6:N2}" -f ($PSItem.FreeSpace / 1GB) }; align = "right" }, @{Label = "Frei (%)"; Expression = { "{0,3:P0}" -f ($PSItem.FreeSpace / $PSItem.Size) }; align = "right" } -AutoSize
}

function Reset-Dns() {
    if (Test-IsAdmin) {
        ##Requires -RunAsAdministrator
        ipconfig /flushdns
        ipconfig /registerdns
        ipconfig /release
        ipconfig /renew
        NETSH winsock reset catalog
        NETSH int ipv4 reset reset.log
        NETSH int ipv6 reset reset.log
    }
    else {
        Write-Warning "Es werden Admin-Rechte für diesen Befehl benötigt."
    }
}

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

# Abfrage der auszuführenden Aktion
Clear-Host
$prevTitle = $host.ui.RawUI.WindowTitle
$host.ui.RawUI.WindowTitle = "Backupsteuerung & Systeminformationen"
Write-Output ""
Write-Output "1 - Programmeneinstellungen sichern"
Write-Output "2 - Programmeneinstellungen wiederherstellen"
Write-Output "3 - Volle Sicherung auf Backupplatte B:"
Write-Output ""
Write-Output "4 - Speicherauslastung"
Write-Output "5 - Festplattenauslastung"
Write-Output "6 - Reset DNS"
Write-Output ""
$auswahl = Read-Host "Auswahl"

switch ($Auswahl) {
    1 { Backup-Programmconfigurations }
    2 { Restore-Programmconfigurations }
    3 { Backup-Full }
    4 { Get-MemoryValues }
    5 { Get-DiskSpaceInfo }
    6 { Reset-Dns }
}

Write-Output "... any-key Taste ..."
[void][System.Console]::ReadKey($true)
$host.ui.RawUI.WindowTitle = $prevTitle
