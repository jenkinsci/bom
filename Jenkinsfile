env.MAVEN_NTP = true

properties([disableConcurrentBuilds(abortPrevious: true), buildDiscarder(logRotator(numToKeepStr: '7')),])

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
          if (junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml').failCount > 0) {
            // TODO JENKINS-27092 throw up UNSTABLE status in this case
            error 'Some test failures, not going to continue'
          }
        }
      }
    }
  }
}

stage('prep') {
  mavenEnv(jdk: 21) {
    def scmVars = checkout scm
    withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist', 'CURRENT_COMMIT_ID=' + scmVars.GIT_COMMIT]) {
      sh '''
      mvn -v
      bash prep.sh
      # save current commit for future references
      touch "target/commit-${CURRENT_COMMIT_ID}"
      '''
      // archive tar of all files produced by prep.sh used after the "prep" stage of the main bom job
      sh 'tar -czvf prep.tar.gz pct.sh excludes.txt bom-*/excludes.txt target **/target/surefire-reports/TEST-*.xml'
      // also archive plugins.txt & lines.txt for future references
      archiveArtifacts 'prep.tar.gz,target/plugins.txt,target/lines.txt'
    }
  }
}
