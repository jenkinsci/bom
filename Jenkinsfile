// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '40 13 * * 5'
}

// === Actionable in replay
env.MAVEN_NTP = true
// Can be set to a specific prep archive name in case last commits aren't impacting it
final String fixedPrepArchiveName = ''
// Test flags depending on the presence of corresponding labels or marker files
// Can be modified to test specific cases independently of the current PR labels or markers
// Possible value(s): 'label', 'marker'
Map flags = [
  'weekly-test': [] as Set,
  'full-test': [] as Set,
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

// Collect flags from labels
if (env.CHANGE_ID) {
  flags.each { name, sources ->
    if (pullRequest.labels.contains(name)) {
      sources << 'label'
    }
  }
}

void mavenEnv(Map params = [:], Closure body) {
  int attempt = 0
  final int attempts = 6
  retry(count: attempts, conditions: [kubernetesAgent(handleNonKubernetes: true), nonresumable()]) {
    echo '[INFO] Attempt ' + ++attempt + ' of ' + attempts
    // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
    node('maven-bom') {
      timeout(120) {
        infra.withArtifactCachingProxy {
          withEnv([
            'JAVA_HOME=/opt/jdk-' + params['jdk'],
            'PATH+JDK=/opt/jdk-' + params['jdk'] + '/bin',
            "MAVEN_ARGS=${env.MAVEN_ARGS != null ? MAVEN_ARGS : ''} -B ${env.MAVEN_NTP != null ? '-ntp' : ''} -Dmaven.repo.local=${WORKSPACE_TMP}/m2repo",
            "MVN_LOCAL_REPO=${WORKSPACE_TMP}/m2repo",
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

String commitId
int prepFoundInBuildNumber = 0
Map pluginsByRepository = [:]
List lines = []
List newestAndOldestLines = []
Map results = [:]

mavenEnv(jdk: 21) {
  stage('init') {
    Map scmVars = checkout scm

    // Collect flags from marker files
    flags.each { name, sources ->
      if (fileExists(name)) {
        sources << 'marker'
      }
    }
    echo '[INFO] Flags:\n' + flags.collect { name, conditions ->
      final String desc = conditions ? conditions.join(' & ') : 'none'
      "  - ${name.padRight(20)} : ${desc}"
    }.join('\n')
  }

  stage('prep') {
    withChecks(name: 'Tests', includeStage: true) {
      withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
        sh '''
        mvn -v
        bash prep.sh
        '''
        if (junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml').failCount > 0) {
          error 'Some test failures during prep.sh, not going to continue'
        }
        // Publish incrementals before prep archive preparation to avoid dirty git status
        infra.prepareToPublishIncrementals()
      }
    }
  }

  stage('parse prep') {
    dir('target') {
      String[] plugins = []
      String[] allLines = []
      String from = 'plugins.txt'

      plugins = readFile('plugins.txt').readLines()
      allLines = readFile('lines.txt').readLines()

      pluginsByRepository = parsePlugins(plugins)
      echo "[INFO] ${pluginsByRepository.size()} repositories retrieved from ${from}"
      echo "[INFO] List of repositories and their plugins:\n${plugins.join('\n')}"

      echo "[INFO] ${allLines.size()} lines retrieved from lines.txt: ${allLines.join(' ')} "

      lines = [allLines.first(), allLines.last()] // Save resources by running PCT only on newest and oldest lines
      echo "[INFO] Keeping only newest and oldest lines to save resources: ${lines.join(' ')} "
      if (flagEnabled(flags, 'weekly-test')) {
        lines = ['weekly']
        echo "[WARNING] Keeping only 'weekly' line as there is a 'weekly-test' label or marker file"
      }
      if (BRANCH_NAME != 'master' && !(flagEnabled(flags, 'full-test') || flagEnabled(flags, 'weekly-test'))) {
        lines = []
        catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
          error('[SKIP] Removing all lines, build not from master or running without any "weekly-test" / "full-test" flags')
        }
        return
      }
    }
  }

  stage('stash prep lines') {
    if (lines.isEmpty()) {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') { error('[SKIP] No line to stash') }
      return
    }

    echo "[INFO] Stashing ${lines.join(' & ')}"
    lines.each { line ->
      stash name: line, includes: "pct.sh,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-${line}.war"
    }
  }
}

stage('run pct') {
  if (lines.isEmpty()) {
    catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
      error('[SKIP] No line to run')
    }
    return
  }

  Map branches = [failFast: false]
  lines.each {line ->
    pluginsByRepository.each { repository, plugins ->
      final String branchName = "${repository}:${line}"
      branches[branchName] = {
        final int jdk = line == 'weekly' ? 21 : 17
        withChecks(name: 'Tests', includeStage: true) {
          mavenEnv(jdk: jdk) {
            unstash line
            withEnv([
              "PLUGINS=${plugins.join(',')}",
              "LINE=$line",
              'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=1'
            ]) {
              final long start = System.currentTimeMillis()
              int currentAttempt = env.CURRENT_ATTEMPT.toInteger()
              echo "[INFO] Current attempt: ${currentAttempt}"

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
                final double elapsed = (System.currentTimeMillis() - start) / 1000.0
                results[branchName] = [:]
                results[branchName]['elapsed'] = elapsed
                echo "[INFO] results for ${branchName}: ${results[branchName]}"
              }
            }
          }
        }
      }
    }
  }
  parallel branches
}

stage('report results') {
  if (results.isEmpty()) {
    catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') { error('[SKIP] No result to report') }
    return
  }

  node('maven-bom') {
    Map totals = results.values().inject([
      elapsed   : 0d,
    ]) { acc, r ->
      acc.elapsed    += r.elapsed
      acc
    }
    totals.resultsCount = results.size()

    final String reportLines = results.collect { combination, result ->
      final String normalized = combination.replaceAll('[-:.]', '_')
      """<testcase name="${combination}" classname="pct-duration.${normalized}" time="${result.elapsed}"/>"""
    }.join('\n')

    final String xmlReport = """<?xml version="1.0" encoding="UTF-8"?>
    <testsuite name="bom" time="${totals.elapsed}" tests="${totals.resultsCount}">
      ${reportLines}
    </testsuite>
    """

    final String txtReport = results.collect { combination, result ->
      "name=${combination};" + result.collect { k, v -> "${k}=${v}" }.join(';')
    }.sort().join('\n')

    writeFile file: 'bom-report.xml', text: xmlReport
    writeFile file: 'bom-report.txt', text: txtReport
    archiveArtifacts artifacts: 'bom-report.*'
    junit allowEmptyResults: true, testResults: 'bom-report.xml'

    echo "[INFO] Aggregates from ${totals.resultsCount} result(s):\n${totals}"
  }
}

stage('flag checks') {
  // Mark build as failed on any marker file
  def markerErrors = flags.findAll { flag, sources -> 'marker' in sources }.keySet()
  if (!markerErrors.isEmpty()) {
    error "Remember to `git rm ${markerErrors.join(' ')}` before taking out of draft"
  }
}

stage('publish incrementals') {
  if (prepFoundInBuildNumber > 0) {
    catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') { error('[SKIP] No new prep to publish to incrementals') }
    return
  }
  infra.maybePublishIncrementals()
}

// === Helper functions

@NonCPS
Map parsePlugins(plugins) {
  Map pluginsByRepository = [:]
  plugins.each { plugin ->
    String[] splits = plugin.split('\t')
    pluginsByRepository[splits[0].split('/')[1]] = splits[1].split(',')
  }
  pluginsByRepository
}

// Return if a test flag is set
// If only a flag is passed, return true if there is a corresponding label and/or marker file
// If a flag and a source like 'marker' or 'label' are passed, return true if there is that source
boolean flagEnabled(Map flags, String flag, String source = null) {
  source ? source in flags[flag] : !flags[flag].isEmpty()
}
