<#
    Aktualisiert alle untergeordneten Arbeitsverzeichnisse mit den verknüpften TFS- und git-Repositories.
#>

# Dieser Pfad ist abhängig von der installierten VS-Version
$pathToTfexe = "C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\tf.exe"
if (Test-Path $pathToTfexe)
{
    Write-Host -ForegroundColor Green "- TFS -"

    $tfsFolder = Get-ChildItem -Directory -Force -Recurse -Depth 3 | Where-Object Name -eq '$tf'
    foreach ($folder in $tfsFolder) {
        $path = (Get-Item $folder.FullName -Force).Parent.FullName
        Write-Host -ForegroundColor DarkGreen "-- Aktualisiere: $path"
        Push-Location $path
        $fileToUserName = Join-Path ((Get-Item $PWD).Parent).FullName ("User-" + (Get-Item $PWD).Name + ".txt")
        if (Test-Path $fileToUserName)
        {
            $username = "/login:" + (Get-Content $fileToUserName)
        } else {
            $username = $null
        }
        & $pathToTfexe get $username
        Pop-Location
        Write-Output ''
    }
}

# Bei git wird ein pull auf alle branches durchgeführt. Ggf. ist dies nicht die optimalste Lösung.
Write-Host -ForegroundColor Green "- git -"
$gitFolder = Get-ChildItem -Directory -Force -Recurse -Depth 3 | Where-Object Name -eq '.git'
foreach ($folder in $gitFolder) {
    $path = (Get-Item $folder.FullName -Force).Parent.FullName
    $branch = (git -C $path branch).Trim()
    Write-Host -ForegroundColor DarkGreen "-- Aktualisiere: $path"
    Write-Host -ForegroundColor DarkGreen "-- Branches: $branch"
    git -C $path pull --all
    Write-Output ''
}

Pause