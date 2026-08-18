// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '10 0 * * 4'
}

env.MAVEN_NTP = true
def maxSplitsPerLine = 20

// Run pct tests on a limited set of repositories and their plugin(s) if not empty
// Ex: ['jenkinsci/badge-plugin\tbadge', 'jenkinsci/cron_column-plugin\tcron_column']
def limitedPluginSet = []

properties([
  // disableConcurrentBuilds(abortPrevious: true),
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
    def provisioningStart = System.currentTimeMillis()
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
            "PROVISONING_START=${provisioningStart}",
            "CURRENT_ATTEMPT=${attempt}",
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
def fullTest = false
def weeklyTest = false
def consumeIncrementals = false
def splits = [:]
def results = [:]
def commit
def pctDuration

mavenEnv(jdk: 21) {
  stage('prep') {
    commit = checkout(scm).GIT_COMMIT.take(7)

    // Debug: retrieve prep from archive
    copyArtifacts(projectName: 'Tools/bom/prep-only', selector: lastWithArtifacts(), filter: 'prep.tar.gz', fingerprintArtifacts: true)
    publishChecks(name: 'Tests / prep')
    sh 'tar -xzvf prep.tar.gz && rm prep.tar.gz'

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
    echo "${lines.size()} lines: ${lines.join(' ')}"

    // Fixed splits, each split using only one line
    lines.each { line ->
      pluginsByRepository.eachWithIndex { repository, repoPlugins, idx ->
        def index = (idx % maxSplitsPerLine) + 1 // to get split1 to split<maxSplitsPerLine>
        def name = "split-${index}:${line}"
        splits[name] = splits[name] ?: []
        splits[name] << repository
      }
    }
    echo "${splits.size()} split(s)"
    echo splits.collect { split, repositories ->
      "${split} (${repositories.size()}) ${repositories}"
    }.join('\n')
  }
  stage('stash line(s)') {
    lines.each { line ->
      stash name: line, includes: "pct.sh,incrementals.sh,consume-incrementals,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-${line}.war"
    }
  }
}

if (BRANCH_NAME == 'master' || fullTest || weeklyTest) {
  stage('run pct') {
    def pctStart = System.currentTimeMillis()
    def branches = [failFast: false]
    splits.each { split, repositories ->
      def line = split.split(':')[1]
      def jdk = line == 'weekly' || line == '2.555.x' ? 21 : 17
      branches["${split} [${repositories.size()}]"] = {
        echo "In this split: ${repositories.join(',')}"
        mavenEnv(jdk: jdk) {
          def provisionStart = env.PROVISONING_START.toLong()
          def readyIn = (System.currentTimeMillis() - provisionStart) / 1000.0
          echo "INFO: agent ready to run pct in ${readyIn}s"
          stage('unstash line') {
            unstash line
          }
          repositories.eachWithIndex { repository, idx ->
            def combination = "${repository}:${line}"
            // if the tests ran with success in a previous attempt, skip the combination (ex: in case of reclaimed spot agent)
            def previousResult = results[combination] ?: [totalCount: 0, failCount: 0]
            if (previousResult.totalCount> 0 && previousResult.failCount == 0) {
              echo "${combination} has already ran ${previousResult.totalCount} test(s) with success in a previous attempt, skipping"
            } else {
              stage("${combination} (${idx + 1}/${repositories.size()})") {
                withChecks(name: "PCT / ${combination}") {
                  withEnv([
                    "PLUGINS=${pluginsByRepository[repository]}",
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
                        publishChecks status: 'COMPLETED', conclusion: 'FAILURE', title: 'Tests could not be executed'
                        unstable('PCT failed in ' + repository + ' - line ' + line)
                      } else {
                        throw e
                      }
                    } finally {
                      // record test results (can be missing if the plugin couldn't be built)
                      def junitResults = junit allowEmptyResults: true, testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml'
                      results[combination] = [
                        'elapsed': (System.currentTimeMillis() - start) / 1000.0,
                        'totalCount': junitResults ? junitResults.totalCount : 0,
                        'failCount': junitResults ? junitResults.failCount : 0,
                        'split': split,
                        'readyIn': readyIn,
                        'attempt': env.CURRENT_ATTEMPT,
                      ]
                    }
                  }
                }
              }
              echo "${combination}: ${results[combination]['totalCount']} tests executed in ${results[combination]['elapsed']}s"
            }
          }
          def totalTime = (System.currentTimeMillis() - provisionStart) / 1000.0
          def runningTime = totalTime - readyIn
          echo "INFO: pct tests of ${split} took ${runningTime}s"
        }
      }
    }
    parallel branches
    pctDuration = (System.currentTimeMillis() - pctStart) / 1000.0
    echo "INFO: pct tests took ${pctDuration}s in total"
  }
  node('maven-bom') {
    stage('reports') {
      def branches = [:]
      lines.each { line ->
        def testSuiteName = "bom-report_${line}"
        // We need junit records in distinct stages later on for splitTests
        // Otherwise it would try to balance all repositories across all lines
        // While we want one line per split (agent)
        branches[testSuiteName] = {
          def testCases = []
          results.each { combination, result ->
            def repository = combination.split(':')[0]
            def resultLine = combination.split(':')[1]
            if (line == resultLine) {
              testCases << '<testcase split="' + result['split'] + '" name="' + repository + '" classname="pct-report.' + repository + '" time="' + result['elapsed'] + '" readyin="' + result['readyIn'] + '" attempt="' + result['attempt'] + '"/>\n'
            }
          }
          def content = """<?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="${testSuiteName}" line="${line}" pctduration="${pctDuration}" commit="${commit}" build="${env.BUILD_URL}">
            ${testCases.sort().join('\n')}
            </testsuite>
          """
          writeFile file: "${testSuiteName}.xml", text: content
          junit testResults: "${testSuiteName}.xml"
          archiveArtifacts artifacts: "${testSuiteName}.xml"
        }
      }
      parallel branches
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
}
