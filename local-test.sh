#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

# TODO adapt to take a LINE=2.164.x arg
# expects: $PLUGINS, optionally $TEST

export SAMPLE_PLUGIN_OPTS=-Dtest=InjectedTest
bash prep.sh

rm -rf target/local-test
mkdir target/local-test
cp -v sample-plugin/target/{megawar.war,pct.jar} pct.sh target/local-test

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
           -e EXTRA_MAVEN_PROPERTIES=$EXTRA_MAVEN_PROPERTIES \
           --entrypoint bash \
           jenkins/jnlp-agent-maven \
           -c "trap 'chown -R $(id -u):$(id -g) /pct /var/maven/.m2/repository' EXIT; bash /pct/pct.sh"
else
    export EXTRA_MAVEN_PROPERTIES
    bash target/local-test/pct.sh
fi
