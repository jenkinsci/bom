// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '0 15 * * 5'
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
  'limited-plugin-set': [] as Set,
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

final String[] limitedPluginSet = [
  'jenkinsci/aws-credentials-plugin	aws-credentials',
  'jenkinsci/aws-global-configuration-plugin	aws-global-configuration',
  'jenkinsci/azure-credentials-plugin	azure-credentials',
  'jenkinsci/azure-keyvault-plugin	azure-keyvault',
  'jenkinsci/azure-sdk-plugin	azure-sdk',
  'jenkinsci/azure-storage-plugin	windows-azure-storage',
  'jenkinsci/badge-plugin	badge',
  'jenkinsci/basic-branch-build-strategies-plugin	basic-branch-build-strategies',
  'jenkinsci/cron_column-plugin	cron_column',
  'jenkinsci/pipeline-maven-plugin	pipeline-maven,pipeline-maven-api,pipeline-maven-database', // longer than the others, multiple plugins
]

mavenEnv(jdk: 21) {
  String prepArchiveName
  stage('init') {
    Map scmVars = checkout scm

    // Ensure prep archive corresponds to the current state
    commitId = scmVars.GIT_COMMIT.substring(0, 7)
    prepArchiveName = "bom-prep-${commitId}.tar.gz"
    if (fixedPrepArchiveName) {
      echo "[WARNING] Using fixed prep archive name ${fixedPrepArchiveName} instead of ${prepArchiveName}"
      prepArchiveName = fixedPrepArchiveName
    } else {
      echo "[INFO] Using prep archive name ${prepArchiveName}"
    }

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

  stage('retrieve prep archive') {
    prepFoundInBuildNumber = retrieveArtifactsFromPreviousBuilds(prepArchiveName, env.JOB_NAME)
    if (prepFoundInBuildNumber == 0) {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') { error("[SKIP] ${prepArchiveName} not found") }
      return
    }
  }

  stage('prep') {
    if (prepFoundInBuildNumber == 0) {
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
    } else {
      withEnv(["ARCHIVE_NAME=${prepArchiveName}"]) {
        sh '''
        tar xzfv "${ARCHIVE_NAME}"
        rm "${ARCHIVE_NAME}"
        '''
        echo "[INFO] ${prepArchiveName} retrieved and extracted, no need to run prep.sh"
      }
    }
  }

  stage('parse prep') {
    dir('target') {
      String[] plugins = []
      String[] allLines = []
      String from = 'plugins.txt'

      if (flagEnabled(flags, 'limited-plugin-set')) {
        from = 'a limited set of plugins'
        echo('[WARNING] Running on a limited set of plugins')

        // Limited set from marker file if it exists
        plugins = fileExists('../limited-plugin-set') ? readFile('../limited-plugin-set').readLines() : limitedPluginSet
        // Lines from sample-plugin
        allLines = sh (returnStdout: true, script: '''
          echo "weekly $(grep -F '.x</bom>' ../sample-plugin/pom.xml | sed -E 's, *<bom>(.+)</bom>,\\1,g' | sort -rn | xargs)"
        ''').trim().split(' ')
      } else {
        plugins = readFile('plugins.txt').readLines()
        allLines = readFile('lines.txt').readLines()
      }

      pluginsByRepository = parsePlugins(plugins)
      echo "[INFO] ${pluginsByRepository.size()} repositories retrieved from ${from}"
      echo "[INFO] List of repositories and their plugins:\n${plugins.join('\n')}"

      echo "[INFO] ${allLines.size()} lines retrieved from lines.txt: ${allLines.join(' ')} "

      // For archival, keeping track of newest and oldest lines as PR labels may change accross builds
      // For stashes, we only care about the final lines of the current build
      newestAndOldestLines = [allLines.first(), allLines.last()] // Save resources by running PCT only on newest and oldest lines
      lines = newestAndOldestLines
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

  stage('archive new prep') {
    if (prepFoundInBuildNumber > 0) {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') { error("[SKIP] No new prep to archive") }
      return
    }

    String prepArchiveGlob = 'pct.sh excludes.txt bom-*/excludes.txt target/pct.jar target/plugins.txt target/lines.txt'
    // Both newest and oldest lines in the prep archive, in case labels change on PR accross builds
    // ex: from weekly-test to full-test
    newestAndOldestLines.each { line ->
      prepArchiveGlob += " target/megawar-${line}.war"
    }
    withEnv(["ARCHIVE_NAME=${prepArchiveName}", "ARCHIVE_GLOB=${prepArchiveGlob}",]) {
      sh 'tar czfv "${ARCHIVE_NAME}" ${ARCHIVE_GLOB}'
      archiveArtifacts artifacts: prepArchiveName, fingerprint: true
      echo "[INFO] New ${prepArchiveName} archived"
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
                def junitResults
                try {
                  junitResults = junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml')
                } catch(e) {
                  echo "[WARNING] Error junitResult: ${e}"
                }
                Map result = [
                  failCount : junitResults?.failCount  ?: 0,
                  skipCount : junitResults?.skipCount  ?: 0,
                  passCount : junitResults?.passCount  ?: 0,
                  totalCount: junitResults?.totalCount ?: 0,
                  duration  : junitResults?.duration   ?: 0,
                ]
                result.elapsed = elapsed
                result.plugins = plugins.join(',')
                result.pluginCount = plugins.size()
                result.attempt = currentAttempt
                result.build_id = env.BUILD_ID
                result.job_base_name = env.JOB_BASE_NAME
                result.short_commit_id = commitId.substring(0, 7)

                results[branchName] = result
                echo "[INFO] results for ${branchName}: ${result}"
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
      totalCount: 0,
      skipCount : 0,
      failCount : 0
    ]) { acc, r ->
      acc.elapsed    += r.elapsed
      acc.totalCount += r.totalCount
      acc.skipCount  += r.skipCount
      acc.failCount  += r.failCount
      acc
    }
    totals.resultsCount = results.size()

    final String reportLines = results.collect { combination, result ->
      final String normalized = combination.replaceAll('[-:.]', '_')
      """<testcase name="${combination}" classname="pct-duration.${normalized}" time="${result.elapsed}" tests="${result.totalCount}" failures="${result.failCount}" skipped="${result.skipCount}"/>"""
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

  // Mark build as unstable on PR with limited-plugin-set
  if (flagEnabled(flags, 'limited-plugin-set', 'label')) {
    unstable 'Remember to remove `limited-plugin-set` label before taking out of draft'
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

// Search and copy an artifact from builds of a job
// Returns the build number where it has been found, zero otherwise
int retrieveArtifactsFromPreviousBuilds(String archiveName, String jobName) {
  int foundInBuildNumber = 0
  boolean archiveExists = false
  final int buildNumber = env.BUILD_NUMBER.toInteger()
  if (buildNumber == 1) {
    echo "[INFO] First build of ${jobName}, no ${archiveName} available yet"
    return 0
  }

  // Loop over builds to retrieve the prep archive as previous build can have (only) other archive(s)
  int checkBuildNumber = buildNumber - 1
  // Don't loop until the first build of master '^^
  final int limit = jobName.endsWith('master') ? buildNumber - 50 : 0
  while (!archiveExists && checkBuildNumber > limit) {
    echo "[INFO] Trying to retrieve ${archiveName} from ${jobName}#${checkBuildNumber}..."
    try {
      copyArtifacts(projectName: jobName,
      selector: specific("${checkBuildNumber}"),
      filter: archiveName,
      fingerprintArtifacts: true,
      optional: false,
      )
      archiveExists = true
    } catch(e) {}
    if (!archiveExists) {
      checkBuildNumber = checkBuildNumber - 1
    }
  }
  if (!archiveExists) {
    echo "[INFO] No ${archiveName} found in any build of ${jobName}"
  } else {
    foundInBuildNumber = checkBuildNumber
    echo "[INFO] ${archiveName} found in ${jobName}#${checkBuildNumber}"
  }
  return foundInBuildNumber
}
