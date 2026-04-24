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
if ! [[ $PLUGINS =~ lockable-resources || $PLUGINS =~ pipeline-maven ]]; then
	#
	# The Lockable Resources and Pipeline Maven Integration
	# test suites use a lot of memory and cannot handle parallelism.
	#
	PCT_D_ARGS+='-DforkCount=.75C '
fi

EXCLUDES_FILE="$(pwd)/excludes.txt"
if [ -f "$(pwd)/bom-${LINE}/excludes.txt" ]; then
	# Create a temporary excludes file, remove it when the shell exits
	EXCLUDES_FILE="$(mktemp -t excludes-${LINE}-XXX.txt)"
	trap 'rm -f -- "$EXCLUDES_FILE"' EXIT
	cat excludes.txt bom-${LINE}/excludes.txt > "${EXCLUDES_FILE}"
fi

exec java \
	-Dorg.jenkins.tools.test.hook.JenkinsTestHarnessHook2.enabled \
	-jar target/pct.jar \
	test-plugins \
	--war "$(pwd)/target/megawar-$LINE.war" \
	--include-plugins "${PLUGINS}" \
	--working-dir "$(pwd)/target/pct-work" \
	$PCT_D_ARGS \
	${PCT_OPTS-} \
	-Dsurefire.excludesFile="${EXCLUDES_FILE}"

# produces: **/target/surefire-reports/TEST-*.xml
