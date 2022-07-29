#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: megawar.war, pct.war, excludes.txt, $PLUGINS, $LINE

rm -rf pct-work pct-report.xml

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
MAVEN_PROPERTIES+=":jenkins.version=${JENKINS_VERSION}:overrideWar=$(pwd)/megawar.war:useUpperBounds=true"

#
# The overrideWar option is available in HPI Plugin 3.29 or later, but many plugins under test
# still use an older plugin parent POM and therefore an older HPI plugin version. As a temporary
# workaround, we override the HPI plugin version to the latest version.
#
# TODO When all plugins in the managed set are using a plugin parent POM with HPI Plugin 3.29 or
# later (i.e., plugin parent POM 4.44 or later), this can be deleted.
#
MAVEN_PROPERTIES+=:hpi-plugin.version=3.31

#
# Define the excludes for upper bounds checking. We define these excludes in a separate file and
# pass it in via -mavenPropertiesFile rather than using -mavenProperties because -mavenProperties
# uses a colon as the separator and these values contain colons.
#
if [[ $LINE == '2.319.x' ]]; then
	#
	# com.sun.mail needs to be excluded because it is still provided by core on this line (using
	# pre-Jakarta imports) and we do not want it to be upgraded to a version that uses Jakarta
	# imports (which is not a realistic test scenario) just because the Jakarta Mail API plugin
	# happens to be on the class path and triggers an upper bounds violation.
	#
	echo upperBoundsExcludes=com.sun.mail:jakarta.mail,javax.servlet:servlet-api >maven.properties
else
	#
	# javax.servlet:servlet-api comes from core at version 0, which is an intentional trick to
	# prevent this library from being used, and we do not want it to be upgraded to a nonzero
	# version (which is not a realistic test scenario) just because it happens to be on the
	# class path of some plugin and triggers an upper bounds violation. JENKINS-68696 tracks the
	# removal of this trick.
	#
	echo upperBoundsExcludes=javax.servlet:servlet-api >maven.properties
fi

#
# JSch and OkHttp use an older plugin parent POM and therefore an older test harness that predates
# compatibility with the removal of JNR in recent cores in jenkinsci/jenkins-test-harness#350. As a
# temporary workaround, we override the test harness to a recent version. Note that we cannot use a
# test harness newer than 1812.v6d4e97d91fd8, because later releases of the test harness require
# changes to the plugin parent POM for JUnit 5 support.
#
# TODO When these plugins are using a plugin parent POM with test harness 1657.vf8a824e79147 or
# later (i.e., plugin parent POM 4.32 or later), this can be deleted.
#
if [[ $PLUGINS =~ jsch ]] || [[ $PLUGINS =~ okhttp-api ]]; then
	MAVEN_PROPERTIES+=:jenkins-test-harness.version=1812.v6d4e97d91fd8
fi

#
# Testing plugins against a version of Jenkins that requires Java 11 exposes
# jenkinsci/plugin-pom#563. This was fixed in plugin parent POM 4.42, but many plugins under test
# still use an older plugin parent POM. As a temporary workaround, we skip Enforcer.
#
# TODO When all plugins in the managed set are using plugin parent POM 4.42 or later, this can be
# deleted.
#
MAVEN_PROPERTIES+=:enforcer.skip=true

java \
	-jar pct.jar \
	-war "$(pwd)/megawar.war" \
	-includePlugins "${PLUGINS}" \
	-workDirectory "$(pwd)/pct-work" \
	-reportFile "$(pwd)/pct-report.xml" \
	$PCT_S_ARG \
	-mavenProperties "${MAVEN_PROPERTIES}" \
	-excludeHooks org.jenkins.tools.test.hook.TransformPom \
	-mavenPropertiesFile "$(pwd)/maven.properties" \
	-skipTestCache true

if grep -q -F -e '<status>INTERNAL_ERROR</status>' pct-report.xml; then
	echo 'PCT failed with internal error' >&2
	cat pct-report.xml
	exit 1
elif grep -q -F -e '<status>COMPILATION_ERROR</status>' pct-report.xml; then
	echo 'PCT failed with compilation error' >&2
	cat pct-report.xml
	exit 1
elif grep -q -F -e '<status>TEST_FAILURES</status>' pct-report.xml; then
	#
	# Previous versions of PCT claimed that there were test failures even when no tests had been
	# run at all. While we believe that current versions of PCT no longer present this
	# pathology, we err on the side of caution and check anyway.
	#
	echo 'PCT marked failed, checking to see if that is due to a failure to run tests at all' >&2

	#
	# Pipeline: Declarative Extension Points API depends on Pipeline: Model API, which lives in
	# the same repository. When PCT runs the tests for the latter, it ends up compiling the
	# former, which confuses the logic below that attempts to detect when tests were compiled
	# but not executed. While this is potentially an issue for any plugin-to-plugin dependency
	# where both plugins are in a multi-module Maven project tested by PCT, in practice it only
	# affects Pipeline: Declarative Extension Points API, so rather than making the detection
	# logic more complex we simply work around the issue by deleting the relevant class.
	#
	[[ $PLUGINS == pipeline-model-extensions ]] && rm -fv pct-work/pipeline-model-definition/pipeline-model-api/target/test-classes/InjectedTest.class

	#
	# If InjectedTest was compiled but not executed, we assume no tests ran at all. This
	# assumption is valid except in the case of a multi-module Maven project that contains a
	# plugin with a dependency on another plugin in the same multi-module Maven project, in
	# which case PCT will compile both the dependent and its dependency but only execute tests
	# for the dependent.
	#
	for t in pct-work/*/{,*/}target; do
		if [[ -f "${t}/test-classes/InjectedTest.class" ]] && [[ ! -f "${t}/surefire-reports/TEST-InjectedTest.xml" ]] && [[ ! -f "${t}/failsafe-reports/TEST-InjectedTest.xml" ]]; then
			mkdir -p "${t}/surefire-reports"
			cat >"${t}/surefire-reports/TEST-pct.xml" <<-'EOF'
				<testsuite name="pct">
				  <testcase classname="pct" name="overall">
				    <error message="some sort of PCT problem; look at logs"/>
				  </testcase>
				</testsuite>
			EOF
		fi
	done
fi

# produces: **/target/surefire-reports/TEST-*.xml
