properties([disableConcurrentBuilds(abortPrevious: true), buildDiscarder(logRotator(numToKeepStr: '7'))])

def mavenEnv(Map params = [:], Closure body) {
  def attempt = 0
  def attempts = 3
  retry(count: attempts, conditions: [kubernetesAgent(handleNonKubernetes: true), nonresumable()]) {
    echo 'Attempt ' + ++attempt + ' of ' + attempts
    // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
    node("maven-$params.jdk") {
      timeout(120) {
        sh 'mvn -version'
        // Exclude DigitalOcean artifact caching proxy provider, currently unreliable on BOM builds
        // TODO: remove when https://github.com/jenkins-infra/helpdesk/issues/3481 is fixed
        infra.withArtifactCachingProxy(env.ARTIFACT_CACHING_PROXY_PROVIDER != 'do') {
          withEnv([
            "MAVEN_ARGS=${env.MAVEN_ARGS != null ? MAVEN_ARGS : ''} -B -ntp -Dmaven.repo.local=${WORKSPACE_TMP}/m2repo"
          ]) {
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

def pluginsByRepository
def lines
def fullTest = env.CHANGE_ID && pullRequest.labels.contains('full-test')

stage('prep') {
  mavenEnv(jdk: 11) {
    checkout scm
    withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
      withCredentials([
        usernamePassword(credentialsId: 'app-ci.jenkins.io', usernameVariable: 'GITHUB_APP', passwordVariable: 'GITHUB_OAUTH')
      ]) {
        sh 'bash prep.sh'
      }
    }
    dir('target') {
      pluginsByRepository = readFile('plugins.txt').split('\n')
      lines = readFile('lines.txt').split('\n')
      if (!fullTest) {
        // run PCT only on newest and oldest lines, to save resources
        lines = [lines[0], lines[-1]]
      }
      launchable.install()
      withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
        lines.each { line ->
          def commitHashes = readFile "commit-hashes-${line}.txt"
          launchable("record build --name \"${BUILD_TAG}-${line}\" --no-commit-collection " + commitHashes)
          launchable("record session --build \"${BUILD_TAG}-${line}\" --observation >launchable-session-${line}.txt")
          stash name: "launchable-session-${line}.txt", includes: "launchable-session-${line}.txt"
        }
      }
    }
    infra.prepareToPublishIncrementals()
  }
}

branches = [failFast: !fullTest]
lines.each {line ->
  pluginsByRepository.each { plugins ->
    branches["pct-$plugins-$line"] = {
      def jdk = line == 'weekly' ? 17 : 11
      mavenEnv(jdk: jdk) {
        deleteDir()
        checkout scm
        withEnv([
          "PLUGINS=$plugins",
          "LINE=$line",
          'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=1'
        ]) {
          sh 'bash prep-megawar.sh && bash prep-pct.sh && bash pct.sh'
        }
        launchable.install()
        withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
          launchable('verify')
          unstash "launchable-session-${line}.txt"
          def launchableSession = readFile("launchable-session-${line}.txt").trim()
          launchable("record tests --session ${launchableSession} maven './**/target/surefire-reports' './**/target/failsafe-reports'")
        }
      }
    }
  }
}
parallel branches

infra.maybePublishIncrementals()
