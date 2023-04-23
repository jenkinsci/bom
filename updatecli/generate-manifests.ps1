if ($null -eq $ENV:GITHUB_WORKSPACE) {
  $root = "$PSScriptRoot/.." | Resolve-Path
} else {
  $root = $ENV:GITHUB_WORKSPACE
}

function EnsureModuleInstalled ($name) {
  $module = Get-InstalledModule -Name $name -ErrorAction SilentlyContinue
  if ($null -eq $module) {
    Install-Module -Name $name -Scope CurrentUser -AllowClobber
  } else {
    Import-Module $name
  }
}

EnsureModuleInstalled "powershell-yaml"

$manifestDirectory = "$root/updatecli/updatecli.d"

if ([System.IO.Directory]::Exists($manifestDirectory) -eq $false) {
  New-Item -Force -ItemType Directory -Path $manifestDirectory | Out-Null
}

# Get current bom versions based on directory structure afterwards sort by version number ascending
$bills = Get-ChildItem "$root/bom-*" -Directory `
  | Select-Object -ExpandProperty Name `
  | Where-Object { $_ -ne "bom-weekly" } `
  | ForEach-Object { [System.Version]$($_ -replace '^bom-(\d+\.\d+?)\.x$','$1') } `
  | Sort-Object `
  | ForEach-Object { "bom-$($_.Major).$($_.Minor).x" }

$latestStableBom = $bills[-1]
$bills = @("bom-weekly") + $bills

$pomPath = "sample-plugin/pom.xml"
$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($pomPath)

$jenkinsVersions = @{}

$jenkinsVersions["weekly"] = $pom.project.properties."jenkins.version"

$pom.project.profiles.profile | ForEach-Object {
  $jenkinsVersions[$_.id] = $_.properties."jenkins.version"
}

foreach ($bom in $bills) {
  $updateJenkinsManifest = [ordered]@{
    scms         = [ordered]@{
      github = [ordered]@{
        kind = "github"
        spec = [ordered]@{
          user       = '{{ .github.user }}'
          email      = '{{ .github.email }}'
          owner      = '{{ .github.owner }}'
          repository = '{{ .github.repository }}'
          branch     = '{{ .github.branch }}'
          username   = '{{ .github.username }}'
          token      = '{{ requiredEnv .github.token }}'
        }
      }
    }
    sources      = [ordered]@{}
    conditions   = [ordered]@{}
    targets      = [ordered]@{}
    actions      = [ordered]@{}
  }

  $bomVersion = $bom -replace "bom-", ""
  $jenkinsVersion = $jenkinsVersions[$bomVersion]

  $updateJenkinsManifestPath = "$manifestDirectory/update-jenkins-$bomVersion.yaml"

  if ($bom -eq "bom-weekly") {
    $updateJenkinsManifest.sources["jenkins"] = [ordered]@{
      name = "Get Last jenkins Weekly Version"
      kind = "jenkins"
      spec = [ordered]@{
        release = "weekly"
        github  = [ordered]@{
          token    = '{{ requiredEnv .github.token }}'
          username = '{{ .github.username }}'
        }
      }
    }
  } else {
    # remove .x from z.y.x and replace literal dot with escaped dot
    $bomVersionPattern = $bomVersion -replace ".x", ""
    if ($latestStableBom -eq $bom) {
      $bomVersionPattern = "jenkins-$bomVersionPattern.1$"
    } else {
      $bomVersionPattern = "jenkins-$bomVersionPattern.\d+$"
    }
    $bomVersionPattern = $bomVersionPattern -replace "\.", "\."
    $updateJenkinsManifest.sources["jenkins"] = [ordered]@{
      name         = "Get last Jenkins stable version"
      kind         = "githubrelease"
      spec         = [ordered]@{
        owner         = "jenkinsci"
        repository    = "jenkins"
        token         = '{{ requiredEnv .github.token }}'
        versionfilter = [ordered]@{
          kind    = "regex"
          pattern = $bomVersionPattern
        }
      }
      transformers = @(@{
          trimprefix = "jenkins-"
        })
    }
  }

  $updateJenkinsManifest.conditions["jenkins"] = [ordered]@{
    name     = "Test if Jenkins stable published"
    kind     = "maven"
    sourceid = "jenkins"
    spec     = [ordered]@{
      url        = "repo.jenkins-ci.org"
      repository = "releases"
      groupId    = "org.jenkins-ci.main"
      artifactId = "jenkins-war"
    }
  }
  $updateJenkinsManifest.targets["jenkins"] = [ordered]@{
    name     = "Update Jenkins version"
    sourceid = "jenkins"
    scmid    = "github"
    kind     = "shell"
    spec     = [ordered]@{
      command      = "pwsh -NoProfile -File {{ requiredEnv `"GITHUB_WORKSPACE`" }}/updatecli/update-jenkins.ps1 $bomVersion"
    }
  }
  $updateJenkinsManifest.actions["jenkins"] = [ordered]@{
    title   = "Bump jenkins.version from $jenkinsVersion to {{ source `"jenkins`" }} for bom-$bomVersion"
    kind    = "github/pullrequest"
    scmid   = "github"
    targets = @("jenkins")
    spec    = [ordered]@{
      labels      = @("dependencies")
      automerge   = $true
      mergemethod = "squash"
      usetitleforautomerge = $true
    }
  }

  ConvertTo-Yaml -Data $updateJenkinsManifest -OutFile $updateJenkinsManifestPath -Force

  if ($bom -eq "bom-weekly") {
    # weekly bom is handled by dependabot
    continue
  }

  $pomPath = "$bom/pom.xml"
  $pom = New-Object System.Xml.XmlDocument
  $pom.PreserveWhitespace = $true
  $pom.Load($pomPath)

  $dependencies = $pom.Project.DependencyManagement.Dependencies.Dependency | Select-Object -Skip 1


  foreach ($dependency in $dependencies) {
    $artifactId = $dependency.artifactId
    $groupId = $dependency.groupId
    $version = $dependency.version
    $name = $artifactId
    if ($version.StartsWith("$")) {
      # remove the dollar sign and curly braces
      $name = $version -replace '^\${(.+?)}$', '$1'
      $version = $pom.project.properties."$name"
    }

    $updatePluginsManifestPath = "$manifestDirectory/update-plugin-$bomVersion-$artifactId-$version.yaml"

    if ([System.IO.File]::Exists($updatePluginsManifestPath)) {
      continue
    }

    $updatePluginsManifest = [ordered]@{
      scms         = [ordered]@{
        github = [ordered]@{
          kind = "github"
          spec = [ordered]@{
            user       = '{{ .github.user }}'
            email      = '{{ .github.email }}'
            owner      = '{{ .github.owner }}'
            repository = '{{ .github.repository }}'
            branch     = '{{ .github.branch }}'
            username   = '{{ .github.username }}'
            token      = '{{ requiredEnv .github.token }}'
          }
        }
      }
      sources      = [ordered]@{}
      conditions   = [ordered]@{}
      targets      = [ordered]@{}
      actions      = [ordered]@{}
    }

    $updatePluginsManifest.sources["plugin"] = [ordered]@{
      name         = "Get last $name version"
      kind         = "shell"
      spec         = @{
        command = "java -jar {{ requiredEnv `"PLUGIN_MANAGER_JAR_PATH`" }} --no-download --available-updates --output txt --jenkins-version $jenkinsVersion --plugins ${artifactId}:${version}"
      }
      transformers = @(
        @{
          findsubmatch = @{
            pattern      = '(.*?):(.*)'
            captureindex = 2
          }
        }
      )
    }
    $updatePluginsManifest.conditions["plugin"] = [ordered]@{
      name     = "Test if $name is published"
      kind     = "maven"
      sourceid = "plugin"
      spec     = [ordered]@{
        url        = "repo.jenkins-ci.org"
        repository = "releases"
        groupId    = $groupId
        artifactId = $artifactId
      }
    }
    $updatePluginsManifest.targets["plugin"] = [ordered]@{
      name     = "Update $name"
      sourceid = "plugin"
      scmid    = "github"
      kind     = "shell"
      spec     = @{
        command = "pwsh -NoProfile -File {{ requiredEnv `"GITHUB_WORKSPACE`" }}/updatecli/update-plugin.ps1 $pomPath $name"
      }
    }
    $updatePluginsManifest.actions["plugin"] = [ordered]@{
      title   = "Bump $name from $version to {{ source `"plugin`" }} in /bom-$bomVersion"
      kind    = "github/pullrequest"
      scmid   = "github"
      targets = @("plugin")
      spec    = [ordered]@{
        labels      = @("dependencies")
        automerge   = $true
        mergemethod = "squash"
        usetitleforautomerge = $true
      }
    }

    ConvertTo-Yaml -Data $updatePluginsManifest -OutFile $updatePluginsManifestPath -Force
  }
}
