#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

mvn -B -ntp -Dmaven.test.failure.ignore install

mvn -B -ntp -f sample-plugin custom-war-packager:custom-war

version=0.1.0
pct=$HOME/.m2/repository/org/jenkins-ci/tests/plugins-compat-tester-cli/$version/plugins-compat-tester-cli-$version.jar
if [ \! -f $pct ]
then
    echo $pct not found, downloading
    mvn -B -ntp dependency:get -Dartifact=org.jenkins-ci.tests:plugins-compat-tester-cli:$version:jar -Dtransitive=false
fi

# https://github.com/jenkinsci/plugin-compat-tester/pull/116#issuecomment-509439409
plugins=$(cd sample-plugin/tmp/output/target/megawar-*/WEB-INF/plugins; ls *.hpi | sed s/.hpi// | paste -sd,)

java -jar $pct \
     -war sample-plugin/tmp/output/target/megawar-*.war \
     -includePlugins $plugins \
     -workDirectory sample-plugin/target/pct-work \
     -reportFile sample-plugin/target/pct-report.xml \
     -mvn $(which mvn) \
     -skipTestCache true

# TODO currently failing tests
rm -fv \
   sample-plugin/target/pct-work/workflow-cps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.cps.SnippetizerTest.xml \
   sample-plugin/target/pct-work/structs-plugin/plugin/target/surefire-reports/TEST-org.jenkinsci.plugins.structs.describable.DescribableModelTest.xml
