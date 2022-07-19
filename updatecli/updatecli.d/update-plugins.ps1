param(
  [Parameter(Position=0)]
  [string] $JenkinsVersion
)

Write-Host "Jenkins version: $JenkinsVersion"
$JenkinsVersionX = $JenkinsVersion -replace '\d+$', 'x'

$pluginManagerJar = $ENV:PLUGIN_MANAGER_JAR_PATH ?? './plugin-manager.jar'
$pluginManagerVersion = $ENV:PLUGIN_MANAGER_VERSION ?? '2.12.8'

# check if jar does not exist, download it - useful for testing
if ([System.IO.File]::Exists($pluginManagerJar) -eq $false) {
  curl -sSL "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/$pluginManagerVersion/jenkins-plugin-manager-$pluginManagerVersion.jar" -o "$pluginManagerJar"
}

if (Get-Command 'java' -ErrorAction SilentlyContinue) {
  $java = 'java'
} elseif ($IsLinux) {
  $java = '/usr/bin/java'
} else {
  $java = 'java'
}

$pomPath = "bom-${JenkinsVersionX}/pom.xml"
$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($pomPath)

# Select Dependencies and Skip BOM
$dependencies = $pom.Project.DependencyManagement.Dependencies.Dependency | Select-Object -Skip 1

$changed = $false
foreach ($dependency in $dependencies) {
  $artifact = $dependency.artifactId
  $oldVersion = $dependency.version
  $plugin = "${artifact}:${oldVersion}"
  [string] $output = & $java -jar "$pluginManagerJar" --no-download --available-updates --output txt --jenkins-version "$JenkinsVersion" --plugins $plugin
  if ($null -ne $output -and $output -ne $plugin) {
    # Example output:
    # credentials:2.6.1.1

    # Grab the version number
    $newVersion = $output.Split(':')[-1]
    Write-Output "Changed $artifact from $oldVersion to $newVersion"
    $dependency.version = $newVersion
    $changed = $true
  }
}

if ($changed) {
  $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
  $streamWriter = New-Object System.IO.StreamWriter($pomPath, $false, $utf8WithoutBom)
  $pom.Save($streamWriter)
  $streamWriter.Close()
}
