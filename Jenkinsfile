// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '10 0 * * 5'
}

env.MAVEN_NTP = true
def maxSplitsPerLine = 20

// Run pct tests on a limited set of repositories and their plugin(s) if not empty
// Ex: ['jenkinsci/badge-plugin\tbadge', 'jenkinsci/cron_column-plugin\tcron_column']
def limitedPluginSet = [
  'jenkinsci/aws-credentials-plugin	aws-credentials',
  'jenkinsci/aws-global-configuration-plugin	aws-global-configuration',
  'jenkinsci/azure-credentials-plugin	azure-credentials',
  'jenkinsci/azure-keyvault-plugin	azure-keyvault',
  'jenkinsci/azure-sdk-plugin	azure-sdk',
  'jenkinsci/azure-storage-plugin	windows-azure-storage',
  'jenkinsci/badge-plugin	badge',
  'jenkinsci/basic-branch-build-strategies-plugin	basic-branch-build-strategies',
  'jenkinsci/cron_column-plugin	cron_column',
  'jenkinsci/pipeline-maven-plugin	pipeline-maven,pipeline-maven-api,pipeline-maven-database',
]

properties([
  disableConcurrentBuilds(abortPrevious: true),
  buildDiscarder(logRotator(numToKeepStr: '7')),
  pipelineTriggers([cron(cronTrigger)])
])

if (env.BRANCH_NAME == 'master' && currentBuild.buildCauses*._class == ['jenkins.branch.BranchEventCause']) {
  currentBuild.result = 'NOT_BUILT'
  error 'No longer running builds on response to master branch pushes. If you wish to cut a release, use “Re-run checks” from this failing check in https://github.com/jenkinsci/bom/commits/master'
}

def mavenEnv(Map params = [:], Closure body) {
  def attempt = 0
  def attempts = 6
  retry(count: attempts, conditions: [kubernetesAgent(handleNonKubernetes: true), nonresumable()]) {
    echo 'Attempt ' + ++attempt + ' of ' + attempts
    // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
    node('maven-bom') {
      timeout(120) {
        infra.withArtifactCachingProxy {
          withEnv([
            'JAVA_HOME=/opt/jdk-' + params['jdk'],
            'PATH+JDK=/opt/jdk-' + params['jdk'] + '/bin',
            "MAVEN_ARGS=${env.MAVEN_ARGS != null ? MAVEN_ARGS : ''} -B ${env.MAVEN_NTP != null ? '-ntp' : ''} -Dmaven.repo.local=${WORKSPACE_TMP}/m2repo",
            "MVN_LOCAL_REPO=${WORKSPACE_TMP}/m2repo",
          ]) {
            infra.loadMavenLocalCacheIfAny(env.MVN_LOCAL_REPO)

            body()
          }
        }
      }
    }
  }
}

@NonCPS
def parsePlugins(plugins) {
  def pluginsByRepository = [:]
  plugins.each { plugin ->
    def splits = plugin.split('\t')
    pluginsByRepository[splits[0].split('/')[1]] = splits[1]
  }
  pluginsByRepository
}

def pluginsByRepository
def lines
def fullTestMarkerFile
def weeklyTestMarkerFile
def consumeIncrementalsMarkerFile
boolean fullTest = false
boolean weeklyTest = false
boolean consumeIncrementals = false
def splits = [:]
def durations = [:]

mavenEnv(jdk: 21) {
  stage('prep') {
    checkout scm
    consumeIncrementalsMarkerFile = fileExists 'consume-incrementals'
    consumeIncrementals = consumeIncrementalsMarkerFile || (env.CHANGE_ID && pullRequest.labels.contains('consume-incrementals'))
    if (!consumeIncrementals) {
      echo 'Forbidding use of incremental dependencies. If you need to consume incrementals, add the `consume-incrementals` label, or add a file named `consume-incrementals` to the repository root if you lack triage permission. Then keep this PR in draft until the dependencies have been switched to release versions.'
    }
    withChecks(name: 'Tests', includeStage: true) {
      withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist', "CONSUME_INCREMENTALS=${consumeIncrementals}"]) {
        sh '''
        mvn -v
        bash prep.sh
        '''
      }
      if (junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml').failCount > 0) {
        error 'Some test failures during prep.sh, not going to continue'
      }
    }
    infra.prepareToPublishIncrementals()

    fullTestMarkerFile = fileExists 'full-test'
    weeklyTestMarkerFile = fileExists 'weekly-test'
    fullTest = fullTestMarkerFile || (env.CHANGE_ID && pullRequest.labels.contains('full-test'))
    weeklyTest = weeklyTestMarkerFile || (env.CHANGE_ID && pullRequest.labels.contains('weekly-test'))

    def plugins = readFile('target/plugins.txt').split('\n')
    if (limitedPluginSet) {
      plugins = limitedPluginSet
      maxSplitsPerLine = 3
      echo "INFO: running on a limited plugin set (maxSplitsPerLine reduced to ${maxSplitsPerLine})"
    }
    pluginsByRepository = parsePlugins(plugins)

    lines = readFile('target/lines.txt').split('\n')
    lines = [lines[0], lines[-1]] // Save resources by running PCT only on newest and oldest lines
    if (weeklyTest && !(fullTest)) {
      echo 'INFO: keeping only "weekly" line'
      lines = ['weekly']
    }
    echo "${pluginsByRepository.size()} repositories:\n${plugins.join('\n')}"
    echo "${lines.size()} lines: ${lines.join(' ')} "

    // Fixed splits, each split using only one line
    lines.each { line ->
      pluginsByRepository.eachWithIndex { repository, repoPlugins, idx ->
        def index = (idx % maxSplitsPerLine) + 1 // to get split1 to split<maxSplitsPerLine>
        def name = "split-${index}:${line}"
        def repositoryAndPlugins = "${repository} ${repoPlugins}"

        splits[name] = splits[name] ?: []
        splits[name] << repositoryAndPlugins
      }
    }
    echo "${splits.size()} splits"
    echo splits.collect { split, combinations -> "${split} ${combinations}" }.join('\n')
  }
  stage('stash line(s)') {
    lines.each { line ->
      stash name: line, includes: "pct.sh,incrementals.sh,consume-incrementals,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-${line}.war"
    }
  }
}

if (BRANCH_NAME == 'master' || fullTest || weeklyTest) {
  stage('run pct') {
    def branches = [failFast: false]
    splits.each { split, combinations ->
      def line = split.split(':')[1]
      def jdk = line == 'weekly' || line == '2.555.x' ? 21 : 17
      branches[split] = {
        mavenEnv(jdk: jdk) {
          stage('unstash line') {
            unstash line
          }
          combinations.eachWithIndex { repositoryAndPlugins, idx ->
            def parts = repositoryAndPlugins.split(' ')
            def repository = parts[0]
            def plugins = parts[1]
            def combination = "${repository}:${line}"
            stage("${combination} (${idx + 1}/${combinations.size()})") {
              withChecks(name: "PCT / ${combination}") {
                withEnv([
                  "PLUGINS=${plugins}",
                  "LINE=$line",
                  "CONSUME_INCREMENTALS=${consumeIncrementals}",
                  'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=1'
                ]) {
                  def start = System.currentTimeMillis()
                  try {
                    sh '''
                    mvn -v
                    bash pct.sh
                    '''
                  } catch (e) {
                    if (!(e instanceof InterruptedException) && !(e instanceof org.jenkinsci.plugins.workflow.support.steps.AgentOfflineException)) {
                      unstable('PCT failed in ' + repository + ' - line ' + line)
                    } else {
                      throw e
                    }
                  } finally {
                    def elapsed = System.currentTimeMillis() - start
                    durations["pct-$repository-$line"] = (elapsed / 1000.0)
                    try {
                      // record test results (can be missing if the plugin couldn't be built)
                      junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml')
                    } catch(je) {
                      unstable "error junitResult: ${je}"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    parallel branches
  }
  stage('duration report') {
    node('maven-bom') {
      Double totalTime = 0
      def reportLines = ''
      durations.each { branch, time ->
        totalTime += time as Double
        reportLines += '<testcase name="' + branch + '" classname="pct-duration.' + branch + '" time="' + time + '"/>\n'
      }
      if (reportLines) {
        def content = """<?xml version="1.0" encoding="UTF-8"?>
          <testsuite name="bom" time="${totalTime}">
          ${reportLines}
          </testsuite>
        """
        writeFile file: 'bom-report.xml', text: content
        archiveArtifacts artifacts: 'bom-report.xml'
        junit allowEmptyResults: true, testResults: 'bom-report.xml'
      }
    }
  }
}

stage('checks') {
  if (fullTestMarkerFile) {
    unstable 'Remember to `git rm full-test` before taking out of draft'
  }
  if (weeklyTestMarkerFile) {
    unstable 'Remember to `git rm weekly-test` before taking out of draft'
  }
  if (consumeIncrementalsMarkerFile) {
    unstable 'Remember to `git rm consume-incrementals` before taking out of draft'
  }
  if (limitedPluginSet) {
    unstable 'Remember to empty `limitedPluginSet` in Jenkinsfile before taking out of draft'
  }
}

stage('publish incrementals') {
  infra.maybePublishIncrementals()
}
