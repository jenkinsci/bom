#!/usr/bin/env bash

set -eux -o pipefail

jenkinsVersion="$1"
jar="${PLUGIN_MANAGER_JAR_PATH:-"./plugin-manager.jar"}"

# check if jar does not exist
if [ ! -f "$jar" ]; then
  curl -sSL https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.3/jenkins-plugin-manager-2.12.3.jar -o "$jar"
fi

pwsh -NoProfile -File "./updatecli/updatecli.d/update-plugins.ps1" -JenkinsVersion "${jenkinsVersion}" -PluginManagerJar "${jar}"
