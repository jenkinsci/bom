// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '57 11 * * 5'
}

def fullTestLabel = pullRequest.labels.contains('full-test')
def weeklyTestLabel = pullRequest.labels.contains('weekly-test')
def limitedPluginSetLabel = pullRequest.labels.contains('limited-plugin-set')

def testingCase = ''
if (testingCase == 'limited-weekly') {
  fullTestLabel = false
  weeklyTestLabel = true
  limitedPluginSetLabel = true
}
if (testingCase == 'limited-full') {
  fullTestLabel = true
  weeklyTestLabel = false
  limitedPluginSetLabel = true
}

env.MAVEN_NTP = true
def MAX_SPLITS = 20
def borkedReport = false // set this to true if the previous report is borked and causes failure
def reportName = '' // can be overriden
def reportResults = true
// TODO: get limited set from a marker file?
def limitedPluginSet = [
  'jenkinsci/aws-credentials-plugin	aws-credentials',
  'jenkinsci/aws-global-configuration-plugin	aws-global-configuration',
  'jenkinsci/azure-credentials-plugin	azure-credentials',
  'jenkinsci/azure-keyvault-plugin	azure-keyvault',
  'jenkinsci/azure-sdk-plugin	azure-sdk',
  'jenkinsci/azure-storage-plugin	windows-azure-storage',
  'jenkinsci/badge-plugin	badge',
  'jenkinsci/basic-branch-build-strategies-plugin	basic-branch-build-strategies',
  'jenkinsci/cron_column-plugin_weekly	cron_column',
  'jenkinsci/pipeline-maven-plugin	pipeline-maven,pipeline-maven-api,pipeline-maven-database',
]
def limitedMaxSplits = 3
def combinationSeparator = '~'

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
          "CURRENT_ATTEMPT=${attempt}",
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

// TODO: copyArtifactsFromAllPreviousBuilds and merge results?
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
    def limit = jobName.endsWith('master') ? buildNumber - 50 : 0
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

// TODO: check what happens if MAX_SPLITS > repositories
@NonCPS
def splitReports(List items, int maxSplits) {
  // initialize buckets
  def buckets = (0..<maxSplits).collect {
    [total: 0.0, items: []]
  }

  // sort by elapsed time, largest first
  def sorted = items.sort { -it.elapsed }

  sorted.each { item ->
    // pick the bucket with the smallest total elapsed time
    def target = buckets.min { it.total }

    target.items << item
    target.total += item.elapsed
  }

  // Trim empty buckets
  buckets = buckets.findAll { it.items.size() > 0 }

  return buckets
}

// TODO: replace by args[:]
@NonCPS
def getAllCombinations(pluginsByRepository, lines, weeklyOnly, combinationSeparator) {
  def combinations = [:]
  lines.each {line ->
    if (line != 'weekly' && weeklyOnly) {
      return
    }
    def normalizedLine = line.replaceAll('\\.', '-')
    // TODO: alert if repository or plugins isn't valid (a-Z_-)
    pluginsByRepository.each { repository, plugins ->
      combinations["${repository}${combinationSeparator}${normalizedLine}"] = plugins.join(',')
    }
  }
  combinations
}

// TODO: if there is a time for a repo-line but not repo-anotherLine,
// use that first time as default estimation and resplit from there
@NonCPS
def getBatches(buckets, allCombinations, bucketType) {
  def batches = [:]
  def seen = new HashSet()
  buckets.eachWithIndex { bucket, idx ->
    def counter = idx + 1
    def splitIndex = "${bucketType}-${counter} (${bucket.items.size()})"
    batches[splitIndex] = [:]
    bucket.items.each {
      def combination = it.name
      if (!seen.contains(combination)) {
        seen.add(combination)
        batches[splitIndex][combination] = allCombinations[combination]
      }
    }
  }
  echo "seen.size(): ${seen.size()}"
  echo "batches.size(): ${batches.size()}"

  batches
}

@NonCPS
def getResult(junitResults, elapsed, plugins) {
  def result = [:]
  result['elapsed'] = (elapsed / 1000.0)
  result['plugins'] = plugins
  result['pluginCount'] = plugins.count(',')
  if (junitResults) {
    result['failCount'] = junitResults.failCount
    result['skipCount'] = junitResults.skipCount
    result['passCount'] = junitResults.passCount
    result['totalCount'] = junitResults.totalCount
    result['duration'] = junitResults.duration
  } else {
    result['failCount'] = 0
    result['skipCount'] = 0
    result['passCount'] = 0
    result['totalCount'] = 0
    result['duration'] = 0
  }
  result
}

// TODO: complete results with previous (successful) reports
@NonCPS
def getReportsFromResults(results, combinationSeparator) {
  Double totalElapsed = 0
  Double totalDuration = 0
  int totalFailCount = 0
  int totalSkipCount = 0
  int totalPassCount = 0
  int totalTotalCount = 0

  def xmlReportContent
  def reportLines = ''
  def sortedResult = results.sort { it }
  sortedResult.each { combination, result ->
    // results.each { combination, result ->
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
    def normalizedCombination = combination.replaceAll('-', '_').replaceAll(combinationSeparator, '_')
    reportLines += '<testcase name="' + combination + '" classname="pct-duration.' + normalizedCombination + '" time="' + elapsed + '" failures="' + failCount + '"/>\n'
    // TODO: try after only setting name, no classname
  }
  if (reportLines) {
    xmlReportContent = """<?xml version="1.0" encoding="UTF-8"?>
      <testsuite name="org.jenkins.ci.bom" time="${totalElapsed}" tests="${totalTotalCount}" skipped="${totalSkipCount}" failures="${totalFailCount}">
      ${reportLines}
      </testsuite>
    """
  }

  def reportLinesJson = results.collect { combination, result ->
    """{"name":"${combination}","elapsed":${result['elapsed']},"duration":${result['duration']},"failCount":${result['failCount']},"skipCount":${result['skipCount']},"passCount":${result['passCount']},"totalCount":${result['totalCount']},"attempt":${result['attempt']}}"""
  }.join(',')
  def jsonReportContent = """{"jobs": [${reportLinesJson}]}"""

  def txtReportContent = results.collect { combination, result ->
    "${combination}:${result['elapsed']}:${result['failCount']}:${result['plugins']}"
  }.join('\n')

  [
    xmlReportContent: xmlReportContent,
    jsonReportContent: jsonReportContent,
    txtReportContent: txtReportContent,
  ]
}

@NonCPS
def getBuildDescription(args = [:]) {
  // TODO: merge user args & default values ala pipeline lib
  def originalDesc = args['description']
  def desc = ''
  def labels = []
  def markers = []
  def elts = []
  if (args['fullTestLabel']) {
    labels.add('full-test')
  }
  if (args['weeklyTestLabel']) {
    labels.add('weekly-test')
  }
  if (args['limitedPluginSetLabel']) {
    labels.add('limited-plugin-set')
  }
  if (args['fullTestMarkerFile']) {
    markers.add('full-test')
  }
  if (args['weeklyTestMarkerFile']) {
    markers.add('weekly-test')
  }
  if (args['testingCase']) {
    elts.add("<b>test</b>:${args['testingCase']}")
  }
  if (labels.size() > 0) {
    elts.add("<b>labels</b>:${labels.join(',')}")
  }
  if (markers.size() > 0) {
    elts.add("<b>markers</b>:${markers.join(',')}")
  }
  if (elts.size() > 0) {
    desc = '<i><small>' + elts.join('<br>') + '</small></i>'
  }
  if (originalDesc) {
    desc = (originalDesc + '<br>' + desc).trim()
  }
  return desc
}

// def getBuildDescription(Map args = [:]) {
//   def labels = [
//     (args.fullTestLabel): 'full-test',
//     (args.weeklyTestLabel): 'weekly-test',
//     (args.limitedPluginSetLabel): 'limited-plugin-set'
//   ].findAll { it.key }.values()

//   def markers = [
//     (args.fullTestMarkerFile): 'full-test',
//     (args.weeklyTestMarkerFile): 'weekly-test'
//   ].findAll { it.key }.values()

//   def parts = []

//   if (labels)  parts << "[labels:${labels.join(',')}]"
//   if (markers) parts << "[markers:${markers.join(',')}]"
//   if (args.testingCase) parts << "[test ${args.testingCase}]"

//   return ([args.description, parts.join(' ')].findAll { it } ).join(' ').trim()
// }

def pluginsByRepository
def lines
def newestAndOldestLines
def allCombinations
def reports = [:]
def fakeReports
def fullTestMarkerFile
def weeklyTestMarkerFile
def results = [:]
def previousResults = [:]
def batches = [:]

mavenNode(jdk: 21) {
  def scmVars = checkout scm

  fullTestMarkerFile = fileExists 'full-test'
  weeklyTestMarkerFile = fileExists 'weekly-test'

  // Add current labels, marker files and testing case to the build description once
  if (env.CURRENT_ATTEMPT == 1) {
    def desc = getBuildDescription([
      description: currentBuild.description,
      fullTestLabel: fullTestLabel,
      weeklyTestLabel: weeklyTestLabel,
      limitedPluginSetLabel: limitedPluginSetLabel,
      fullTestMarkerFile: fullTestMarkerFile,
      weeklyTestMarkerFile: weeklyTestMarkerFile,
      testingCase: testingCase,
    ])
    currentBuild.description = desc
  }

  // Report name depending on labels and marker files, by order of prevalence
  // We chould add more info in the reportName, like which lines/one per line
  // or reportName if not empty
  // TODO: also report as <...>-PR_N_buildN
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

  stage('retrieve prep archive') {
    prepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild(prepArchiveName, env.JOB_NAME)
    if (prepFoundInBuildNumber == 0) {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
        error("${prepArchiveName} not found")
      }
      return
    }
  }

  stage('prep') {
    if (prepFoundInBuildNumber == 0) {
      withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist', "ARCHIVE_NAME=${prepArchiveName}",]) {
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
        MAX_SPLITS = limitedMaxSplits
      } else {
        plugins = readFile('plugins.txt').split('\n')
      }
      pluginsByRepository = parsePlugins(plugins)

      def from = limitedPluginSetLabel ? 'a limited set of plugins' : 'plugins.txt'
      echo "INFO: ${pluginsByRepository.size()} repositories retrieved from ${from}"
      echo "INFO: retrieved repositories and their plugins:\n${plugins.join('\n')}"

      def allLines = readFile('lines.txt').split('\n')
      newestAndOldestLines = [allLines[0], allLines[-1]] // Save resources by running PCT only on newest and oldest lines
      echo "INFO: ${allLines.size()} lines retrieved from lines.txt: ${allLines.join(' ')} "

      // For archival, keep track of newest and oldest lines as PR labels or marker files may change accross builds
      // For stashes, we only care about the lines of the current build
      lines = newestAndOldestLines
      if (weeklyTestMarkerFile || weeklyTestLabel ) {
        echo "INFO: keeping only 'weekly' line as there is a 'weekly-test' label or marker file"
        lines = ['weekly']
      } else {
        echo "INFO: keeping only newest and oldest lines to save resources: ${lines.join(' ')} "
      }

      // Generating all combinations of repository x lines
      allCombinations = getAllCombinations(pluginsByRepository, lines, (weeklyTestMarkerFile || weeklyTestLabel), combinationSeparator)
      def allCombinationNames = allCombinations.collect { combination, _ -> combination } as Set
      echo "INFO: ${allCombinations.size()} resulting combinations:\n${allCombinationNames.join('\n')}"
    }
  }

  stage('archive new prep') {
    if (prepFoundInBuildNumber == 0) {
      // Newest and oldest lines only in the prep archive, in case labels change on PR accross builds
      newestAndOldestLines.each { line ->
        prepArchiveGlob += " target/megawar-${line}.war"
      }
      withEnv(["ARCHIVE_NAME=${prepArchiveName}", "ARCHIVE_GLOB=${prepArchiveGlob}",]) {
        sh 'tar czfv "${ARCHIVE_NAME}" ${ARCHIVE_GLOB}'
        archiveArtifacts artifacts: prepArchiveName, fingerprint: true
        echo "INFO: new ${prepArchiveName} archived"
      }
    } else {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
        error("INFO: no new prep to archive")
      }
      return
    }
  }

  stage('retrieve reports') {
    // TODO: include commit in reportName? Only in PR and search on master with simple name?
    reportprepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild("${reportName}.txt", env.JOB_NAME)

    // TODO: always retrieve from master (unless reports contain all combinations?)
    // so we can merge all
    // TODO: save/retrieve a more generic report name on master for easier retrieval?
    // NOTE: we can retrieve elapsed time from everywhere.
    // If we want previous failure counts, it will have to be restricted to the commit (save one generic, one "themed" [weekly/full/limited/custom], one including commit then retrieve all)

    // If not found in current build fallback to master
    if (reportprepFoundInBuildNumber == 0) {
      // TODO: use a direct copyArtifact with an appropriate selector? (lastSuccessful(), lastArchived(), etc.)
      reportprepFoundInBuildNumber = copyArtifactsFromAnyPreviousBuild("${reportName}.txt", 'Tools/bom/master')
    }
    if (reportprepFoundInBuildNumber > 0) {
      echo "INFO: ${reportName}.txt found, parsing its content"
      def content = readFile("${reportName}.txt")
      reports = content.readLines().collect { line ->
        def parts = line.trim().split(':')
        [
          name: parts[0],
          elapsed: parts[1].toDouble(),
          failures: parts[2].toInteger(),
          plugins: parts[3],
        ]
      }
    }
    echo "INFO: ${reports.size()} reports"
  }

  stage('generate batches') {
    if (reports.size() == 0 || borkedReport) {
      echo "INFO: ${reportName}.txt not found, empty or borked, faking reports for all combinations"
      fakeReports = allCombinations.collect { combination, plugins ->
        [
          name: combination,
          elapsed: 0.0001,
          failures: 0,
          count: 0, // 0 failure 0 count == fake
          plugins: plugins
        ]
      }
      def fakeBuckets = splitReports(fakeReports, MAX_SPLITS)
      batches += getBatches(fakeBuckets, allCombinations, 'fake')
    } else {
      // Keep only current combinations
      def actualReports = reports.findAll {
        allCombinations.containsKey(it.name)
      }

      // Track what we already have
      def seen = actualReports.collect { it.name } as Set
      def missingReports = fakeReports.findAll { !seen.contains(it.key) }

      // TODO: search missing repo in reports repos, and deduce elapsed from there (keeping totalCound = 0 to indicate it's not a real result?)

      if (actualReports.size() > 0) {
        def reportBuckets = splitReports(actualReports, MAX_SPLITS)
        batches += getBatches(reportBuckets, allCombinations, 'report')
      }

      if (missingReports.size() > 0) {
        def missingBuckets = splitReports(missingReports, MAX_SPLITS)
        batches += getBatches(missingBuckets, allCombinations, 'missing')
      }
    }

    // debug
    echo "INFO: ${batches.size()} batches"
    batches.each { batch, combinations ->
      if (combinations.size() > 0) {
        // echo "batch: ${batch}"
        def batchCombinationNames = combinations.collect { combination, plugins -> combination } as Set
        echo "INFO: '${batch}' batch, ${batchCombinationNames.size()} combinations:\n${batchCombinationNames.join('\n')}"
      }
    }
  }

  stage('stash prep lines') {
    if (batches.size() > 0) {
      lines.each { line ->
        stash name: line, includes: "pct.sh,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-${line}.war"
      }
    } else {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
        error('No batch, no need to stash any line')
      }
      return
    }
  }
}

stage('run pct') {
  def branches = [failFast: false]

  if (BRANCH_NAME != 'master' && !(fullTestMarkerFile || weeklyTestMarkerFile || fullTestLabel || weeklyTestLabel )) {
    catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
      error('Not running on master or no weekly-test / full-test labels or markers')
    }
    return
  }

  batches.each { batch, combinations ->
    if (combinations.size() == 0) {
      catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
        error('No batch, nothing to run')
      }
      return
    }
    branches[batch] = {
      mavenNode() {
        // Unstash all lines used in this batch
        def unstashLines = combinations
            .keySet()
            .collect { it.split(combinationSeparator)[1].replaceAll('-', '.') }
            .unique()
        unstashLines.each { unstash it }

        def combinationCount = 1
        def totalCombination = combinations.size()
        def batchCombinationNames = combinations.collect { combination, plugins -> combination } as Set
        echo "INFO: combinations in '${batch}' batch:\n${batchCombinationNames.join('\n')}"
        combinations.each { combination, plugins ->
          def parts = combination.split(combinationSeparator)
          def repository = parts[0]
          def line = parts[1].replaceAll('-', '.')
          // Note: line is currrently never set to '2.555.x'
          // as we're keeping only the first ('weekly') and the last lines from lines.txt in 'prep' stage
          def jdk = line == 'weekly' || line == '2.555.x' ? 21 : 17
          echo "INFO: combination ${combinationCount}/${totalCombination}: ${combination} (plugins: ${plugins})"

          def combinationAlreadySucceeded = false
          // Check if combination already in results, in case of aborted build due to a reclaimed spot instance for ex
          if (results.containsKey(combination)) {
            def previousFailCount = results[combination]['failCount']
            def previousElapsed = results[combination]['elapsed']
            if (previousFailCount == 0) {
              combinationAlreadySucceeded = true
              echo "${combination} has already succeeded (elapsed: ${previousElapsed})"
              try {
                echo "env.CURRENT_ATTEMPT: ${env.CURRENT_ATTEMPT}"
              } catch(e) {}
            } else {
              echo "${combination} had previously ${previousFailCount} failure(s) (elapsed: ${previousElapsed})"
            }
          }

          if (combinationAlreadySucceeded) {
            echo "INFO: skipping ${combination}, already succeeded"
          } else {
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
                  def junitResults
                  try {
                    junitResults = junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml')
                  } catch(e) {
                    echo "error junitResult: ${e}"
                  }
                  results[combination] = getResult(junitResults, elapsed, plugins)
                  try {
                    // TODO: review, KO (always = 6)
                    results[combination]['attempt'] = env.CURRENT_ATTEMPT
                  } catch(e) {
                    echo "error result attemtp: ${e}"
                  }
                  echo "results[${combination}]: ${results[combination]}"
                }
              }
            }
          }
          combinationCount = combinationCount + 1
        }
      }
    }
  }
  parallel branches
}

// TODO: consolidate with previous/master reports
// TODO: add 'src' of report? (results, previous reports ['pr-N', 'master-N'], deduced) to know which of these reports are retrieved from elsewhere than actual tests elapsed time?
stage('report results') {
  if (results.size() == 0) {
    catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
      error('No result to report')
    }
    return
  }
  if (!reportResults) {
    catchError(buildResult: 'SUCCESS', stageResult: 'NOT_BUILT') {
      error('WARNING: reportResults set to false, skipping')
    }
    return
  } else {
    node('maven-bom') {
      def contents = getReportsFromResults(results, combinationSeparator)
      if (contents['xmlReportContent']) {
        writeFile file: "${reportName}.xml", text: contents['xmlReportContent']
        junit allowEmptyResults: true, testResults: "${reportName}.xml"
      }
      writeFile file: "${reportName}.json", text: contents['jsonReportContent']
      writeFile file: "${reportName}.txt", text: contents['txtReportContent']

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
