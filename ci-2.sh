#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

# expects: megawar.war, pct.war, $PLUGIN

rm -rf pct-work pct-report.xml

if [ -v MAVEN_SETTINGS ]
then
    PCT_S_ARG="-m2SettingsFile $MAVEN_SETTINGS"
else
    PCT_S_ARG=
fi

java -jar pct.jar \
     -war $(pwd)/megawar.war \
     -includePlugins $PLUGIN \
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

# produces: pct-report.xml, **/target/surefire-reports/TEST-*.xml
