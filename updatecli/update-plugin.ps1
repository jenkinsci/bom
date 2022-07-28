param(
  [Parameter(Position=0)]
  [string] $PomPath,
  [Parameter(Position=1)]
  [string] $Artifact,
  [Parameter(Position=2)]
  [string] $NewVersion
)

$changed = $false
if ($null -eq $ENV:DRY_RUN) {
  $ENV:DRY_RUN = $false
}

$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($PomPath)

# Select Dependencies and Skip BOM
$dependencies = $pom.Project.DependencyManagement.Dependencies.Dependency | Select-Object -Skip 1

$plugins = @($dependencies | Where-Object { $_.artifactid -eq $Artifact })
$property = $pom.project.properties."$Artifact"

if ($null -ne $property -and $property -ne $NewVersion) {
  Write-Host "1 Updating $Artifact to $NewVersion"
  $changed = $true
  $pom.project.properties."$Artifact" = $NewVersion
}

if ($plugins.Count -ne 0 -and $plugins[0].version -ne $NewVersion) {
  $changed = $true
  $plugins | ForEach-Object {
    $_.version = $NewVersion
  }
}

if ($changed) {
  Write-Output $NewVersion

  if ($ENV:DRY_RUN -eq $false) {
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $streamWriter = New-Object System.IO.StreamWriter($PomPath, $false, $utf8WithoutBom)
    $pom.Save($streamWriter)
    $streamWriter.Close()
  }
}
