#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

# expects: $PLUGINS, optionally $TEST

export SAMPLE_PLUGIN_OPTS=-Dtest=InjectedTest
bash prep.sh

rm -rf target/local-test
mkdir target/local-test
cp -v sample-plugin/target/{megawar.war,pct.jar} pct.sh target/local-test

cd target/local-test
if [ -v TEST ]
then
    export EXTRA_MAVEN_PROPERTIES="test=$TEST"
fi
bash pct.sh
