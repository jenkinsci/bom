
$root = "$PSScriptRoot/.." | Resolve-Path

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

# bills would be sorted by name due to our naming convention of "bom-x.y.z"
$bills = Get-ChildItem "$root/bom-*" -Directory | Select-Object -ExpandProperty Name

$pomPath = "sample-plugin/pom.xml"
$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($pomPath)

$jenkinsVersions = @{}

$jenkinsVersions["weekly"] = $pom.project.properties."jenkins.version"

$pom.project.profiles.profile | ForEach-Object {
  $jenkinsVersions[$_.id] = $_.properties."jenkins.version"
}

$last = $bills | Where-Object { $_ -ne "bom-weekly" } | Select-Object -Last 1
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
    pullrequests = [ordered]@{}
  }

  $version = $bom -replace "bom-", ""
  $versionWithoutX = $version -replace ".x", ""

  $updateJenkinsManifestPath = "$manifestDirectory/update-jenkins-$version.yaml"

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
    if ($last -eq $bom) {
      $versionPattern = "jenkins-$versionWithoutX.1$"
    } else {
      $versionPattern = "jenkins-$versionWithoutX.\d+$"
    }
    $updateJenkinsManifest.sources["jenkins"] = [ordered]@{
      name         = "Get last Jenkins stable version"
      kind         = "githubrelease"
      spec         = [ordered]@{
        owner         = "jenkinsci"
        repository    = "jenkins"
        token         = '{{ requiredEnv .github.token }}'
        versionfilter = [ordered]@{
          kind    = "regex"
          pattern = "$($versionPattern)"
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
      command      = 'pwsh -NoProfile -File {{ requiredEnv "GITHUB_WORKSPACE" }}/updatecli/update-jenkins.ps1'
    }
  }
  $updateJenkinsManifest.pullrequests["jenkins"] = [ordered]@{
    title   = "Bump jenkins.version from $($jenkinsVersions[$version]) to {{ source `"jenkins`" }} for bom-$version"
    kind    = "github"
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
  $jenkinsVersion = $version

  foreach ($dependency in $dependencies) {
    $artifact = $dependency.artifactId
    $groupId = $dependency.groupId
    $version = $dependency.version
    if ($version.StartsWith("$")) {
      # remove the dollar sign and curly braces
      $version = $version -replace '^\${(.+?)}$', '$1'
      $version = $pom.project.properties."$version"
    }

    $updatePluginsManifestPath = "$manifestDirectory/update-plugin-$jenkinsVersion-$artifact-$version.yaml"

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
      pullrequests = [ordered]@{}
    }

    $updatePluginsManifest.sources["plugin"] = [ordered]@{
      name         = "Get last $artifact version"
      kind         = "shell"
      spec         = @{
        command = "java -jar {{ requiredEnv `"PLUGIN_MANAGER_JAR_PATH`" }} --no-download --available-updates --output txt --jenkins-version $($jenkinsVersions[$jenkinsVersion]) --plugins ${artifact}:${version}"
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
      name     = "Test if $artifact is published"
      kind     = "maven"
      sourceid = "plugin"
      spec     = [ordered]@{
        url        = "repo.jenkins-ci.org"
        repository = "releases"
        groupId    = "$($groupId)"
        artifactId = "$($artifact)"
      }
    }
    $updatePluginsManifest.targets["plugin"] = [ordered]@{
      name     = "Update $artifact"
      sourceid = "plugin"
      scmid    = "github"
      kind     = "shell"
      spec     = @{
        command = "pwsh -NoProfile -File {{ requiredEnv `"GITHUB_WORKSPACE`" }}/updatecli/update-plugin.ps1 $pomPath $artifact"
      }
    }
    $updatePluginsManifest.pullrequests["plugin"] = [ordered]@{
      title   = "Bump $artifact from $version to {{ source `"plugin`" }} in /bom-$jenkinsVersion"
      kind    = "github"
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
