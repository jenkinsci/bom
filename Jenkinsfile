// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '57 11 * * 5'
}

env.MAVEN_NTP = true
def MAX_SPLITS = 10
def limitedPluginSet = false
def reportName = 'bom-report'
def pluginsByRepository
def lines
def fullTestMarkerFile
def weeklyTestMarkerFile
def results = [:]

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
    echo 'Attempt ' + ++attempt + ' of ' + attempts
    // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
    node('maven-bom') {
      timeout(120) {
        withChecks(name: 'Tests', includeStage: true) {
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
          // TODO: only when param.prep == false, fail with -DskipTests otherwise
          // TODO: put that in the branch loop, as unstable
          // if (junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml').failCount > 0) {
          //   // TODO JENKINS-27092 throw up UNSTABLE status in this case
          //   error 'Some test failures, not going to continue'
          // }
        }
      }
    }
  }
}

def copyArtifactsFromAnyPreviousBuild(archiveName, jobName) {
  def foundInBuildNumber = 0
  def archiveExists = false
  def buildNumber = env.BUILD_NUMBER.toInteger()
  if (buildNumber == 1) {
    echo 'INFO: first build, no prep archive available yet'
  } else {
    // Loop over builds to retrieve the prep archive as previous build can have (only) other archive(s)
    def checkBuildNumber = buildNumber - 1
    // Don't loop until the first build of master '^^
    def limit = jobName.endsWith('master') ? buildNumber - 10 : 0
    while (!archiveExists && checkBuildNumber > limit) {
      echo "Trying to retrieve prep archive from buid #${checkBuildNumber}..."
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
      echo "No ${archiveName} found in any build of ${jobName}"
    } else {
      foundInBuildNumber = checkBuildNumber
      echo "${archiveName} found in build #${foundInBuildNumber} of ${jobName}"
    }
  }
  return foundInBuildNumber
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

@NonCPS
def parseReport(String content) {
  echo "parseReport..."
  content.readLines().collect { line ->
    def parts = line.trim().split(':')
    def name = parts[0]
    Double duration = parts[1].toDouble()
    int failures = parts[2].toInteger()

    [
      name: name,
      duration: duration,
      failures: failures
    ]
  }
}

@NonCPS
def splitReports(List items, int maxSplits) {
  echo "splitReports..."
  // initialize buckets
  def buckets = (0..<maxSplits).collect {
    [total: 0.0, items: []]
  }

  // sort by duration DESC (largest first)
  def sorted = items.sort { -it.duration }

  sorted.each { item ->
    // pick the bucket with smallest total duration
    def target = buckets.min { it.total }

    target.items << item
    target.total += item.duration
  }

  return buckets
}

stage ('debug') {
  def splits = splitTests parallelism: count(MAX_SPLITS), stage: 'results report'
  echo "splits.size(): ${splits.size()}"
  splits.eachWithIndex { split, idx ->
    echo "splits[${idx}].size(): ${split.size()}"
    echo "splits[${idx}]: ${split}"
  }
}

stage('prep') {
  mavenEnv(jdk: 21) {
    def scmVars = checkout scm
    // Ensure prep archive corresponds to the current state
    def prepArchiveName = "bom-prep-${scmVars.GIT_COMMIT}.tar.gz"
    def prepArchiveExists = false
    def prepArchiveGlob = 'pct.sh excludes.txt bom-*/excludes.txt target/pct.jar target/plugins.txt target/lines.txt'
    def prepFoundInBuildNumber = 0
    def reportprepFoundInBuildNumber = 0

    stage('search prep') {
      prepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild(prepArchiveName, env.JOB_NAME)
    }

    stage('prep.sh') {
      if (prepFoundInBuildNumber == 0) {
        withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist', "ARCHIVE_NAME=${prepArchiveName}",]) {
          sh '''
          mvn -v
          bash prep.sh
          '''
          // Publish incrementals before prep archive preparation to avoid dirty git status
          infra.prepareToPublishIncrementals()
        }
      } else {
        withEnv(["ARCHIVE_NAME=${prepArchiveName}"]) {
          sh '''
          tar xzfv "${ARCHIVE_NAME}"
          rm "${ARCHIVE_NAME}"
          '''
          echo "INFO: ${prepArchiveName} retrieved from build #${prepFoundInBuildNumber}"
        }
      }
    }

    stage('archive prep') {
      if (prepFoundInBuildNumber == 0) {
        // Prepare prep archive
        withEnv(["ARCHIVE_NAME=${prepArchiveName}", "ARCHIVE_GLOB=${prepArchiveGlob}",]) {
          sh 'tar czfv "${ARCHIVE_NAME}" ${ARCHIVE_GLOB}'
          archiveArtifacts artifacts: prepArchiveName, fingerprint: true
          echo "INFO: new ${prepArchiveName} archived"
        }
      } else {
        echo "INFO: no new prep to archive"
      }
    }

    stage('search previous report') {
      reportprepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild("${reportName}.txt", env.JOB_NAME)
      // If not found in current build fallback to master
      if (reportprepFoundInBuildNumber == 0) {
        // TODO: use a direct copyArtifact with an appropriate selector? (lastSuccessful(), lastArchived(), etc.)
        reportprepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild("${reportName}.txt", 'Tools/bom/master')
      }
    }

    stage('split report') {
      if (reportprepFoundInBuildNumber > 0) {
        def content = readFile("${reportName}.txt")
        def tests = parseReport(content)
        def buckets = splitReports(tests, MAX_SPLITS)
        buckets.eachWithIndex { bucket, i ->
          echo "Split #${i} (total: ${bucket.total})"
          bucket.items.each {
            echo "  - ${it.name} (${it.duration})"
          }
        }
      }
      sh "cat ${reportName}.txt || true"
    }

    stage('parse prep') {
      fullTestMarkerFile = fileExists 'full-test'
      weeklyTestMarkerFile = fileExists 'weekly-test'
      dir('target') {
        def plugins = []
        if (limitedPluginSet || pullRequest.labels.contains('limited-plugin-set')) {
          echo "WARNING: running on a limited set of plugins"
          plugins = [
            'jenkinsci/aws-credentials-plugin	aws-credentials',
            'jenkinsci/aws-global-configuration-plugin	aws-global-configuration',
            'jenkinsci/azure-credentials-plugin	azure-credentials',
            'jenkinsci/azure-keyvault-plugin	azure-keyvault',
            'jenkinsci/azure-sdk-plugin	azure-sdk',
            'jenkinsci/azure-storage-plugin	windows-azure-storage',
            'jenkinsci/azure-vm-agents-plugin	azure-vm-agents',
            'jenkinsci/badge-plugin	badge',
            'jenkinsci/basic-branch-build-strategies-plugin	basic-branch-build-strategies',
            'jenkinsci/pipeline-maven-plugin	pipeline-maven,pipeline-maven-api,pipeline-maven-database',
          ]
        } else {
          plugins = readFile('plugins.txt').split('\n')
        }
        pluginsByRepository = parsePlugins(plugins)

        lines = readFile('lines.txt').split('\n')
        lines = [lines[0], lines[-1]] // Save resources by running PCT only on newest and oldest lines
      }
      lines.each { line ->
        stash name: line, includes: "pct.sh,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-${line}.war"
        prepArchiveGlob += " target/megawar-${line}.war"
      }
    }
  }
}

if (BRANCH_NAME == 'master' || fullTestMarkerFile || weeklyTestMarkerFile || env.CHANGE_ID && (pullRequest.labels.contains('full-test') || pullRequest.labels.contains('weekly-test'))) {
  stage('parallel') {
    def branches = [failFast: false]
    lines.each {line ->
      if (line != 'weekly' && (weeklyTestMarkerFile || env.CHANGE_ID && pullRequest.labels.contains('weekly-test'))) {
        return
      }
      pluginsByRepository.each { repository, plugins ->
        def branchName = "${repository}_${line.replaceAll('\\.', '-')}"
        branches[branchName] = {
          def jdk = line == 'weekly' || line == '2.555.x' ? 21 : 17
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
                junitResults = junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml')
                results[branchName] = [:]
                results[branchName]['elapsed'] = (elapsed / 1000.0)
                results[branchName]['pluginCount'] = plugins.size()
                results[branchName]['plugins'] = plugins.join(',')
                results[branchName]['failCount'] = junitResults.failCount
                results[branchName]['skipCount'] = junitResults.skipCount
                results[branchName]['passCount'] = junitResults.passCount
                results[branchName]['totalCount'] = junitResults.totalCount
                results[branchName]['duration'] = junitResults.duration
                try {
                  echo "results[${branchName}]: ${results[branchName]}"
                } catch(e) {
                  echo "error: ${e}"
                }
              }
            }
          }
        }
      }
    }
    parallel branches
  }
  stage('results report') {
    node('maven-bom') {
      // TODO: export to its own @NonCPS function
      Double totalElapsed = 0
      Double totalDuration = 0
      int totalFailCount = 0
      int totalSkipCount = 0
      int totalPassCount = 0
      int totalTotalCount = 0
      def reportLines = ''
      results.each { branch, result ->
        Double elapsed = result['elapsed']
        Double duration = result['duration']
        int failCount = result['failCount']
        int skipCount = result['skipCount']
        int passCount = result['passCount']
        int totalCount = result['totalCount']
        totalElapsed += elapsed
        totalDuration += duration
        totalFailCount += failCount
        totalSkipCount += skipCount
        totalPassCount += passCount
        totalTotalCount += totalCount
        def normalizedBranch = branch.replaceAll('-', '_')
        reportLines += '<testcase name="' + branch + '" classname="pct-duration.' + normalizedBranch + '" time="' + elapsed + '" failures="' + failCount + '"/>\n'
        // TODO: try after only setting name, no classname
      }
      if (reportLines) {
        def content = """<?xml version="1.0" encoding="UTF-8"?>
          <testsuite name="org.jenkins.ci.bom" time="${totalElapsed}" tests="${totalTotalCount}" skipped="${totalSkipCount}" failures="${totalFailCount}">
          ${reportLines}
          </testsuite>
        """
        writeFile file: "${reportName}.xml", text: content
        junit allowEmptyResults: true, testResults: "${reportName}.xml"
      }

      def reportLinesJson = results.collect { branch, result ->
        """{"name":"${branch}","elapsed":${result['elapsed']},"duration":${result['duration']},"failCount":${result['failCount']},"skipCount":${result['skipCount']},"passCount":${result['passCount']},"totalCount":${result['totalCount']}}"""
      }.join(',')
      def contentJson = """{"jobs": [${reportLinesJson}]}"""
      writeFile file: "${reportName}.json", text: contentJson

      def reportLinesTxt = results.collect { branch, result ->
        "${branch}:${result['elapsed']}:${result['failCount']}"
      }.join('\n')
      writeFile file: "${reportName}.txt", text: reportLinesTxt

      sh "cat ${reportName}.xml || true"
      sh "cat ${reportName}.json || true"
      sh "cat ${reportName}.txt || true"
      archiveArtifacts artifacts: "${reportName}.*", allowEmpty: true
    }
  }
}

if (fullTestMarkerFile) {
  error 'Remember to `git rm full-test` before taking out of draft'
}

infra.maybePublishIncrementals()
