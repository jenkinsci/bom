param(
  [Parameter(Position = 0)]
  [string] $BomVersion,
  [Parameter(Position = 1)]
  [string] $JenkinsVersion
)

$changed = $false
if ($null -eq $ENV:DRY_RUN) {
  $ENV:DRY_RUN = $false
}

$pomPath = "sample-plugin/pom.xml"
$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($pomPath)

if ($BomVersion -eq "weekly") {
  $currentVersion = $pom.project.properties.'jenkins.version'
  if ($null -ne $currentVersion -and $currentVersion -ne $JenkinsVersion) {
    $changed = $true
    $pom.project.properties.'jenkins.version' = $JenkinsVersion
  }
} else {
  $pomProfile = $pom.project.profiles.profile | Where-Object { $_.id -eq $BomVersion } | Select-Object -First 1
  if ($null -eq $pomProfile) {
    Write-Host "Profile for Jenkins version $BomVersion not found in $pomPath"
    exit 1
  }

  $currentVersion = $pomProfile.properties.'jenkins.version'
  if ($null -ne $currentVersion -and $currentVersion -ne $JenkinsVersion) {
    $changed = $true
    $pomProfile.Properties.'jenkins.version' = $JenkinsVersion
  }
}

if ($changed) {
  Write-Output "$JenkinsVersion"

  if ($ENV:DRY_RUN -eq $false) {
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $streamWriter = New-Object System.IO.StreamWriter($pomPath, $false, $utf8WithoutBom)
    $pom.Save($streamWriter)
    $streamWriter.Close()
  }
}
