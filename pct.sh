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
if ! [[ $PLUGINS =~ blueocean || $PLUGINS =~ lockable-resources || $PLUGINS =~ pipeline-maven ]]; then
	#
	# The Blue Ocean, Lockable Resources, and Pipeline Maven Integration
	# test suites use a lot of memory and cannot handle parallelism.
	#
	PCT_D_ARGS+='-DforkCount=.75C '
fi

exec java \
	-jar target/pct.jar \
	test-plugins \
	--war "$(pwd)/target/megawar-$LINE.war" \
	--include-plugins "${PLUGINS}" \
	--working-dir "$(pwd)/target/pct-work" \
	$PCT_D_ARGS \
	${PCT_OPTS-} \
	-Dsurefire.excludesFile="$(pwd)/excludes.txt"

# produces: **/target/surefire-reports/TEST-*.xml
