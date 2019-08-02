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

# TODO use -ntp if there is a PCT option to pass Maven options
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

if fgrep -q '<status>INTERNAL_ERROR</status>' pct-report.xml
then
    echo PCT failed
    exit 1
fi

# TODO rather than removing all these, have a text file of known failures and just convert them to “skipped”

# TODO https://github.com/jenkinsci/jenkins/pull/4120 problems with workflow-cps → jquery-detached:
rm -fv pct-work/structs-plugin/plugin/target/surefire-reports/TEST-InjectedTest.xml
rm -fv pct-work/apache-httpcomponents-client-4-api/target/surefire-reports/TEST-InjectedTest.xml
rm -fv pct-work/ssh-slaves/target/surefire-reports/TEST-InjectedTest.xml
rm -fv pct-work/plain-credentials/target/surefire-reports/TEST-InjectedTest.xml
# TODO pending https://github.com/jenkinsci/ansicolor-plugin/pull/164
rm -fv pct-work/ansicolor/target/surefire-reports/TEST-hudson.plugins.ansicolor.AnsiColorBuildWrapperTest.xml
# TODO https://github.com/jenkinsci/matrix-project-plugin/pull/59
rm -fv pct-work/matrix-project/target/surefire-reports/TEST-InjectedTest.xml
# TODO pending https://github.com/jenkinsci/git-plugin/pull/738
rm -fv pct-work/git/target/surefire-reports/TEST-hudson.plugins.git.CredentialsUserRemoteConfigTest.xml
# TODO https://github.com/jenkinsci/jenkins/pull/4099 pending backport to 2.176.3
rm -fv pct-work/command-launcher/target/surefire-reports/TEST-hudson.slaves.CommandLauncher2Test.xml
# TODO https://github.com/jenkinsci/durable-task-plugin/pull/101
rm -fv pct-work/durable-task/target/surefire-reports/TEST-org.jenkinsci.plugins.durabletask.BourneShellScriptTest.xml
# TODO https://github.com/jenkinsci/git-client-plugin/pull/440
rm -fv pct-work/git-client/target/surefire-reports/TEST-hudson.plugins.git.GitExceptionTest.xml
# TODO fails for one reason in (non-PCT) official sources, run locally; and for another reason in PCT in Docker; passes in official sources in Docker, or locally in PCT
rm -fv pct-work/git-client/target/surefire-reports/TEST-org.jenkinsci.plugins.gitclient.FilePermissionsTest.xml
# TODO pending https://github.com/jenkinsci/workflow-api-plugin/pull/99
rm -fv pct-work/workflow-api/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.log.FileLogStorageTest.xml

# produces: pct-report.xml, **/target/surefire-reports/TEST-*.xml
