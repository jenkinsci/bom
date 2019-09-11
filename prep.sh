#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

rm -rf sample-plugin/target

MVN='mvn -B -ntp'
if [ -v MAVEN_SETTINGS ]
then
    MVN="$MVN -s $MAVEN_SETTINGS"
fi

$MVN -Dmaven.test.failure.ignore install ${SAMPLE_PLUGIN_OPTS:-}

cd sample-plugin/target
cp -r jenkins-for-test megawar
mkdir jenkins
echo '# nothing' > jenkins/split-plugins.txt
jar uvf megawar/WEB-INF/lib/jenkins-core-*.jar jenkins/split-plugins.txt
rm -rfv megawar/WEB-INF/detached-plugins megawar/META-INF/*.{RSA,SF}
mkdir megawar/WEB-INF/plugins
cp -rv test-classes/test-dependencies/*.hpi megawar/WEB-INF/plugins
(cd megawar && jar c0Mf ../megawar.war *)

# TODO find a way to encode this in some POM so that it can be managed by Dependabot
version=0.2.1
timestamp=20190911.153925-1 # TODO https://github.com/jenkinsci/plugin-compat-tester/pull/181
pct=$HOME/.m2/repository/org/jenkins-ci/tests/plugins-compat-tester-cli/${version}-SNAPSHOT/plugins-compat-tester-cli-${version}-${timestamp}.jar
[ -f $pct ] || $MVN dependency:get -Dartifact=org.jenkins-ci.tests:plugins-compat-tester-cli:${version}-${timestamp}:jar -DremoteRepositories=https://repo.jenkins-ci.org/public/ -Dtransitive=false

cp $pct pct.jar
cd megawar/WEB-INF/plugins
echo -n *.hpi | sed s/.hpi//g > ../../../plugins.txt

# produces: sample-plugin/target/{megawar.war,pct.jar,plugins.txt}
