function Backup-FolderTo {
    param
    (
        [Parameter(Mandatory=$true)][string]$source,
        [Parameter(Mandatory=$true)][string]$destination,
        [Parameter(Mandatory=$false)][string]$logpath = "",
        [Parameter(Mandatory=$false)][string]$excludeDirectories = "",
        [Parameter(Mandatory=$false)][string]$excludeFiles = ""
    )

    $options = @()

    if ($logpath.Length -gt 0) {
        $datum = Get-Date -Format "yyyy-MM-dd"
        $logfile = Join-Path $logpath "Backup-${datum}.log"
        $options += "/UNILOG+:${logfile}"
    }

    if ($excludeDirectories.Length -gt 0) {
        $options += "/XD", $excludeDirectories
    }

    if ($excludeFiles.Length -gt 0) {
        $options += "/XF", $excludeFiles
    }

    robocopy.exe "${source}" "${destination}" /MIR /NP /TEE /XJ /NDL /R:5 /W:10 @options
}

function Copy-FolderTo {
    param (
        [Parameter(Mandatory=$true)][string]$source,
        [Parameter(Mandatory=$true)][string]$destination
    )
    
    robocopy.exe "${source}" "${destination}" /NP /XJ /NDL /R:5 /W:10 /E /XX
}

function Backup-Programmconfigurations {
    $profilePfad = "D:\Sonstiges\Profile"
    Backup-FolderTo (Join-Path $env:APPDATA "XnViewMP") (Join-Path $profilePfad "XnViewMP")
    Backup-FolderTo (Join-Path $env:USERPROFILE ".vscode") (Join-Path $profilePfad ".vscode")
    Copy-Item (Join-Path $env:APPDATA WinSCP.ini) D:\Sonstiges\Profile\ -Force
}

function Restore-Programmconfigurations {
    $profilePfad = "D:\Sonstiges\Profile"
    Backup-FolderTo (Join-Path $profilePfad "XnViewMP") (Join-Path $env:APPDATA "XnViewMP")
    Backup-FolderTo (Join-Path $profilePfad ".vscode") (Join-Path $env:USERPROFILE ".vscode")
    Copy-Item D:\Sonstiges\Profile\WinSCP.ini $env:APPDATA -Force
}

function Backup-Full {
    Backup-ToStick
    Backup-ToDisk
    Backup-ToNAS
}

function Backup-ToStick {
    $BackupPfad = "A:\"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Software" (Join-Path $BackupPfad "Software")
        Backup-FolderTo "D:\Programme" (Join-Path $BackupPfad "Programme")
    }
}

function Backup-ToDisk {
    $BackupPfad = "B:\Backup"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Sonstiges" (Join-Path $BackupPfad "Sonstiges") $BackupPfad
        Backup-FolderTo "D:\Software" (Join-Path $BackupPfad "Software") $BackupPfad
        Backup-FolderTo "D:\OneDrive" (Join-Path $BackupPfad "OneDrive") $BackupPfad -excludeFiles ".849C9593-D756-4E56-8D6E-42412F2A707B"
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
}

function Backup-ToNAS {
    $BackupPfad = "\\Schatzkiste\Public"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Software" (Join-Path $BackupPfad "Software")
    }

    $BackupPfad = "\\Schatzkiste\home"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Desktop" (Join-Path $BackupPfad "Desktop") $BackupPfad
        Backup-FolderTo "D:\Dokumente" (Join-Path $BackupPfad "Dokumente") $BackupPfad
        Backup-FolderTo "D:\Gespeicherte Spiele" (Join-Path $BackupPfad "Gespeicherte Spiele") $BackupPfad
        Backup-FolderTo "D:\Programme" (Join-Path $BackupPfad "Programme") $BackupPfad
        Backup-FolderTo "D:\Sonstiges" (Join-Path $BackupPfad "Sonstiges") $BackupPfad
        Backup-FolderTo "D:\Spiele" (Join-Path $BackupPfad "Spiele") $BackupPfad
        Backup-FolderTo "D:\Downloads" (Join-Path $BackupPfad "Downloads") $BackupPfad
    }

    $BackupPfad = "\\Schatzkiste\Multimedia"
    if (Test-Path $BackupPfad) {
        Backup-FolderTo "D:\Bilder" (Join-Path $BackupPfad "Bilder")
        Backup-FolderTo "D:\Lesestoff" (Join-Path $BackupPfad "Lesestoff")
        Backup-FolderTo "D:\Musik" (Join-Path $BackupPfad "Musik")
        Copy-FolderTo "D:\Videos" (Join-Path $BackupPfad "Videos")
    }
}

function Backup-MarieFromNAS {
    $BackupPfadB = "B:\Marie"
    $BackupPfadM = "M:\Marie"
    if (Test-Path $BackupPfadB) {
        Backup-FolderTo "\\Schatzkiste\Public\Marie" $BackupPfadB
    }
    if ((Test-Path $BackupPfadB) -and (Test-Path $BackupPfadM)) {
        Backup-FolderTo $BackupPfadB $BackupPfadM
    }
    elseif (Test-Path $BackupPfadM) {
        Backup-FolderTo "\\Schatzkiste\Public\Marie" $BackupPfadM
    }
}

function Get-MemoryValues {
    $memoryInfo = Get-CimInstance CIM_OperatingSystem

    Write-Output $memoryInfo | Format-Table @{Name = "Name"; Expression = { $PSItem.CSName } }, @{Name = "Total Memory"; Expression = { "{0,6:N2} GB" -f ($PSItem.TotalVisibleMemorySize / 1MB) }; align = "right" }, @{Name = " Free Memory"; Expression = { "{0,6:N2} GB" -f ($PSItem.FreePhysicalMemory / 1MB) }; align = "right" } -AutoSize
}

function Get-DiskSpaceInfo {
    $diskInfo = Get-CimInstance CIM_LogicalDisk | Where-Object DriveType -eq 3 | Sort-Object DeviceID

    Write-Output $diskInfo | Format-Table @{Label = "Laufwerk"; Expression = { $_.DeviceID } }, @{Label = "Total (GB)"; Expression = { "{0,6:N2}" -f ($PSItem.Size / 1GB) }; align = "right" }, @{Label = "Frei (GB)"; Expression = { "{0,6:N2}" -f ($PSItem.FreeSpace / 1GB) }; align = "right" }, @{Label = "Frei (%)"; Expression = { "{0,3:P0}" -f ($PSItem.FreeSpace / $PSItem.Size) }; align = "right" } -AutoSize
}

function Reset-Dns {
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
Write-Output "3 - Sicherung: A:\, B:\ und NAS"
Write-Output "4 - Sicherung: A:\"
Write-Output "5 - Sicherung: B:\"
Write-Output "6 - Sicherung: NAS"
Write-Output "m - Sicherung Marie: NAS auf B:\ und M:\"
Write-Output ""
Write-Output "7 - Speicherauslastung"
Write-Output "8 - Festplattenauslastung"
Write-Output "9 - Reset DNS"
Write-Output ""
$Auswahl = Read-Host "Auswahl"

switch ($Auswahl.ToLowerInvariant()) {
    1 { Backup-Programmconfigurations }
    2 { Restore-Programmconfigurations }
    3 { Backup-Full }
    4 { Backup-ToStick }
    5 { Backup-ToDisk }
    6 { Backup-ToNAS }
    7 { Get-MemoryValues }
    8 { Get-DiskSpaceInfo }
    9 { Reset-Dns }
    m { Backup-MarieFromNAS }
}

Write-Output "... any-key Taste ..."
[void][System.Console]::ReadKey($true)
$host.ui.RawUI.WindowTitle = $prevTitle
