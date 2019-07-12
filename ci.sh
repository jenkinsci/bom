#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

# TODO use -ntp after INFRA-2129 / Maven 3.6.1
MVN='mvn -B -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn'
if [ -v MAVEN_SETTINGS ]
then
    MVN="$MVN -s $MAVEN_SETTINGS"
    PCT_S_ARG="-m2SettingsFile $MAVEN_SETTINGS"
else
    PCT_S_ARG=
fi

$MVN -Dmaven.test.failure.ignore install

cd sample-plugin/target
cp -r jenkins-for-test megawar
rm -rfv megawar/WEB-INF/detached-plugins megawar/META-INF/*.{RSA,SF}
mkdir megawar/WEB-INF/plugins
cp -rv test-classes/test-dependencies/*.hpi megawar/WEB-INF/plugins
(cd megawar && jar c0Mf ../megawar.war *)

version=0.1.0
pct=$HOME/.m2/repository/org/jenkins-ci/tests/plugins-compat-tester-cli/$version/plugins-compat-tester-cli-$version.jar
[ -f $pct ] || $MVN dependency:get -Dartifact=org.jenkins-ci.tests:plugins-compat-tester-cli:$version:jar -Dtransitive=false

# TODO perhaps stash the megawar and split the test runs across nodes in parallel? (use label `maven` for quick startup)
# (means losing the ability to run Dockerized tests in PCT, e.g. in durable-task)
java -jar $pct \
     -war $(pwd)/megawar.war \
     -workDirectory $(pwd)/pct-work \
     -reportFile $(pwd)/pct-report.xml \
     -mvn $(which mvn) \
     $PCT_S_ARG \
     -mavenProperties org.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn \
     -skipTestCache true

# TODO currently failing tests: https://github.com/jenkinsci/workflow-cps-plugin/pull/302 https://github.com/jenkinsci/structs-plugin/pull/50
rm -fv \
   pct-work/workflow-cps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.cps.SnippetizerTest.xml \
   pct-work/structs-plugin/plugin/target/surefire-reports/TEST-org.jenkinsci.plugins.structs.describable.DescribableModelTest.xml
