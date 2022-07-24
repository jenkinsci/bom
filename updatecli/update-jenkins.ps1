param(
  [Parameter(Position=0)]
  [string] $JenkinsVersion
)

$changed = $false

$pomPath = "sample-plugin/pom.xml"
$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($pomPath)

if ($JenkinsVersion -imatch "^\d+\.\d+\.\d+$") {
  $JenkinsVersionX = $JenkinsVersion -replace '\d+$', 'x'
  $pomProfile = $pom.project.profiles.profile | Where-Object { $_.id -eq $JenkinsVersionX } | Select-Object -First 1
  if ($null -eq $pomProfile) {
    Write-Host "Profile for Jenkins version $JenkinsVersionX not found in $pomPath"
    exit 1
  }

  $currentVersion = $pomProfile.properties.'jenkins.version'
  if ($null -ne $currentVersion -and $currentVersion -ne $JenkinsVersion) {
    $changed = $true
    $pomProfile.Properties.'jenkins.version' = $JenkinsVersion
    Write-Output "$JenkinsVersion"
  }
} elseif ($JenkinsVersion -imatch "^\d+\.\d+$") {
  $currentVersion = $pom.project.properties.'jenkins.version'
  if ($null -ne $currentVersion -and $currentVersion -ne $JenkinsVersion) {
    $changed = $true
    $pom.project.properties.'jenkins.version' = $JenkinsVersion
    Write-Output "$JenkinsVersion"
  }
} else {
  Write-Host "Invalid Jenkins version $JenkinsVersion"
  exit 1
}

if ($changed) {
  $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
  $streamWriter = New-Object System.IO.StreamWriter($pomPath, $false, $utf8WithoutBom)
  $pom.Save($streamWriter)
  $streamWriter.Close()
}
