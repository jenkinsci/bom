param(
  [Parameter(Position=0)]
  [string] $PomPath,
  [Parameter(Position=1)]
  [string] $Artifact,
  [Parameter(Position=2)]
  [string] $NewVersion
)

$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($PomPath)

# Select Dependencies and Skip BOM
$dependencies = $pom.Project.DependencyManagement.Dependencies.Dependency | Select-Object -Skip 1

$plugin = @($dependencies | Where-Object { $_.artifactid -eq $Artifact })

if ($plugin.Count -eq 0) {
  Write-Host "Plugin not found"
  exit 1
}

if ($plugin[0].version -eq $NewVersion) {
  exit 0
}

$plugin | ForEach-Object {
  $_.version = $NewVersion
}
Write-Output $NewVersion

$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
$streamWriter = New-Object System.IO.StreamWriter($PomPath, $false, $utf8WithoutBom)
$pom.Save($streamWriter)
$streamWriter.Close()
