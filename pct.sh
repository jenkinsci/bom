#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: megawar.war, pct.war, excludes.txt, $PLUGINS, $LINE

rm -rf pct-work

if [[ -n ${MAVEN_SETTINGS-} ]]; then
	PCT_S_ARG="--maven-settings ${MAVEN_SETTINGS}"
else
	PCT_S_ARG=
fi

PCT_D_ARGS=
if [[ -n ${EXTRA_MAVEN_PROPERTIES-} ]]; then
	for prop in ${EXTRA_MAVEN_PROPERTIES//:/ }; do
		PCT_D_ARGS+="-D${prop} "
	done
fi

#
# This test has been broken for a very long time.
#
[[ $PLUGINS == gitlab-plugin ]] && PCT_D_ARGS+='-Dfailsafe.excludes=com.dabsquared.gitlabjenkins.testing.integration.GitLabIT '

#
# The overrideWar option is available in HPI Plugin 3.29 or later, but many plugins under test still
# use an older plugin parent POM and therefore an older HPI plugin version. As a temporary
# workaround, we override the HPI plugin version to the latest version. When all plugins in the
# managed set are using a plugin parent POM with HPI Plugin 3.29 or later (i.e., plugin parent POM
# 4.44 or later), this can be deleted.
#
# Testing plugins against a version of Jenkins that requires Java 11 exposes
# jenkinsci/plugin-pom#563. This was fixed in plugin parent POM 4.42, but many plugins under test
# still use an older plugin parent POM. As a temporary workaround, we skip Enforcer. When all
# plugins in the managed set are using plugin parent POM 4.42 or later, this can be deleted.
#
exec java \
	-jar pct.jar \
	--war "$(pwd)/megawar.war" \
	--include-plugins "${PLUGINS}" \
	--working-dir "$(pwd)/pct-work" \
	$PCT_S_ARG \
	$PCT_D_ARGS \
	-Denforcer.skip=true \
	-DforkCount=.75C \
	-Dhpi-plugin.version=3.38 \
	-Djth.jenkins-war.path="$(pwd)/megawar.war" \
	-DoverrideWarAdditions=true \
	-Dsurefire.excludesFile="$(pwd)/excludes.txt"

# produces: **/target/surefire-reports/TEST-*.xml
