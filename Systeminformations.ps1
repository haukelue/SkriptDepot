<#PSScriptInfo
.VERSION 1.13.0
.GUID F93B53EC-E907-4DFA-871E-6F0BE553A26B
.AUTHOR Hauke Lüneburg
.COMPANYNAME Fielmann
.COPYRIGHT 2018 Fielmann
.TAGS
.LICENSEURI
.PROJECTURI http://0002-cvsp01.fielmann.net/Bonobo.Git.Server/Repository/Detail/a40d2d19-85ea-4943-8ea2-71b276825703
.ICONURI
.EXTERNALMODULEDEPENDENCIES PSParallel
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
1.0.0   Initiale Version
1.1.0   Server OS lässt sich ermitteln; Installierte Fielmann-Services lassen sich ermitteln
1.2.0   Fügt Kommandozeilenparameter hinzu
1.3.0   Überprüft die Existenz des ADM-Users, bevor dieser verwendet wird.
1.4.0   Fügt eine Abfrage der installierten PS-Version hinzu
1.4.1   Entfernt debugging ausgabe und behebt einen Schreibfehler
1.5.0   Stellt die Abfrage der installierten Services auf eine PS 2.0 kompatibles Abfrage um.
1.6.0   Fügt PSScriptInfo hinzu.
1.7.0   Die Abfrage der installierten Services wieder auf PS > 2.0 umgestellt.
1.8.0   Fügt eine Abfrage für die CPU-Auslastung der Server hinzu.
        Die Liste der Server wird nun über eine Funktion ermittelt. Diese prüft im Vorfeld die Erreichbarkeit aller Server.
        Fügt Dokumentation den übergeordneten Funktionen hinzu.
1.9.0   Fügt die Abfrage der .NET Version auf den Servern hinzu.
1.10.0  Fügt eine Validierung der adm-Credetials hinzu.
        Dokumentation erweitert.
        Abfrage der installierten Applications in den IIS-Servern hinzugefügt.
1.11.0  Stellt einzelne Elemente auf Invoke-Parallel um.
1.12.0  Stellt bis auf die AppPool-Abfrage alle Server-Abfragen auf Invoke-Parallel um.
        Fügt die ProgressActivity bei den Aufrufen von Invoke-Parallel hinzu.
        Verlagert die Ermittlung der URI für die AppPool-Abfrage in die Klasse VersionInfo.
1.13.0  Sämtliche Serverabfragen werden parallel ausgeführt (sofern das Modul vorhanden ist).
#>

<#
.DESCRIPTION
Ermittelt Systeminformationen über das lokale System, bzw. einer Liste von Servern.
Für die Abfrage der Server-Informationen wird eine Textdatei 'C:\Workspaces\Server.txt' erwartet mit eine einfachen Auflistung von Servernamen. Siehe dazu: Get-AvailableServer
Die Verarbeitung bei vielen Servern kann einige zeit in Anspruch nehmen. Die Abfragen werden parallelisiert, wenn das Modul 'PSParallel' installiert ist.
#>

<# Commandline Parameters #>
param($auswahl)

<# Felder #>
$canExecutedParallel = Get-Module -Name PSParallel -ListAvailable

<# .REGION
Übergeordnete Funktionen
#>

function New-AdmCredential()
{
    <#
    .SYNOPSIS
    Erstellt ein Objekt, mit dem man sich auf einem Server mit dem eigenen Fielmann-Admin-Account anmelden kann.
    .DESCRIPTION
    Aus dem Usernamen des aktuell angemeldeten Benutzers und dem Präfix "adm-" wird der Benutzername erstellt.
    Sollte es den dadurch entstandenen Benutzernamen im AD nicht geben, wird einer manuell abgefragt. Existiert dieser auch nicht, ist die Funktionsrückgabe $null.
    Zu diesem Benutzernamen wird durch eine sichere Eingabe das Passwort abgefragt.
    Wird kein Passwort angegeben wird die Verarbeitung abgebrochen und $null zurückgegeben.
    Mit dieser Kombination wird dann ein "System.Management.Automation.PSCredential"-Objekt erstellt und zurückgegeben.
    .EXAMPLE
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }    
    Invoke-Command -Credential $credential ...
    #>
    $AdmUserName = "adm-$env:USERNAME";
    if (!(Get-ADUser -Filter {SamAccountName -like $AdmUserName}))
    {
        $AdmUserName = Read-Host "Eingabe ADM-User";
        if (!(Get-ADUser -Filter {SamAccountName -like $AdmUserName}))
        {
            Write-Warning "Der angegebene Benutzername '" + $AdmUserName + "' konnte nicht gefunden werden.";
            return $null;
        }
    }
    $AdmPassword = Read-Host "ADM-Passwort für $AdmUserName" -AsSecureString;
    if ($AdmPassword.Length -eq 0)
    {
        Write-Warning "Es wurde kein Passwort angegeben. Die Verarbeitung wird abgebrochen.";
        return $null;
    }

    $credential = New-Object System.Management.Automation.PSCredential ($AdmUserName, $AdmPassword);
    if (Test-Credential($credential))
    {
        return $credential;
    } else {
        Write-Warning "Das Passwort ist falsch oder der Account ist gesperrt. Die Verarbeitung wird abgebrochen.";
        return $null;
    }
}

function Test-Credential()
{
    <#
    .SYNOPSIS
    Überprüft ob eine Kombination von Benutzername und Passwort korrekt ist.
    .DESCRIPTION
    Ein Objekt vom Typ System.Management.Automation.PSCredential wird auf korrektheit überprüft.
    Dazu wird eine Verbindung zur aktuellen Domäne hergestellt und eine Verbindung mit den Credentials aufgebaut.
    Aufbauend auf folgende Information: https://serverfault.com/questions/276098/check-if-user-password-input-is-valid-in-powershell-script/276106
    .INPUTS
    System.Management.Automation.PSCredential
    .OUTPUTS
    System.Boolean
    .PARAMETER Credential
    Die zu überprüfenden Anmeldeinformationen vom Typ System.Management.Automation.PSCredential.
    .EXAMPLE
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $Password);
    if (Test-Credential($credential)) {...}
    .Example
    PS C:\> Test-Credential -Credential (Get-Credential)
    True
    #>
    param(
        [Parameter(Mandatory = $true)]
        [Alias('PSCredential')]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        $Credential
    )
   
    # Get current domain using logged-on user's credentials
    $CurrentDomain = "LDAP://" + ([ADSI]"").distinguishedName;
    $domain = New-Object System.DirectoryServices.DirectoryEntry(
        $CurrentDomain,
        $Credential.UserName,
        $Credential.GetNetworkCredential().Password);
   
    return $null -ne $domain.Name;
}

function Get-AvailableServer()
{
    <#
    .SYNOPSIS
    Gibt eine Liste von verfügbaren Servern zurück.
    .DESCRIPTION
    Ließt die Textdatei 'C:\Workspaces\Server.txt' aus (einfache Auflistung von Servernamen).
    Die Server werden anhand des Namens auf Erreichbarkeit überprüft.
    Ist ein Server aus der Liste erreichbar, wird dessen Name zurückgegeben.
    .EXAMPLE
    Get-WmiObject Win32_LogicalDisk -Filter DriveType=3 -ComputerName (Get-AvailableServer)
    .EXAMPLE
    Invoke-Command -ComputerName (Get-AvailableServer) ...
    #>
    $serverListe = ${C:\Workspaces\Server.txt};

    if ($canExecutedParallel)
    {
        $serverListe | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand {
            if(Test-Connection -ComputerName $PSItem -Count 1 -Quiet)
            {
                $PSItem
            }
        }
    } else {
        foreach ($server in $serverListe)
        {
            if (Test-Connection -ComputerName $server -Count 1 -Quiet)
            {
                $server;
            }
        }
    }
}

<# .REGION
Kapselung der Auswahl der abfragbaren Systeminformationen.
#>

function Get-LocalMemoryValues()
{
    $localMemoryInformation = Get-CimInstance CIM_OperatingSystem

    Write-Output $localMemoryInformation | Format-Table @{Name="Total Memory"; Expression={"{0,6:N2} GB" -f ($PSItem.TotalVisibleMemorySize / 1MB)}; align="right"}, @{Name=" Free Memory"; Expression={"{0,6:N2} GB" -f ($PSItem.FreePhysicalMemory / 1MB)}; align="right"} -AutoSize
}

function Get-ServerMemoryValues()
{
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }
    $scriptBlock = { Get-WmiObject Win32_OperatingSystem }

    if ($canExecutedParallel)
    {
        $serverMemoryInformations = Get-AvailableServer | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock } -ErrorAction Stop
    } else {
        $serverMemoryInformations = Invoke-Command -Credential $credential -ComputerName (Get-AvailableServer) -ScriptBlock $scriptBlock -ErrorAction Stop
    }

    Write-Output $serverMemoryInformations | Sort-Object CSName | Format-Table @{Name="Name"; Expression={$PSItem.CSName}}, @{Name="Total Memory"; Expression={"{0,6:N2} GB" -f ($PSItem.TotalVisibleMemorySize / 1MB)}; align="right"}, @{Name=" Free Memory"; Expression={"{0,6:N2} GB" -f ($PSItem.FreePhysicalMemory / 1MB)}; align="right"} -AutoSize
}

function Get-LocalDiskSpaceInfo()
{
    $localDiskSpaceInformation = Get-CimInstance CIM_LogicalDisk | Where-Object DriveType -eq 3 | Sort-Object DeviceID

    Write-Output $localDiskSpaceInformation | Format-Table @{Label = "Laufwerk"; Expression = {$PSItem.DeviceID}}, @{Label = "Total (GB)"; Expression = {"{0,6:N2}" -f ($PSItem.Size / 1GB)}; align = "right"}, @{Label = "Frei (GB)"; Expression = {"{0,6:N2}" -f ($PSItem.FreeSpace / 1GB)}; align = "right"}, @{Label = "Frei (%)"; Expression = {"{0,3:P0}" -f ($PSItem.FreeSpace / $PSItem.Size)}; align = "right"} -AutoSize
}

function Get-ServerDiskSpaceInfo()
{
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }
    $scriptBlock = { Get-WmiObject Win32_LogicalDisk -Filter DriveType=3 }

    if ($canExecutedParallel)
    {
        $serverDiskSpaceInformations = Get-AvailableServer | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock } -ErrorAction Stop
    } else {
        $serverDiskSpaceInformations = Invoke-Command -Credential $credential -ComputerName (Get-AvailableServer) -ScriptBlock $scriptBlock -ErrorAction Stop
    }

    Write-Output $serverDiskSpaceInformations | Sort-Object SystemName, DeviceID | Format-Table @{Name = "System         "; Expression = {$PSItem.SystemName}}, @{Name = "Laufwerk"; Expression = {$PSItem.DeviceID}}, @{Name = "Größe (GB)"; Expression = {"{0,6:N2}" -f ($PSItem.Size / 1GB)}; align = "right"}, @{Name = "Frei (GB)"; Expression = {"{0,6:N2}" -f ($PSItem.FreeSpace/1GB)}; align = "right"}, @{Name = "Frei (%)"; Expression = {"{0,3:P0}" -f ($PSItem.FreeSpace/$PSItem.Size)}; align = "right"}
}

function Get-ServerCpuLoadInfo()
{
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }
    $scriptBlock = { Get-WmiObject win32_perfformatteddata_perfos_processor | Select-Object Name, PercentProcessorTime }

    if ($canExecutedParallel)
    {
        $serverCpuLoadInformations = Get-AvailableServer | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock } -ErrorAction Stop
    } else {
        $serverCpuLoadInformations = Invoke-Command -Credential $credential -ComputerName (Get-AvailableServer) -ScriptBlock $scriptBlock -ErrorAction Stop
    }

    Write-Output $serverCpuLoadInformations | Sort-Object PSComputerName, Name | Select-Object PSComputerName, Name, PercentProcessorTime | Format-Table
}

function Get-ServerOperatingSystem()
{
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }
    $scriptblock = { Get-WmiObject -class Win32_OperatingSystem }

    if ($canExecutedParallel)
    {
        $serverOperatingSystem = Get-AvailableServer | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock } -ErrorAction Stop
    } else {
        $serverOperatingSystem = Invoke-Command -Credential $credential -ComputerName (Get-AvailableServer) -ScriptBlock $scriptBlock -ErrorAction Stop
    }
    
    Write-Output $serverOperatingSystem | Sort-Object PSComputerName | Select-Object PSComputerName, Name | Format-Table -AutoSize
}

function Get-ServerInstalledFielmannServices()
{
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }

    # Software wird in unterschiedliche Registry-Verzeichnisse installiert.
    $scriptblock1 = { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object Publisher -eq 'Fielmann' | Where-Object DisplayName -Match 'Service' }
    $scriptBlock2 = { Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object Publisher -eq 'Fielmann' | Where-Object DisplayName -Match 'Service' }
    $server = Get-AvailableServer

    if ($canExecutedParallel)
    {
        $serverFielmannSoftware = $server | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock1 } -ErrorAction Stop
        $serverFielmannSoftware += $server | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock2 } -ErrorAction Stop
    } else {
        $serverFielmannSoftware = Invoke-Command -Credential $credential -ComputerName ($server) -ScriptBlock $scriptBlock1 -ErrorAction Stop
        $serverFielmannSoftware += Invoke-Command -Credential $credential -ComputerName ($server) -ScriptBlock $scriptBlock2 -ErrorAction Stop
    }
    
    Write-Output $serverFielmannSoftware | Sort-Object PSComputerName, DisplayName | Select-Object PSComputerName, DisplayName, DisplayVersion | Format-Table -AutoSize
}

function Get-LocalPowerShellVersion()
{
    $PSVersionTable
}

function Get-ServerPowerShellVersion()
{
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }
    
    if ($canExecutedParallel)
    {
        $versions = Get-AvailableServer | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock { $PSVersionTable.PSVersion } } -ErrorAction Stop
    } else {
        $versions = Invoke-Command -Credential $credential -ComputerName (Get-AvailableServer) -ScriptBlock { $PSVersionTable.PSVersion } -ErrorAction Stop
    }
    
    Write-Output $versions | Sort-Object PSComputerName | Format-Table -AutoSize @{Name="ComputerName   "; Expression={$PSItem.PSComputerName}}, @{Name="Version"; Expression={"{0}.{1}" -f $PSItem.Major, $PSItem.Minor}; align = "right"}
}

function Get-ServerdotNETVersion()
{
    # Die Ausgabe ist verwirrend, da die Version nicht vollständig die öffentlich genutzte Version wiederspiegelt. Mit der Release-Angabe kann die Version eindeutig bestimmt werden.
    # Genaue Dokumentation findet sich hier: https://docs.microsoft.com/en-us/dotnet/framework/migration-guide/how-to-determine-which-versions-are-installed
    
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }
    
    $scriptBlock = { Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -recurse | Get-ItemProperty -name Version,Release -EA 0 | Where-Object { $_.PSChildName -match 'Full'} | Select-Object Version, Release }
    
    if ($canExecutedParallel)
    {
        $versions = Get-AvailableServer | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock } -ErrorAction Stop
    } else {
        $versions = Invoke-Command -Credential $credential -ComputerName (Get-AvailableServer) -ScriptBlock $scriptBlock -ErrorAction Stop    
    }
    
    Write-Output $versions | Sort-Object PSComputerName | Select-Object PSComputerName, Version, Release | Format-Table -AutoSize
}

function Get-VersionOfInstalledIISApplications()
{
    $credential = New-AdmCredential
    if (!$credential)
    {
        return;
    }
       
    $scriptBlock = {
        # Nur Server mit installiertem IIS verarbeiten.
        if (Get-Service -Name 'W3SVC' -ErrorAction Ignore)
        {
            # Siehe dazu auch:
            # https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/ee790599(v=technet.10) 
            Import-Module WebAdministration
            Get-WebApplication
        }
    }

    if ($canExecutedParallel)
    {
        $versionInfoList = Get-AvailableServer | Invoke-Parallel -ProgressActivity $MyInvocation.MyCommand { Invoke-Command -Credential $credential -ComputerName $PSItem -ScriptBlock $scriptBlock } -ErrorAction Stop | Invoke-Parallel {
            Get-VersionInfo($PSItem)
        }
    } else {
        $versionInfoList = Invoke-Command -Credential $credential -ComputerName (Get-AvailableServer) -ScriptBlock $scriptBlock -ErrorAction Stop | ForEach-Object {
            Get-VersionInfo($PSItem)
        }
    }

    Write-Output $versionInfoList | Sort-Object ServerName, PoolName, VirtualPath | Out-GridView -Title "Versionen der installierten IIS Applications"
}

function Get-VersionInfo ($webAppObject) {
    # Die internen Zertifikate sind auf %servername%.fielmann.net ausgestellt.
    $uri = "https://" + $webAppObject.PSComputerName + ".fielmann.net" + $webAppObject.path + "/api/versioninfo"
    try
    {
        $restResponse = Invoke-RestMethod -Uri $uri -Method Get -ContentType "application/json" -TimeoutSec 2 -DisableKeepAlive
        $version = $restResponse.Version
    }
    catch
    {
        $version = "-"
    }

    [PSCustomObject] @{ ServerName = $webAppObject.PSComputerName; PoolName = $webAppObject.applicationPool; VirtualPath = $webAppObject.path; Version = $version }
}

<# .REGION
Abfrage der Benutzereingabe
#>

$prevTitle = $host.ui.RawUI.WindowTitle
$host.ui.RawUI.WindowTitle = "Systeminformationen"
if (!$auswahl)
{
    Write-Output ""
    Write-Output "-- Eigenes System"
    Write-Output " 1 - Speicherauslastung"
    Write-Output " 2 - Festplattenauslastung"
    Write-Output " 3 - PowerShell-Version"
    Write-Output ""
    Write-Output "-- Server"
    Write-Output " 4 - CPU-Auslastung"
    Write-Output " 5 - Speicherauslastung"
    Write-Output " 6 - Festplattenauslastung"
    Write-Output " 7 - Betriebssystem"
    Write-Output " 8 - Installierte Fielmann-Services"
    Write-Output " 9 - PowerShell-Version"
    Write-Output "10 - .NET-Version"
    Write-Output "11 - Versionen der installierten IIS Applications (via REST über api/versioninfo)"
    Write-Output ""
    $auswahl = Read-Host "Auswahl"
}

switch ($auswahl)
{
    1 { Get-LocalMemoryValues }
    2 { Get-LocalDiskSpaceInfo }
    3 { Get-LocalPowerShellVersion }
    4 { Get-ServerCpuLoadInfo }
    5 { Get-ServerMemoryValues }
    6 { Get-ServerDiskSpaceInfo }
    7 { Get-ServerOperatingSystem }
    8 { Get-ServerInstalledFielmannServices }
    9 { Get-ServerPowerShellVersion }
    10 { Get-ServerdotNETVersion }
    11 { Get-VersionOfInstalledIISApplications }
}
$host.ui.RawUI.WindowTitle = $prevTitle