// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '0 6 * * 5'
}

env.MAVEN_NTP = true

def fullTestLabel
def weeklyTestLabel
def limitedPluginSetLabel
if (env.CHANGE_ID) {
  fullTestLabel = pullRequest.labels.contains('full-test')
  weeklyTestLabel = pullRequest.labels.contains('weekly-test')
  limitedPluginSetLabel = pullRequest.labels.contains('limited-plugin-set')
}

def fixedPrepArchiveName = '' // can be set to a specific prep archive name in case last commits aren't impacting it

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
    pluginsByRepository[splits[0].split('/')[1]] = splits[1].split(',')
  }
  pluginsByRepository
}

def pluginsByRepository
def lines
def fullTestMarkerFile
def weeklyTestMarkerFile
def limitedPluginSetMarkerFile
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
def durations = [:]

mavenEnv(jdk: 21) {
  def scmVars = checkout scm
  def commitId = scmVars.GIT_COMMIT

  fullTestMarkerFile = fileExists 'full-test'
  weeklyTestMarkerFile = fileExists 'weekly-test'
  limitedPluginSetMarkerFile = fileExists 'limited-plugin-set'

  // Ensure prep archive corresponds to the current state
  def prepArchiveName = "bom-prep-${commitId}.tar.gz"
  def prepFoundInBuildNumber = 0

  stage('retrieve prep archive') {
    if (fixedPrepArchiveName) {
      prepArchiveName = fixedPrepArchiveName
      echo "[WARNING] Using fixed prep archive name ${fixedPrepArchiveName} instead of bom-prep-${commitId}.tar.gz"
    }
    prepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild(prepArchiveName, env.JOB_NAME)
    if (prepFoundInBuildNumber == 0) {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
        error("[INFO] ${prepArchiveName} not found")
      }
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
      def plugins = []
      def allLines = []
      def from = 'plugins.txt'
      if (limitedPluginSetLabel || limitedPluginSetMarkerFile) {
        from = 'a limited set of plugins'
        echo('[WARNING] Running on a limited set of plugins')

        // Limited set
        plugins = limitedPluginSet
        if (limitedPluginSetMarkerFile) {
          plugins = readFile('../limited-plugin-set').split('\n')
        }
        // Lines from sample-plugin
        allLines = sh (
            script: '''
              echo "weekly $(grep -F '.x</bom>' ../sample-plugin/pom.xml | sed -E 's, *<bom>(.+)</bom>,\\1,g' | sort -rn | xargs)"
            ''',
            returnStdout: true
            ).trim().split(' ')
      } else {
        plugins = readFile('plugins.txt').split('\n')
        allLines = readFile('lines.txt').split('\n')
      }
      pluginsByRepository = parsePlugins(plugins)
      echo "[INFO] ${pluginsByRepository.size()} repositories retrieved from ${from}"
      echo "[INFO] List of repositories and their plugins:\n${plugins.join('\n')}"

      newestAndOldestLines = [allLines[0], allLines[-1]] // Save resources by running PCT only on newest and oldest lines
      echo "[INFO] ${allLines.size()} lines retrieved from lines.txt: ${allLines.join(' ')} "

      // For archival, keeping track of newest and oldest lines as PR labels may change accross builds
      // For stashes, we only care about the lines of the current build
      lines = newestAndOldestLines
      if (weeklyTestMarkerFile || weeklyTestLabel) {
        echo "[INFO] Keeping only 'weekly' line as there is a 'weekly-test' label or marker file"
        lines = ['weekly']
      } else {
        echo "[INFO] Keeping only newest and oldest lines to save resources: ${lines.join(' ')} "
      }
    }
  }

  stage('archive new prep') {
    if (prepFoundInBuildNumber == 0) {
      def prepArchiveGlob = 'pct.sh excludes.txt bom-*/excludes.txt target/pct.jar target/plugins.txt target/lines.txt'
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
    } else {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
        error("[INFO] No new prep to archive")
      }
      return
    }
  }

  stage('stash prep lines') {
    if (lines.size() > 0) {
      lines.each { line ->
        stash name: line, includes: "pct.sh,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-${line}.war"
      }
    } else {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
        error('[INFO] No line to stash')
      }
      return
    }
  }
}

if (BRANCH_NAME == 'master' || fullTestMarkerFile || weeklyTestMarkerFile || env.CHANGE_ID && (fullTestLabel || weeklyTestLabel)) {
  def branches = [failFast: false]
  lines.each {line ->
    if (line != 'weekly' && (weeklyTestMarkerFile || env.CHANGE_ID && weeklyTestLabel)) {
      return
    }
    pluginsByRepository.each { repository, plugins ->
      branches["pct-$repository-$line"] = {
        def jdk = line == 'weekly' || line == '2.555.x' ? 21 : 17
        withChecks(name: 'Tests', includeStage: true) {
          mavenEnv(jdk: jdk) {
            unstash line
            withEnv([
              "PLUGINS=${plugins.join(',')}",
              "LINE=$line",
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
              }
            }
          }
        }
      }
    }
  }
  parallel branches
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
    error 'Remember to `git rm full-test` before taking out of draft'
  }
  if (limitedPluginSetMarkerFile) {
    error 'Remember to `git rm limited-plugin-set` before taking out of draft'
  }
  if (limitedPluginSetLabel) {
    error 'Remember to remove `limited-plugin-set` label before taking out of draft'
  }
}

infra.maybePublishIncrementals()


// === Helper functions

// Search and copy an artifact from builds of a job
// Returns the build number where it has been found, zero otherwise
def copyArtifactsFromAnyPreviousBuild(archiveName, jobName) {
  def foundInBuildNumber = 0
  def archiveExists = false
  def buildNumber = env.BUILD_NUMBER.toInteger()
  if (buildNumber == 1) {
    echo "[INFO] First build of ${jobName}, no ${archiveName} available yet"
  } else {
    // Loop over builds to retrieve the prep archive as previous build can have (only) other archive(s)
    def checkBuildNumber = buildNumber - 1
    // Don't loop until the first build of master '^^
    def limit = jobName.endsWith('master') ? buildNumber - 50 : 0
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
  }
  return foundInBuildNumber
}
