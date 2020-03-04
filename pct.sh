#!/bin/bash
set -euxo pipefail
cd "$(dirname "$0")"

# expects: megawar.war, pct.war, $PLUGINS, $LINE

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
     -war "$(pwd)/megawar.war" \
     -includePlugins "${PLUGINS}" \
     -workDirectory "$(pwd)/pct-work" \
     -reportFile "$(pwd)/pct-report.xml" \
     $PCT_S_ARG \
     -mavenProperties "${MAVEN_PROPERTIES}" \
     -skipTestCache true

if grep -F -q '<status>INTERNAL_ERROR</status>' pct-report.xml
then
    echo PCT failed
    exit 1
fi

# TODO rather than removing all these, have a text file of known failures and just convert them to “skipped”
if [ "$LINE" != 2.190.x ]
then
    # TODO https://github.com/jenkinsci/jenkins/pull/4120 problems with workflow-cps → jquery-detached:
    rm -fv pct-work/structs-plugin/plugin/target/surefire-reports/TEST-InjectedTest.xml
    rm -fv pct-work/apache-httpcomponents-client-4-api/target/surefire-reports/TEST-InjectedTest.xml
    rm -fv pct-work/ssh-slaves/target/surefire-reports/TEST-InjectedTest.xml
    rm -fv pct-work/plain-credentials/target/surefire-reports/TEST-InjectedTest.xml
    # TODO https://github.com/jenkinsci/jenkins/pull/4099
    rm -fv pct-work/command-launcher/target/surefire-reports/TEST-hudson.slaves.CommandLauncher2Test.xml

    # TODO wrong detached plugin is being picked up
    # JavaScript GUI Lib: jQuery bundles (jQuery and jQuery UI) plugin v1.2 is older than required. To fix, install v1.2.1 or later.
    # we have 1.12.4-1 managed currently
    rm -fv pct-work/trilead-api/target/surefire-reports/TEST-InjectedTest.xml
fi

# TODO wrong detached plugin is being picked up
# Structs Plugin version 1.7 is older than required. To fix, install version 1.20 or later.
# we have 1.20 managed currently
rm -fv pct-work/cloudbees-folder/target/surefire-reports/TEST-InjectedTest.xml

# TODO flakey tests related to workflow-job saying it's finished but it still hasn't finished updating the log
# ref: https://github.com/jenkinsci/workflow-job-plugin/pull/131/files#r291657569
# https://github.com/jenkinsci/workflow-support-plugin/pull/105
# https://github.com/jenkinsci/workflow-durable-task-step-plugin/pull/130
# https://github.com/jenkinsci/workflow-basic-steps-plugin/pull/110
rm -fv pct-work/workflow-basic-steps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.steps.WaitForConditionStepTest.xml
rm -fv pct-work/workflow-basic-steps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.support.steps.stash.StashTest.xml
rm -fv pct-work/workflow-support/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.support.pickles.serialization.SerializationSecurityTest.xml
rm -fv pct-work/workflow-durable-task-step/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.support.steps.ExecutorStepTest.xml
rm -fv pct-work/workflow-cps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.cps.FlowDurabilityTest.xml
rm -fv pct-work/junit/target/surefire-reports/TEST-hudson.tasks.junit.pipeline.JUnitResultsStepTest.xml

# TODO pending https://github.com/jenkinsci/ansicolor-plugin/pull/164
rm -fv pct-work/ansicolor/target/surefire-reports/TEST-hudson.plugins.ansicolor.AnsiColorBuildWrapperTest.xml
# TODO https://github.com/jenkinsci/matrix-project-plugin/pull/59
rm -fv pct-work/matrix-project/target/surefire-reports/TEST-InjectedTest.xml
# TODO https://github.com/jenkinsci/durable-task-plugin/pull/101
rm -fv pct-work/durable-task/target/surefire-reports/TEST-org.jenkinsci.plugins.durabletask.BourneShellScriptTest.xml
# TODO https://github.com/jenkinsci/git-client-plugin/pull/440
rm -fv pct-work/git-client/target/surefire-reports/TEST-hudson.plugins.git.GitExceptionTest.xml
# TODO fails for one reason in (non-PCT) official sources, run locally; and for another reason in PCT in Docker; passes in official sources in Docker, or locally in PCT
rm -fv pct-work/git-client/target/surefire-reports/TEST-org.jenkinsci.plugins.gitclient.FilePermissionsTest.xml
# TODO pending non-beta release of https://github.com/jenkinsci/git-client-plugin/pull/478 (or #479 backport)
rm -fv pct-work/git-client/target/surefire-reports/TEST-org.jenkinsci.plugins.gitclient.{CliGitAPIImplTest,JGitAPIImplTest,JGitApacheAPIImplTest}.xml
# TODO https://github.com/jenkinsci/configuration-as-code-plugin/pull/1243
rm -fv pct-work/configuration-as-code-plugin/plugin/target/surefire-reports/TEST-io.jenkins.plugins.casc.ConfigurationAsCodeTest.xml

# produces: **/target/surefire-reports/TEST-*.xml
