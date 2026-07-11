// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '57 11 * * 5'
}

def weeklyTestLabel = pullRequest.labels.contains('weekly-test')
def fullTestLabel = pullRequest.labels.contains('full-test')
def limitedPluginSetLabel = pullRequest.labels.contains('limited-plugin-set')

env.MAVEN_NTP = true
def MAX_SPLITS = 5
def reportName = '' // can be overriden
// TODO: get limited set from a marker file?
def limitedPluginSet = [
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

properties([
  // disableConcurrentBuilds(abortPrevious: true),
  buildDiscarder(logRotator(numToKeepStr: '7')),
  pipelineTriggers([cron(cronTrigger)])
])

if (env.BRANCH_NAME == 'master' && currentBuild.buildCauses*._class == ['jenkins.branch.BranchEventCause']) {
  currentBuild.result = 'NOT_BUILT'
  error 'No longer running builds on response to master branch pushes. If you wish to cut a release, use “Re-run checks” from this failing check in https://github.com/jenkinsci/bom/commits/master'
}

def mavenNode(Map params = [:], Closure body) {
  def attempt = 0
  def attempts = 6
  retry(count: attempts, conditions: [kubernetesAgent(handleNonKubernetes: true), nonresumable()]) {
    echo 'Attempt ' + ++attempt + ' of ' + attempts
    // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
    node('maven-bom') {
      timeout(120) {
        withEnv([
          "MAVEN_ARGS=${env.MAVEN_ARGS != null ? MAVEN_ARGS : ''} -B ${env.MAVEN_NTP != null ? '-ntp' : ''} -Dmaven.repo.local=${WORKSPACE_TMP}/m2repo",
          "MVN_LOCAL_REPO=${WORKSPACE_TMP}/m2repo",
        ]) {
          infra.loadMavenLocalCacheIfAny(env.MVN_LOCAL_REPO)
          mavenEnv(params, body)
        }
      }
    }
  }
}

def mavenEnv(Map params = [:], Closure body) {
  withChecks(name: 'Tests', includeStage: true) {
    infra.withArtifactCachingProxy {
      withEnv([
        'JAVA_HOME=/opt/jdk-' + params['jdk'],
        'PATH+JDK=/opt/jdk-' + params['jdk'] + '/bin',
      ]) {
        body()
      }
    }
  }
}

def copyArtifactsFromAnyPreviousBuild(archiveName, jobName) {
  def foundInBuildNumber = 0
  def archiveExists = false
  def buildNumber = env.BUILD_NUMBER.toInteger()
  if (buildNumber == 1) {
    echo "INFO: first build of ${jobName}, no ${archiveName} available yet"
  } else {
    // Loop over builds to retrieve the prep archive as previous build can have (only) other archive(s)
    def checkBuildNumber = buildNumber - 1
    // Don't loop until the first build of master '^^
    def limit = jobName.endsWith('master') ? buildNumber - 10 : 0
    while (!archiveExists && checkBuildNumber > limit) {
      echo "Trying to retrieve ${archiveName} from ${jobName}#${checkBuildNumber}..."
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
      echo "${archiveName} found in ${jobName}#${checkBuildNumber}"
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
    def plugins = parts[3]

    [
      name: name,
      duration: duration,
      failures: failures,
      plugins: plugins,
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

@NonCPS
def getAllCombinations(pluginsByRepository, lines, weeklyOnly) {
  def combinations = [:]
  lines.each {line ->
    if (line != 'weekly' && weeklyOnly) {
      return
    }
    def normalizedLine = line.replaceAll('\\.', '-')
    pluginsByRepository.each { repository, plugins ->
      combinations["${repository}_${normalizedLine}"] = plugins.join(',')
    }
  }
  combinations
}

// TODO: if there is a time for a repo-line but not repo-anotherLine,
// use that first time as default estimation and resplit from there
@NonCPS
def getBucketCombinations(buckets, allCombinations) {
  def bucketCombinations = [:]
  def seen = new HashSet()
  buckets.eachWithIndex { bucket, idx ->
    def splitIndex = "split${idx}-${bucket.size()}"
    bucketCombinations[splitIndex] = [:]
    bucket.items.each {
      def combination = it.name
      if (!seen.contains(combination)) {
        seen.add(combination)
        bucketCombinations[splitIndex][combination] = allCombinations[combination]
        echo "${combination} added to ${splitIndex} (plugins: ${it.plugins})"
      } else {
        echo "${combination} already seen in a split"
      }
    }
  }
  echo "seen.size() before completion: ${seen.size()}"
  echo "bucketCombinations.size() after completion: ${bucketCombinations.size()}"

  // Ensure all combinations are present in bucketCombinations
  // Each in their own bucket
  allCombinations.each { combination, plugins ->
    if (!seen.contains(combination)) {
      seen.add(combination)
      bucketCombinations["new_${combination}"][combination] = allCombinations[combination]
      echo "${combination} added to new"
    }
  }
  echo "seen.size() after completion: ${seen.size()}"
  echo "bucketCombinations.size() after completion: ${bucketCombinations.size()}"
  echo "final bucketCombinations: ${bucketCombinations}"

  bucketCombinations
}

@NonCPS
def resultFromJunitResults(junitResults, plugins) {
  def result = [:]
  result['elapsed'] = (elapsed / 1000.0)
  result['plugins'] = plugins
  result['pluginCount'] = plugins.count(',')
  result['failCount'] = junitResults.failCount
  result['skipCount'] = junitResults.skipCount
  result['passCount'] = junitResults.passCount
  result['totalCount'] = junitResults.totalCount
  result['duration'] = junitResults.duration
  echo "result: ${result}"
  result
}

def pluginsByRepository
def lines
def fullTestMarkerFile
def weeklyTestMarkerFile
def results = [:]
def previousResults = [:]
def batches = [:]

// stage ('debug splitTests') {
//   def splits = splitTests parallelism: count(MAX_SPLITS), stage: 'report results'
//   echo "splits.size(): ${splits.size()}"
//   splits.eachWithIndex { split, idx ->
//     echo "splits[${idx}].size(): ${split.size()}"
//     echo "splits[${idx}]: ${split}"
//   }
// }

mavenNode(jdk: 21) {
  def scmVars = checkout scm

  fullTestMarkerFile = fileExists 'full-test'
  weeklyTestMarkerFile = fileExists 'weekly-test'

  // Report name depending on labels and marker files, by order of prevalence
  // or reportName if not empty
  if (!reportName) {
    if (fullTestLabel || fullTestMarkerFile) {
      reportName = 'bom-report-full'
    }
    if (weeklyTestLabel || weeklyTestMarkerFile) {
      reportName = 'bom-report-weekly'
    }
    if (limitedPluginSetLabel) {
      reportName = 'bom-report-limited'
    }
  }

  // Ensure prep archive corresponds to the current state
  def prepArchiveName = "bom-prep-${scmVars.GIT_COMMIT}.tar.gz"
  def prepArchiveExists = false
  def prepArchiveGlob = 'pct.sh excludes.txt bom-*/excludes.txt target/pct.jar target/plugins.txt target/lines.txt'
  def prepFoundInBuildNumber = 0
  def reportprepFoundInBuildNumber = 0

  stage('search prep archive') {
    prepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild(prepArchiveName, env.JOB_NAME)
  }

  stage('prep') {
    if (prepFoundInBuildNumber == 0) {
      withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist', "ARCHIVE_NAME=${prepArchiveName}",]) {
        sh '''
        mvn -v
        bash prep.sh
        '''
        if (junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml').failCount > 0) {
          // TODO JENKINS-27092 throw up UNSTABLE status in this case
          error 'Some test failures, not going to continue'
        }
        // Publish incrementals before prep archive preparation to avoid dirty git status
        infra.prepareToPublishIncrementals()
      }
    } else {
      withEnv(["ARCHIVE_NAME=${prepArchiveName}"]) {
        sh '''
        tar xzfv "${ARCHIVE_NAME}"
        rm "${ARCHIVE_NAME}"
        '''
        echo "INFO: ${prepArchiveName} retrieved and extracted, no need to run prep.sh"
      }
    }
  }

  stage('parse prep') {
    dir('target') {
      def plugins = []
      if (limitedPluginSetLabel) {
        // TODO: check why unstable seems to break pipeline graph view
        // unstable('WARNING: running on a limited set of plugins')
        echo('WARNING: running on a limited set of plugins')
        plugins = limitedPluginSet
      } else {
        plugins = readFile('plugins.txt').split('\n')
      }
      pluginsByRepository = parsePlugins(plugins)

      lines = readFile('lines.txt').split('\n')
      lines = [lines[0], lines[-1]] // Save resources by running PCT only on newest and oldest lines
    }
    def from = limitedPluginSetLabel ? 'a limited set of plugins' : 'plugins.txt'
    echo "INFO: ${pluginsByRepository.size()} repositories retrieved from ${from}"
    echo "INFO: ${lines.size()} lines retrieved from plugins.txt"
  }

  stage('stash prep lines') {
    lines.each { line ->
      if (line != 'weekly' && (weeklyTestMarkerFile || env.CHANGE_ID && weeklyTestLabel )) {
        echo "INFO: not stashing ${line} line as there is a 'weekly-test' label on PR or a marker file"
      } else {
        stash name: line, includes: "pct.sh,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-${line}.war"
      }
    }
  }

  stage('archive new prep') {
    if (prepFoundInBuildNumber == 0) {
      // Keeping all lines in the prep archive in case labels change on PR
      lines.each { line ->
        prepArchiveGlob += " target/megawar-${line}.war"
      }
      withEnv(["ARCHIVE_NAME=${prepArchiveName}", "ARCHIVE_GLOB=${prepArchiveGlob}",]) {
        sh 'tar czfv "${ARCHIVE_NAME}" ${ARCHIVE_GLOB}'
        archiveArtifacts artifacts: prepArchiveName, fingerprint: true
        echo "INFO: new ${prepArchiveName} archived"
      }
    } else {
      echo "INFO: no new prep to archive"
    }
  }

  stage('search report') {
    // TODO: include commit in reportName? Only in PR and search on master with simple name?
    reportprepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild("${reportName}.txt", env.JOB_NAME)
    // If not found in current build fallback to master
    if (reportprepFoundInBuildNumber == 0) {
      // TODO: use a direct copyArtifact with an appropriate selector? (lastSuccessful(), lastArchived(), etc.)
      reportprepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild("${reportName}.txt", 'Tools/bom/master')
    }
    sh "cat ${reportName}.txt || true"
  }

  stage('splits') {
    def allCombinations = getAllCombinations(pluginsByRepository, lines, (weeklyTestMarkerFile || weeklyTestLabel))
    echo "allCombinations.size(): ${allCombinations.size()}"

    if (reportprepFoundInBuildNumber > 0) {
      def content = readFile("${reportName}.txt")
      previousResults = parseReport(content)
      echo "previousResults: ${previousResults}"
      def buckets = splitReports(previousResults, MAX_SPLITS)
      batches = getBucketCombinations(buckets, allCombinations)
    } else {
      echo "INFO: no ${reportName}.txt found, no balanced split -> one branch per combination of repo/line"
      allCombinations.each { combination, plugins ->
        batches[combination] = [:]
        batches[combination][combination] = plugins
      }
    }
  }
}

if (BRANCH_NAME == 'master' || fullTestMarkerFile || weeklyTestMarkerFile || env.CHANGE_ID && (fullTestLabel || weeklyTestLabel )) {
  stage('parallel') {
    def branches = [failFast: false]

    batches.each { batch, combinations ->
      branches[batch] = {
        mavenNode() {
          def unstashLines = []
          lines.each { line ->
            combinations.each { combination, _ ->
              def parts = combination.split('_')
              def combinationLine = parts[1].replaceAll('-', '.')
              if (combinationLine == line && !unstashLines.contains(combinationLine)) {
                unstash combinationLine
                unstashLines.add(combinationLine)
              }
            }
          }
          combinations.each { combination, plugins ->
            def parts = combination.split('_')
            def repository = parts[0]
            def line = parts[1].replaceAll('-', '.')
            // Note: line is currrently never set to '2.555.x'
            // as we're keeping only the first ('weekly') and the last lines from lines.txt in 'prep' stage
            def jdk = line == 'weekly' || line == '2.555.x' ? 21 : 17
            echo "combination: ${combination} (plugins: ${plugins})"
            mavenEnv(jdk: jdk) {
              withEnv([
                "PLUGINS=${plugins}",
                "LINE=${line}",
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
                  results[combination] = resultFromJunitResults(junitResults, plugins)
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
        "${branch}:${result['elapsed']}:${result['failCount']}:${result['plugins']}"
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
