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

if grep -q -F -e '<status>INTERNAL_ERROR</status>' pct-report.xml
then
    echo PCT failed
    cat pct-report.xml
    exit 1
elif grep -q -F -e '<status>TEST_FAILURES</status>' pct-report.xml
then
    echo PCT marked failed, checking to see if that is due to a failure to run tests at all
    for t in pct-work/*/{,*/}target
    do
        if [ -f $t/test-classes/InjectedTest.class -a \! -f $t/surefire-reports/TEST-InjectedTest.xml ]
        then
            mkdir -p $t/surefire-reports
            cat > $t/surefire-reports/TEST-pct.xml <<'EOF'
<testsuite name="pct">
  <testcase classname="pct" name="overall">
    <error message="some sort of PCT problem; look at logs"/>
  </testcase>
</testsuite>
EOF
        fi
    done
fi

# TODO rather than removing all these, have a text file of known failures and just convert them to “skipped”
# or add surefire.excludesFile to MAVEN_PROPERTIES so we do not waste time even running these

# TODO various problems with PCT itself (e.g. https://github.com/jenkinsci/bom/pull/338#issuecomment-715256727)
# and anyway the tests in PluginAutomaticTestBuilder are generally uninteresting in a PCT context
rm -fv pct-work/*/{,*/}target/surefire-reports/TEST-InjectedTest.xml

# TODO pending https://github.com/jenkinsci/jdk-tool-plugin/pull/12
rm -rf pct-work/jdk-tool/target/surefire-reports/TEST-hudson.tools.JDKInstallerTest.xml

# TODO pending https://github.com/jenkinsci/workflow-cps-global-lib-plugin/pull/96
rm -rf pct-work/workflow-cps-global-lib/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.libs.GlobalLibrariesTest.xml

# TODO Merged, but needs a release: https://github.com/jenkinsci/git-plugin/pull/857
rm -fv pct-work/git/target/surefire-reports/TEST-hudson.plugins.git.GitStatusCrumbExclusionTest.xml

# TODO flakey tests related to workflow-job saying it's finished but it still hasn't finished updating the log
# ref: https://github.com/jenkinsci/workflow-job-plugin/pull/131/files#r291657569
# https://github.com/jenkinsci/workflow-support-plugin/pull/105
# https://github.com/jenkinsci/workflow-durable-task-step-plugin/pull/130
# https://github.com/jenkinsci/workflow-basic-steps-plugin/pull/110 analogue for CatchErrorStepTest
rm -fv pct-work/workflow-basic-steps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.steps.CatchErrorStepTest.xml
rm -fv pct-work/workflow-support/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.support.pickles.serialization.SerializationSecurityTest.xml
rm -fv pct-work/workflow-durable-task-step/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.steps.durable_task.ShellStepTest.xml
rm -fv pct-work/workflow-durable-task-step/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.support.steps.ExecutorStepTest.xml
rm -fv pct-work/workflow-cps/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.cps.FlowDurabilityTest.xml
rm -fv pct-work/junit/target/surefire-reports/TEST-hudson.tasks.junit.pipeline.JUnitResultsStepTest.xml
# https://github.com/jenkinsci/workflow-job-plugin/pull/158
rm -fv pct-work/workflow-job/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.job.WorkflowRunRestartTest.xml

# TODO pending https://github.com/jenkinsci/ansicolor-plugin/pull/164
rm -fv pct-work/ansicolor/target/surefire-reports/TEST-hudson.plugins.ansicolor.AnsiColorBuildWrapperTest.xml
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

# TODO cryptic PCT-only errors: https://github.com/jenkinsci/bom/pull/251#issuecomment-645012427
rm -fv pct-work/matrix-project/target/surefire-reports/TEST-hudson.matrix.AxisTest.xml

# TODO remove after timestamper upgrades to next bom https://github.com/jenkinsci/bom/pull/294#issuecomment-710770375
rm -fv pct-work/timestamper/target/surefire-reports/TEST-hudson.plugins.timestamper.ConfigurationAsCodeTest.xml

# TODO https://github.com/jenkinsci/workflow-multibranch-plugin/pull/102
rm -fv pct-work/workflow-multibranch/target/surefire-reports/TEST-org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProjectTest.xml

# produces: **/target/surefire-reports/TEST-*.xml
