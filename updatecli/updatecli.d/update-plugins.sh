#!/bin/bash

set -eux -o pipefail

jenkinsVersion="$1"
jar="${PLUGIN_MANAGER_JAR_PATH:-"./plugin-manager.jar"}"
pwsh -NoProfile -File "./updatecli/updatecli.d/update-plugins.ps1" -JenkinsVersion "${jenkinsVersion}" -PluginManagerJar "${jar}"
