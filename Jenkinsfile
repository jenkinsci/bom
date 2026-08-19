env.MAVEN_NTP = true

properties([
  parameters([
    string(
        name: 'COMMIT',
        defaultValue: '',
        description: 'Git commit to build. If empty, use the current SCM revision',
        )
  ]),
  parameters([booleanParam(
        name: 'CONSUME_INCREMENTALS',
        defaultValue: false,
        )]),
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

def stashGlob = 'pct.sh,incrementals.sh,consume-incrementals,excludes.txt,bom-*/excludes.txt,target/pct.jar,target/megawar-REPLACEME_LINE.war'

mavenEnv(jdk: 21) {
  def consumeIncrementals = params.CONSUME_INCREMENTALS ?: false
  // No commit by default in the archive name (allowing to retrieve it from any revision in the upstream build)
  def prepArchive = 'prep.tar.gz'
  def scmVars = checkout(scm)
  def gitCommit = params.COMMIT ?: scmVars.GIT_COMMIT
  if (params.COMMIT) {
    sh "git checkout ${params.COMMIT}"
    prepArchive = "prep-${gitCommit}.tar.gz"
  }
  stage(prepArchive) {
    // Try to retrieve prep archive from a previous build on the same revision
    try {
      copyArtifacts(projectName: env.JOB_NAME, selector: lastWithArtifacts(), filter: prepArchive, fingerprintArtifacts: true)
      archiveArtifacts artifacts: prepArchive, fingerprint: true
    } catch(e) {
      try {
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
      // Try..finally to capture potentially failed test results in the archive
      finally {
        stage('archive') {
          sh 'ls *'
          // Add a reference file
          writeFile file: "target/build-url-prep-only-commit-${gitCommit}.txt", text: env.BUILD_URL
          // Archive files stashed for all lines after the "prep" stage + plugins.txt & lines.txt
          def tarGlob = stashGlob.replace(',', ' ').replace('REPLACEME_LINE', '*') + ' target/*.txt'
          // Also include prep.sh test results
          tarGlob += '**/target/surefire-reports/TEST-*.xml **/target/failsafe-reports/TEST-*.xml'
          sh 'tar -czvf ' prepArchive + ' ' + tarGlob
          // Archive the prep archive + ref file & plugins.txt & lines.txt themselves for future references
          archiveArtifacts artifacts: "${prepArchive},target/*.txt", fingerprint: true
        }
      }
    }
  }
}
