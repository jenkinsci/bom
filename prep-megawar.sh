#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${0}")"

# expects: $LINE

if [[ ! -d sample-plugin/target/test-classes/test-dependencies || ! -d sample-plugin/target/jenkins-for-test ]]; then
	if [[ $LINE == weekly ]]; then
		PROFILE=
	else
		PROFILE=-P$LINE
	fi
	mvn -pl sample-plugin clean test -Dtest=InjectedTest $PROFILE
fi

cd sample-plugin/target
mkdir jenkins
# TODO keep managed splits, overriding version with the managed one
echo '# nothing' >jenkins/split-plugins.txt
cp -r jenkins-for-test "megawar-${LINE}"
jar uvf megawar-$LINE/WEB-INF/lib/jenkins-core-*.jar jenkins/split-plugins.txt
rm -rfv megawar-$LINE/WEB-INF/detached-plugins megawar-$LINE/META-INF/*.{RSA,SF}
mkdir "megawar-${LINE}/WEB-INF/plugins"
cp -rv test-classes/test-dependencies/*.hpi "megawar-${LINE}/WEB-INF/plugins"
cd "megawar-${LINE}"
mkdir -p ../../../target
jar c0Mf "../../../target/megawar-${LINE}.war" *

# produces: target/megawar-*.war
