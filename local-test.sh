#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

# expects: $PLUGINS, optionally $TEST, $LINE

LATEST_LINE=$(ls -1d bom-*.x | sort -rn | head -1 | sed s/bom-//g)
: "${LINE:=$LATEST_LINE}"

export SAMPLE_PLUGIN_OPTS=-Dtest=InjectedTest
if [ $LINE \!= $LATEST_LINE ]
then
    export SAMPLE_PLUGIN_OPTS="$SAMPLE_PLUGIN_OPTS -P$LINE"
fi
LINEZ=$LINE bash prep.sh

rm -rf target/local-test
mkdir target/local-test
cp -v target/pct.jar pct.sh target/local-test
cp -v target/megawar-$LINE.war target/local-test/megawar.war

if [ -v TEST ]
then
    EXTRA_MAVEN_PROPERTIES="test=$TEST"
else
    EXTRA_MAVEN_PROPERTIES=
fi

if [ -v DOCKERIZED ]
then
    docker volume inspect m2repo || docker volume create m2repo
    docker run \
           -v ~/.m2:/var/maven/.m2 \
           --rm \
           --name bom-pct \
           -v $(pwd)/target/local-test:/pct \
           -e MAVEN_OPTS=-Duser.home=/var/maven \
           -e MAVEN_CONFIG=/var/maven/.m2 \
           -e PLUGINS=$PLUGINS \
           -e LINE=$LINE \
           -e EXTRA_MAVEN_PROPERTIES=$EXTRA_MAVEN_PROPERTIES \
           --entrypoint bash \
           jenkins/jnlp-agent-maven \
           -c "trap 'chown -R $(id -u):$(id -g) /pct /var/maven/.m2/repository' EXIT; bash /pct/pct.sh"
else
    export EXTRA_MAVEN_PROPERTIES
    LINE=$LINE bash target/local-test/pct.sh
fi
