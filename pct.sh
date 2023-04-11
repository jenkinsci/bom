#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: megawar.war, pct.jar, excludes.txt, $PLUGINS, $LINE

rm -rf pct-work

PCT_D_ARGS=
if [[ -n ${EXTRA_MAVEN_PROPERTIES-} ]]; then
	for prop in ${EXTRA_MAVEN_PROPERTIES//:/ }; do
		PCT_D_ARGS+="-D${prop} "
	done
fi

exec java \
	-jar pct.jar \
	--war "$(pwd)/megawar.war" \
	--include-plugins "${PLUGINS}" \
	--working-dir "$(pwd)/pct-work" \
	$PCT_D_ARGS \
	-DforkCount=.75C \
	-Djth.jenkins-war.path="$(pwd)/megawar.war" \
	-Dsurefire.excludesFile="$(pwd)/excludes.txt"

# produces: **/target/surefire-reports/TEST-*.xml
