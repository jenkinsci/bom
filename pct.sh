#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: megawar.war, pct.war, excludes.txt, $PLUGINS, $LINE

rm -rf pct-work

if [[ -n ${MAVEN_SETTINGS-} ]]; then
	PCT_S_ARG="-m2SettingsFile ${MAVEN_SETTINGS}"
else
	PCT_S_ARG=
fi

MAVEN_PROPERTIES=jth.jenkins-war.path=$(pwd)/megawar.war:forkCount=.75C:surefire.excludesFile=$(pwd)/excludes.txt
if [[ -n ${EXTRA_MAVEN_PROPERTIES-} ]]; then
	MAVEN_PROPERTIES="${MAVEN_PROPERTIES}:${EXTRA_MAVEN_PROPERTIES}"
fi

#
# Grab the Jenkins version from the WAR file so that we can pass it in via jenkins.version. This is
# needed because HPI Plugin requires the version of the WAR passed in via overrideWar to be
# identical to jenkins.version. If we do not explicitly pass in jenkins.version, then the
# jenkins.version defined in the plugin's pom.xml file will be used, which may not match the version
# of the WAR under test.
#
mkdir pct-work
pushd pct-work
jar xf ../megawar.war META-INF/MANIFEST.MF
JENKINS_VERSION=$(perl -w -p -0777 -e 's/\r?\n //g' META-INF/MANIFEST.MF | grep Jenkins-Version | awk '{print $2}')
popd
rm -rf pct-work
MAVEN_PROPERTIES+=":jenkins.version=${JENKINS_VERSION}:overrideWar=$(pwd)/megawar.war:overrideWarAdditions=true:useUpperBounds=true"

#
# The overrideWar option is available in HPI Plugin 3.29 or later, but many plugins under test
# still use an older plugin parent POM and therefore an older HPI plugin version. As a temporary
# workaround, we override the HPI plugin version to the latest version.
#
# TODO When all plugins in the managed set are using a plugin parent POM with HPI Plugin 3.29 or
# later (i.e., plugin parent POM 4.44 or later), this can be deleted.
#
MAVEN_PROPERTIES+=:hpi-plugin.version=3.38

#
# Define the excludes for upper bounds checking. We define these excludes in a separate file and
# pass it in via -mavenPropertiesFile rather than using -mavenProperties because -mavenProperties
# uses a colon as the separator and these values contain colons.
#

#
# javax.servlet:servlet-api comes from core at version 0, which is an intentional trick to
# prevent this library from being used, and we do not want it to be upgraded to a nonzero
# version (which is not a realistic test scenario) just because it happens to be on the
# class path of some plugin and triggers an upper bounds violation. JENKINS-68696 tracks the
# removal of this trick.
#
echo upperBoundsExcludes=javax.servlet:servlet-api >maven.properties

#
# This test has been broken for a very long time.
#
[[ $PLUGINS == gitlab-plugin ]] && MAVEN_PROPERTIES+=:failsafe.excludes=com.dabsquared.gitlabjenkins.testing.integration.GitLabIT

#
# Testing plugins against a version of Jenkins that requires Java 11 exposes
# jenkinsci/plugin-pom#563. This was fixed in plugin parent POM 4.42, but many plugins under test
# still use an older plugin parent POM. As a temporary workaround, we skip Enforcer.
#
# TODO When all plugins in the managed set are using plugin parent POM 4.42 or later, this can be
# deleted.
#
MAVEN_PROPERTIES+=:enforcer.skip=true

exec java \
	-jar pct.jar \
	-war "$(pwd)/megawar.war" \
	-includePlugins "${PLUGINS}" \
	-workDirectory "$(pwd)/pct-work" \
	$PCT_S_ARG \
	-mavenProperties "${MAVEN_PROPERTIES}" \
	-mavenPropertiesFile "$(pwd)/maven.properties"

# produces: **/target/surefire-reports/TEST-*.xml
