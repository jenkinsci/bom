param(
  [string] $JenkinsVersion,
  [string] $PluginManagerJar = './plugin-manager.jar'
)

$JenkinsVersionX = $JenkinsVersion -replace '\d+$', 'x'

$pomPath = "bom-${JenkinsVersionX}/pom.xml"
$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($pomPath)

# Select Dependencies and Skip BOM
$dependencies = $pom.Project.DependencyManagement.Dependencies.Dependency | Select-Object -Skip 1

foreach ($dependency in $dependencies) {
  $artifact = $dependency.artifactId
  $oldVersion = $dependency.version
  $plugin = "${artifact}:${oldVersion}"
  [string] $output = & java -jar "$PluginManagerJar" --no-download --available-updates --jenkins-version "$JenkinsVersion" --plugins $plugin
  if ($output -inotlike '*No available updates*') {
    # Exaple output:
    # Available updates:
    # credentials (2.6.1) has an available update: 2.6.1.1

    # Grab the version number at the end of the line
    $version = $output.Trim().Split(' ')[-1]
    Write-Output "Changed $artifact from $oldVersion to $version"
    $dependency.version = $version
  }
}

$pom.Save($pomPath)
