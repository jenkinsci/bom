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
		bash prep-pct.sh
		LINE=$LINE bash prep-megawar.sh
		java \
			-jar target/pct.jar \
			list-plugins \
			--war "target/megawar-${LINE}.war" \
			--output "target/plugins.txt"
	fi
	if [[ -n ${CI-} ]]; then
		if [[ ${LINE} != weekly ]]; then
			LINE=$LINE bash prep-megawar.sh
			PROFILE="-P${LINE}"
		fi
		# TODO https://github.com/jenkinsci/maven-hpi-plugin/pull/464
		mvn \
			-f sample-plugin \
			hpi:resolve-test-dependencies \
			${SAMPLE_PLUGIN_OPTS:-} \
			${PROFILE:-} \
			-DuseUpperBounds \
			-DcommitHashes=target/commit-hashes.txt
		mv sample-plugin/target/commit-hashes.txt "target/commit-hashes-${LINE}.txt"
	fi
done

# produces: target/{commit-hashes-*.txt,plugins.txt,lines.txt}
