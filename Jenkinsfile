env.MAVEN_NTP = true
// Should be the same as in the primary Jenkinsfile
def stashGlob = 'pct.sh,incrementals.sh,consume-incrementals,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-REPLACEME_LINE.war'

properties([
  parameters([
    string(
        name: 'ARCHIVE_NAME',
        defaultValue: 'prep.tar.gz',
        description: 'Name of the archive to build. Expected format to build the archive from a specific commit: prep-<commit>.tar.gz (add "-consume-incrementals" after the commit if needed)',
        )
  ]),
  buildDiscarder(logRotator(numToKeepStr: '10'))
])

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

mavenEnv(jdk: 21) {
  def scmVars = checkout(scm)
  def gitCommit = scmVars.GIT_COMMIT
  def consumeIncrementals = false
  // No commit by default in the archive name (allowing to retrieve it from any revision in the upstream build)
  def archiveName = params.ARCHIVE_NAME
  def parts = archiveName.replace('.tar.gz', '').split('-')
  echo "DEBUG: archiveName: ${archiveName}, parts: ${parts}"
  if (parts.size() > 1) {
    gitCommit = parts[1]
    sh 'git checkout ' + gitCommit
    if (parts.size() > 2 && parts[2] == 'consume-incrementals') {
      consumeIncrementals = true
    }
  }
  stage(archiveName) {
    // Try to retrieve prep archive from a previous build on the same revision
    try {
      copyArtifacts(projectName: env.JOB_NAME, parameters: "ARCHIVE_NAME=${archiveName}", selector: lastWithArtifacts(), filter: archiveName, fingerprintArtifacts: true)
      archiveArtifacts artifacts: archiveName, fingerprint: true
    } catch(e) {
      // If no corresponding prep archive found (first build or new commit), run prep.sh
      withChecks(name: 'Tests', includeStage: true) {
        withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist', "CONSUME_INCREMENTALS=${consumeIncrementals}"]) {
          sh '''
          mvn -v
          bash prep.sh
          '''
        }
      }
      stage('archive') {
        sh 'ls *'
        // Add a reference file
        writeFile file: "target/build-url-prep-only-commit-${gitCommit}.txt", text: env.BUILD_URL
        // Archive files stashed for all lines after the "prep" stage + plugins.txt & lines.txt
        def tarGlob = stashGlob.replace(',', ' ').replace('REPLACEME_LINE', '*') + ' target/*.txt'
        // Don't try to archive consume-incrementals file if it doesn't exist
        if (!consumeIncrementalsMarkerFile) tarGlob = tarGlob.replace(' consume-incrementals', '')
        // Also include prep.sh test results
        tarGlob += '**/target/surefire-reports/TEST-*.xml **/target/failsafe-reports/TEST-*.xml'
        sh 'tar -czvf ' archiveName + ' ' + tarGlob
        // Archive the prep archive + ref file & plugins.txt & lines.txt themselves for future references
        archiveArtifacts artifacts: "${archiveName},target/*.txt", fingerprint: true
      }
    }

    // Update build description
    def duration = formatDuration((System.currentTimeMillis() - env.PROVISONING_START.toLong()) / 1000.0)
    def buildInfo = "<i>${archiveName}, duration: ${duration}</i>"
    def currentDesc = currentBuild.description
    currentBuild.description = currentDesc ? currentDesc + '<br>' + buildInfo : buildInfo
  }
}

def formatDuration(def seconds) {
  def parts = []
  long totalSeconds = Math.round(seconds as Double)
  long hours = totalSeconds.intdiv(3600)
  long mins = (totalSeconds % 3600).intdiv(60)
  long secs = totalSeconds % 60
  if (hours) {
    parts << "${hours}h"
  }
  if (mins) {
    parts << (hours) ? "${mins.toString().padLeft(2, '0')}m" : "${mins}m"
  }
  if (secs) {
    parts << (mins || hours) ? "${secs.toString().padLeft(2, '0')}s" : "${secs}s"
  }
  parts.join('')
}
