env.MAVEN_NTP = true
// Should be the same as in the primary Jenkinsfile
def stashGlob = 'pct.sh,incrementals.sh,consume-incrementals,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-REPLACEME_LINE.war'

properties([
  parameters([
    string(
        name: 'ARCHIVE_NAME',
        defaultValue: 'prep.tar.gz',
        description: 'Name of the archive to build. Expected format to build the archive from a specific commit: prep_[commit]_[CHANGE_FORK ?: jenkinsci].tar.gz (add "_consume-incrementals" before .tar.gz)',
        ),
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

def consumeIncrementals = false
def archiveName = params.ARCHIVE_NAME
def commit

mavenEnv(jdk: 21) {
  stage('init') {
    def scmVars = checkout(scm)
    sh 'ls *'
    sh('ls ' + env.MVN_LOCAL_REPO + '* || true')

    commit = scmVars.GIT_COMMIT
    // No commit by default in the archive name (allowing to retrieve it from any revision in the upstream build)
    // If there is a commit, there must be a CHANGE_FORK or 'jenkinsci' as third part
    def parts = archiveName.replace('.tar.gz', '').split('_')
    echo "DEBUG: archiveName: ${archiveName}, parts: ${parts}"
    if (parts.size() > 2) {
      commit = parts[1]
      changeFork = parts[2]
      def remote = "https://github.com/${changeFork}/bom.git"
      echo "INFO: setting remote change-fork to ${remote}"
      sh('git remote add change-fork ' + remote)
      sh 'git fetch --no-tags change-fork "+refs/heads/*:refs/remotes/origin/*"'
      sh 'git remote -v'
      sh('git checkout ' + commit)
      if (parts.size() > 3 && parts[3] == 'consume-incrementals') {
        consumeIncrementals = true
        echo 'INFO: setting consume-incrementals'
      }
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
    }
  }
  stage('archive') {
    sh 'ls *'
    sh('ls ' + env.MVN_LOCAL_REPO + '/io/jenkins/tools/bom/* || true')
    // Add a reference file
    writeFile file: "target/build-url-prep-only-commit-${commit}.txt", text: env.BUILD_URL
    // Find the last line from sample-plugin/pom.xml to avoid archiving all (heavy) megawars
    def lastLine = readFile('sample-plugin/pom.xml').readLines().findAll {
      it.contains('<bom>')
    }.last().replaceAll(/.*<bom>|<\/bom>.*/, '')
    // Replace stash glob separator by tar one then keep only the first (weekly) and last megawars
    def tarGlob = stashGlob.replace(',', ' ').replace('target/megawar-REPLACEME_LINE.war', "target/megawar-weekly.war target/megawar-${lastLine}.war")
    // Remove consume-incrementals from glob if it doesn't exist
    consumeIncrementalsMarkerFile = fileExists 'consume-incrementals'
    if (!consumeIncrementalsMarkerFile) tarGlob = tarGlob.replace(' consume-incrementals', '')
    // Copy bom pom in a temporary folder
    sh 'mkdir -p mvn-local-repo-bom'
    sh 'cp -a "${MVN_LOCAL_REPO}/io/jenkins/tools/bom/." mvn-local-repo-bom/'
    tarGlob += ' mvn-local-repo-bom'
    // Add plugins.txt, lines.txt & reference file
    tarGlob += ' target/*.txt'
    echo "INFO: tar glob=${tarGlob}"
    withEnv(["ARCHIVE_NAME=${archiveName}", "TAR_GLOB=${tarGlob}"]) {
      // List files not found
      sh 'find ${TAR_GLOB} -type f 1>/dev/null || true'
      // Archive only files that exist, excluding the folders from ls output
      sh 'tar -czvf ${ARCHIVE_NAME} $(find ${TAR_GLOB} -type f 2>/dev/null)'
    }
    // Archive the prep archive + ref file & plugins.txt & lines.txt themselves for future references
    archiveArtifacts artifacts: "${archiveName},target/*.txt", fingerprint: true
  }
  stage('update build desc') {
    // Update build description
    def duration = formatDuration((System.currentTimeMillis() - env.PROVISONING_START.toLong()) / 1000.0)
    def buildInfo = "<i>${archiveName}, duration: ${duration}</i>"
    def currentDesc = currentBuild.description
    currentBuild.description = currentDesc ? currentDesc + '<br>' + buildInfo : buildInfo
  }
}

def formatDuration(def seconds) {
  long totalSeconds = Math.round(seconds as Double)
  long hours = totalSeconds.intdiv(3600)
  long mins = (totalSeconds % 3600).intdiv(60)
  long secs = totalSeconds % 60
  if (hours> 0) return "${hours}h${mins.toString().padLeft(2, '0')}m${secs.toString().padLeft(2, '0')}s"
  if (mins> 0) return "${mins}m${secs.toString().padLeft(2, '0')}s"
  return "${secs}s"
}
