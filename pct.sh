#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: megawar.war, pct.war, excludes.txt, $PLUGINS, $LINE

rm -rf pct-work pct-report.xml

if [[ -v MAVEN_SETTINGS ]]; then
	PCT_S_ARG="-m2SettingsFile ${MAVEN_SETTINGS}"
else
	PCT_S_ARG=
fi

MAVEN_PROPERTIES=jth.jenkins-war.path=$(pwd)/megawar.war:forkCount=.75C:surefire.excludesFile=$(pwd)/excludes.txt
if [[ -v EXTRA_MAVEN_PROPERTIES ]]; then
	MAVEN_PROPERTIES="${MAVEN_PROPERTIES}:${EXTRA_MAVEN_PROPERTIES}"
fi

#
# Plugin Compatibility Tester (PCT) requires custom --add-opens directives when running on Java 17.
# As a temporary workaround, we pass in these directives when invoking PCT. When
# jenkinsci/plugin-compat-tester#352 is merged and released, and when this repository has upgraded
# to that release, this workaround can be deleted.
#
java \
	--add-opens java.base/java.lang.reflect=ALL-UNNAMED \
	--add-opens java.base/java.text=ALL-UNNAMED \
	--add-opens java.base/java.util=ALL-UNNAMED \
	--add-opens java.desktop/java.awt.font=ALL-UNNAMED \
	-jar pct.jar \
	-war "$(pwd)/megawar.war" \
	-includePlugins "${PLUGINS}" \
	-workDirectory "$(pwd)/pct-work" \
	-reportFile "$(pwd)/pct-report.xml" \
	$PCT_S_ARG \
	-mavenProperties "${MAVEN_PROPERTIES}" \
	-skipTestCache true

if grep -q -F -e '<status>INTERNAL_ERROR</status>' pct-report.xml; then
	echo PCT failed
	cat pct-report.xml
	exit 1
elif grep -q -F -e '<status>TEST_FAILURES</status>' pct-report.xml; then
	echo PCT marked failed, checking to see if that is due to a failure to run tests at all
	for t in pct-work/*/{,*/}target; do
		check=false
		levels=$(echo "$t" | tr / '\n' | wc -l)
		short_name=$(echo "$t" | tr / '\n' | grep -v ^target$ | tail -1)
		if [[ $levels -lt 4 ]]; then
			# Single-module project or root module of multi-module
			# project: always check.
			check=true
		elif [[ $PLUGINS =~ $short_name ]]; then
			# Submodule of multi-module project: only check if the
			# directory name of the submodule is a substring of the
			# list of plugins we are testing.
			check=true
		fi
		if $check && [[ -f "${t}/test-classes/InjectedTest.class" ]] && [[ ! -f "${t}/surefire-reports/TEST-InjectedTest.xml" ]] && [[ ! -f "${t}/failsafe-reports/TEST-InjectedTest.xml" ]]; then
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

# TODO various problems with PCT itself (e.g. https://github.com/jenkinsci/bom/pull/338#issuecomment-715256727)
# and anyway the tests in PluginAutomaticTestBuilder are generally uninteresting in a PCT context
# We always try to run this test rather than adding it to excludes.txt in order
# to be able to detect if PCT failed to run tests at all a few lines above.
rm -fv pct-work/*/{,*/}target/surefire-reports/TEST-InjectedTest.xml

# produces: **/target/surefire-reports/TEST-*.xml
