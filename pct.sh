#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: target/megawar-$LINE.war, target/pct.jar, $PLUGINS, $LINE

rm -rf pct-work

PCT_D_ARGS=
if [[ -n ${EXTRA_MAVEN_PROPERTIES-} ]]; then
	for prop in ${EXTRA_MAVEN_PROPERTIES//:/ }; do
		PCT_D_ARGS+="-D${prop} "
	done
fi

exec java \
	-jar target/pct.jar \
	test-plugins \
	--war "$(pwd)/target/megawar-$LINE.war" \
	--include-plugins "${PLUGINS}" \
	--working-dir "$(pwd)/pct-work" \
	$PCT_D_ARGS \
	-DforkCount=.75C \
	-Djth.jenkins-war.path="$(pwd)/target/megawar-$LINE.war" \
	-Dsurefire.excludesFile="$(pwd)/excludes.txt"

# produces: **/target/surefire-reports/TEST-*.xml
