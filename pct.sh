#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

# expects: megawar.war, pct.war, $PLUGINS

rm -rf pct-work pct-report.xml

if [ -v MAVEN_SETTINGS ]
then
    PCT_S_ARG="-m2SettingsFile $MAVEN_SETTINGS"
else
    PCT_S_ARG=
fi

MAVEN_PROPERTIES=org.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn:jth.jenkins-war.path=$(pwd)/megawar.war
if [ -v EXTRA_MAVEN_PROPERTIES ]
then
    MAVEN_PROPERTIES="$MAVEN_PROPERTIES:$EXTRA_MAVEN_PROPERTIES"
fi

java -jar pct.jar \
     -war $(pwd)/megawar.war \
     -includePlugins $PLUGINS \
     -workDirectory $(pwd)/pct-work \
     -reportFile $(pwd)/pct-report.xml \
     -mvn $(which mvn) \
     $PCT_S_ARG \
     -mavenProperties "$MAVEN_PROPERTIES" \
     -skipTestCache true

# TODO https://github.com/jenkinsci/workflow-cps-plugin/pull/302
rm -fv pct-work/workflow-cps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.cps.SnippetizerTest.xml
# TODO https://github.com/jenkinsci/structs-plugin/pull/50
rm -fv pct-work/structs-plugin/plugin/target/surefire-reports/TEST-org.jenkinsci.plugins.structs.describable.DescribableModelTest.xml
# TODO https://github.com/jenkinsci/jenkins/pull/4120 problems with workflow-cps → jquery-detached:
rm -fv pct-work/structs-plugin/plugin/target/surefire-reports/TEST-InjectedTest.xml

# produces: pct-report.xml, **/target/surefire-reports/TEST-*.xml
