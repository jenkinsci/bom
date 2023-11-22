#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: excludes.txt, target/megawar-$LINE.war, target/pct.jar, $PLUGINS, $LINE

rm -rf target/pct-work

PCT_D_ARGS=
if [[ -n ${EXTRA_MAVEN_PROPERTIES-} ]]; then
	for prop in ${EXTRA_MAVEN_PROPERTIES//:/ }; do
		PCT_D_ARGS+="-D${prop} "
	done
fi
if ! [[ $PLUGINS =~ blueocean || $PLUGINS =~ pipeline-maven ]]; then
	#
	# The Blue Ocean and Pipeline Maven Integration test suites use a lot of
	# memory and cannot handle parallelism.
	#
	PCT_D_ARGS+='-DforkCount=.75C '
fi
if [[ $PLUGINS =~ data-tables-api || $PLUGINS =~ echarts-api || $PLUGINS =~ prism-api ]]; then
       #
       # These plugins use a version of ArchUnit which triggers a
       # requireUpperBoundDeps error with JUnit 5:
       #
       # +-io.jenkins.plugins:data-tables-api:1.13.8-1
       # +-com.tngtech.archunit:archunit-junit5:1.2.0 [test]
       # +-com.tngtech.archunit:archunit-junit5-engine:1.2.0 [test]
       # +-com.tngtech.archunit:archunit-junit5-engine-api:1.2.0 [test]
       # +-org.junit.platform:junit-platform-engine:1.10.0 [test] (managed)
       #   <-- org.junit.platform:junit-platform-engine:1.10.1 [test]
       #
       # Since PCT will automatically resolve requireUpperBoundDeps errors by
       # choosing the newer version, and since the newer version is not
       # ABI-compatible with the older version, exclude this package from PCT's
       # requireUpperBoundDeps resolution.
       #
       # TODO: When these plugins are fixed to not trigger a requireUpperBoundDeps
       # error, this code should be removed.
       #
       PCT_D_ARGS+='-DupperBoundsExcludes=org.junit.platform:junit-platform-commons '
fi

exec java \
	-jar target/pct.jar \
	test-plugins \
	--war "$(pwd)/target/megawar-$LINE.war" \
	--include-plugins "${PLUGINS}" \
	--working-dir "$(pwd)/target/pct-work" \
	$PCT_D_ARGS \
	-Djth.jenkins-war.path="$(pwd)/target/megawar-$LINE.war" \
	-Dsurefire.excludesFile="$(pwd)/excludes.txt"

# produces: **/target/surefire-reports/TEST-*.xml
