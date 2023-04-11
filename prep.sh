#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "${0}")"

mvn clean install ${SAMPLE_PLUGIN_OPTS:-}

ALL_LINEZ=$(
	echo weekly
	grep -F '.x</bom>' sample-plugin/pom.xml | sed -E 's, *<bom>(.+)</bom>,\1,g' | sort -rn
)
: "${LINEZ:=$ALL_LINEZ}"
echo "${LINEZ}" >target/lines.txt

rebuild=false
for LINE in $LINEZ; do
	if $rebuild; then
		mvn -f sample-plugin clean package ${SAMPLE_PLUGIN_OPTS:-} "-P${LINE}"
	else
		rebuild=true
		pushd sample-plugin/target/test-classes/test-dependencies
		ls -1 *.hpi | sed s/.hpi//g >../../../../target/plugins.txt
		popd
	fi
	if [[ -n ${CI-} ]]; then
		if [[ ${LINE} != weekly ]]; then
			PROFILE="-P${LINE}"
		fi
		# TODO https://github.com/jenkinsci/maven-hpi-plugin/pull/464
		mvn \
			-f sample-plugin \
			hpi:resolve-test-dependencies \
			${SAMPLE_PLUGIN_OPTS:-} \
			${PROFILE:-} \
			-DoverrideWar="../target/megawar-${LINE}.war" \
			-DuseUpperBounds \
			-Dhpi-plugin.version=3.42-rc1409.669de6d1a_866 \
			-DcommitHashes=target/commit-hashes.txt
		mv sample-plugin/target/commit-hashes.txt "target/commit-hashes-${LINE}.txt"
	fi
done

# produces: target/{commit-hashes-*.txt,plugins.txt,lines.txt}
