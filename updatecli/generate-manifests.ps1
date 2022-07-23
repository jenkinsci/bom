
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
$updateJenkinsManifestPath = "$manifestDirectory/update-jenkins.yaml"
$updatePluginsManifestPath = "$manifestDirectory/update-plugins.yaml"

if ([System.IO.Directory]::Exists($manifestDirectory) -eq $false) {
  New-Item -Force -ItemType Directory -Path $manifestDirectory
}

# For testing locally, you can set $GITHUB_WORKSPACE to the root of the repository ie. $PWD
$jenkinsUpdateScript = 'pwsh -NoProfile -File {{ requiredEnv "GITHUB_WORKSPACE" }}/updatecli/update-jenkins.ps1'

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

$updateJenkinsManifest.sources["jenkinsWeekly"] = [ordered]@{
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
$updateJenkinsManifest.conditions["jenkinsWeekly"] = [ordered]@{
  name     = "Test if Jenkins weekly published"
  kind     = "maven"
  sourceid = "jenkinsWeekly"
  spec     = [ordered]@{
    url        = "repo.jenkins-ci.org"
    repository = "releases"
    groupId    = "org.jenkins-ci.main"
    artifactId = "jenkins-war"
  }
}
$updateJenkinsManifest.targets["jenkinsWeekly"] = [ordered]@{
  name     = 'Update Jenkins weekly version'
  sourceid = "jenkinsWeekly"
  scmid    = "github"
  kind     = "shell"
  spec     = [ordered]@{
    command      = $($jenkinsUpdateScript)
    environments = @([ordered]@{
        name = "GITHUB_WORKSPACE"
      })
  }
}
$updateJenkinsManifest.pullrequests["jenkinsWeekly"] = [ordered]@{
  title   = 'Bump jenkins.version to {{ source "jenkinsWeekly" }} for bom-weekly'
  kind    = "github"
  scmid   = "github"
  targets = @("jenkinsWeekly")
  spec    = [ordered]@{
    labels      = @("dependencies")
    automerge   = $true
    mergemethod = "squash"
  }
}

# bills would be sorted by name due to our naming convention of "bom-x.y.z"
$bills = Get-ChildItem "$root/bom-*" -Directory | Select-Object -ExpandProperty Name | Where-Object { $_ -ne "bom-weekly" }

$pomPath = "sample-plugin/pom.xml"
$pom = New-Object System.Xml.XmlDocument
$pom.PreserveWhitespace = $true
$pom.Load($pomPath)

$jenkinsVersions = @{}

$pom.project.profiles.profile | ForEach-Object {
  $jenkinsVersions[$_.id] = $_.properties."jenkins.version"
}

$last = $bills[-1]
foreach ($bom in $bills) {
  $version = $bom -replace "bom-", ""
  $versionWithoutX = $version -replace ".x", ""
  if ($last -eq $bom) {
    $versionPattern = "jenkins-$versionWithoutX.1$"
  } else {
    $versionPattern = "jenkins-$versionWithoutX.\d+$"
  }
  $updateJenkinsManifest.sources["jenkins$version"] = [ordered]@{
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
  $updateJenkinsManifest.conditions["jenkins$version"] = [ordered]@{
    name     = "Test if Jenkins stable published"
    kind     = "maven"
    sourceid = "jenkins$version"
    spec     = [ordered]@{
      url        = "repo.jenkins-ci.org"
      repository = "releases"
      groupId    = "org.jenkins-ci.main"
      artifactId = "jenkins-war"
    }
  }
  $updateJenkinsManifest.targets["jenkins$version"] = [ordered]@{
    name     = "Update Jenkins $version version"
    sourceid = "jenkins$version"
    scmid    = "github"
    kind     = "shell"
    spec     = [ordered]@{
      command      = $($jenkinsUpdateScript)
      environments = @(
        @{ name = "GITHUB_WORKSPACE" }
      )
    }
  }
  $updateJenkinsManifest.pullrequests["jenkins$version"] = [ordered]@{
    title   = "Bump jenkins.version to {{ source `"jenkins$version`" }} for bom-$version"
    kind    = "github"
    scmid   = "github"
    targets = @("jenkins$version")
    spec    = [ordered]@{
      labels      = @("dependencies")
      automerge   = $true
      mergemethod = "squash"
    }
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

    if ($null -ne $updatePluginsManifest.sources["plugin${jenkinsVersion}${artifact}"]) {
      continue
    }

    $updatePluginsManifest.sources["plugin${jenkinsVersion}${artifact}"] = [ordered]@{
      name         = "Get last $artifact version for $version"
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
    $updatePluginsManifest.conditions["plugin${jenkinsVersion}${artifact}"] = [ordered]@{
      name     = "Test if $artifact is published"
      kind     = "maven"
      sourceid = "plugin${jenkinsVersion}${artifact}"
      spec     = [ordered]@{
        url        = "repo.jenkins-ci.org"
        repository = "releases"
        groupId    = "$($groupId)"
        artifactId = "$($artifact)"
      }
    }
    $updatePluginsManifest.targets["plugin${jenkinsVersion}${artifact}"] = [ordered]@{
      name     = "Update $artifact"
      sourceid = "plugin${jenkinsVersion}${artifact}"
      scmid    = "github"
      kind     = "shell"
      spec     = @{
        command = "pwsh -NoProfile -File {{ requiredEnv `"GITHUB_WORKSPACE`" }}/updatecli/update-plugin.ps1 $pomPath $artifact"
      }
    }
    $updatePluginsManifest.pullrequests["plugin${jenkinsVersion}${artifact}"] = [ordered]@{
      title   = "Bump $artifact to {{ source `"plugin${jenkinsVersion}${artifact}`" }} for bom-$version"
      kind    = "github"
      scmid   = "github"
      targets = @("plugin${jenkinsVersion}${artifact}")
      spec    = [ordered]@{
        labels      = @("dependencies")
        automerge   = $true
        mergemethod = "squash"
      }
    }
  }
}

ConvertTo-Yaml -Data $updateJenkinsManifest -OutFile $updateJenkinsManifestPath -Force
ConvertTo-Yaml -Data $updatePluginsManifest -OutFile $updatePluginsManifestPath -Force
