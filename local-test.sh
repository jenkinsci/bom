#!/usr/bin/env bash

set -euxo pipefail

cd "$(dirname "$0")"

# expects: $PLUGINS, optionally $TEST, $LINE

LATEST_LINE=weekly
: "${LINE:=$LATEST_LINE}"

if [[ -n ${SAMPLE_PLUGIN_OPTS} ]]; then
	SAMPLE_PLUGIN_OPTS+=' -Dtest=InjectedTest'
else
	SAMPLE_PLUGIN_OPTS='-Dtest=InjectedTest'
fi
if [[ $LINE != "${LATEST_LINE}" ]]; then
	SAMPLE_PLUGIN_OPTS+=" -P${LINE}"
fi
export SAMPLE_PLUGIN_OPTS
LINEZ=$LINE bash prep.sh

if [[ -n ${TEST-} ]]; then
	EXTRA_MAVEN_PROPERTIES="test=${TEST}"
else
	EXTRA_MAVEN_PROPERTIES=
fi

if [[ "${DOCKERIZED-}" == "true" ]]; then
	docker volume inspect m2repo || docker volume create m2repo
	docker run \
		-v ~/.m2:/var/maven/.m2 \
		--rm \
		--name bom-pct \
		-v "$(pwd):/pct" \
		-e MAVEN_OPTS=-Duser.home=/var/maven \
		-e MAVEN_CONFIG=/var/maven/.m2 \
		-e "PLUGINS=${PLUGINS}" \
		-e "LINE=${LINE}" \
		-e "EXTRA_MAVEN_PROPERTIES=${EXTRA_MAVEN_PROPERTIES}" \
		--entrypoint bash \
		maven \
		-c "trap 'chown -R $(id -u):$(id -g) /pct /var/maven/.m2/repository' EXIT; bash /pct/pct.sh"
else
	export EXTRA_MAVEN_PROPERTIES
	LINE=$LINE bash pct.sh
fi
