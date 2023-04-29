def props = [disableConcurrentBuilds(abortPrevious: true), buildDiscarder(logRotator(numToKeepStr: '7'))]

if (env.BRANCH_NAME == 'release') {
  props.add(pipelineTriggers([cron('30 10 * * 1')]))
}

properties props

if (env.BRANCH_NAME == 'release' && currentBuild.buildCauses*._class == ['jenkins.branch.BranchEventCause']) {
  error 'No longer running builds on response to release branch pushes. If you wish to cut an out-of-order release, use “Re-run checks” from this failing check in https://github.com/jenkinsci/bom/commits/release'
}

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
def fullTest = env.CHANGE_ID && pullRequest.labels.contains('full-test')
def isSubset = env.BRANCH_NAME == 'master' || (env.CHANGE_ID && env.CHANGE_TARGET == 'master' && !pullRequest.labels.contains('skip-subset'))

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
      def plugins = readFile('plugins.txt').split('\n')
      pluginsByRepository = parsePlugins(plugins)

      lines = readFile('lines.txt').split('\n')
      if (env.CHANGE_ID && !fullTest) {
        // run PCT only on newest and oldest lines, to save resources (but check all lines on deliberate master builds)
        lines = [lines[0], lines[-1]]
      }
      launchable.install()
      withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
        lines.each { line ->
          def commitHashes = readFile "commit-hashes-${line}.txt"
          launchable("record build --name ${env.BUILD_TAG}-${line} --no-commit-collection " + commitHashes + " --link \"View build in CI\"=${env.BUILD_URL}")

          def jdk = line == 'weekly' ? 17 : 11
          def sessionFile = "launchable-session-${line}.txt"
          launchable("record session --build ${env.BUILD_TAG}-${line} --flavor platform=linux --flavor jdk=${jdk} --observation --link \"View session in CI\"=${env.BUILD_URL} >${sessionFile}")
          stash name: sessionFile, includes: sessionFile
        }
      }
    }
    lines.each { line ->
      stash name: line, includes: "pct.sh,excludes.txt,target/pct.jar,target/megawar-${line}.war"
    }
    infra.prepareToPublishIncrementals()
  }
}

if (!isSubset) {
  branches = [failFast: !fullTest]
  lines.each {line ->
    pluginsByRepository.each { repository, plugins ->
      branches["pct-$repository-$line"] = {
        def jdk = line == 'weekly' ? 17 : 11
        mavenEnv(jdk: jdk) {
          unstash line
          withEnv([
            "PLUGINS=${plugins.join(',')}",
            "LINE=$line",
            'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=1'
          ]) {
            sh 'bash pct.sh'
          }
          launchable.install()
          withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
            launchable('verify')
            def sessionFile = "launchable-session-${line}.txt"
            unstash sessionFile
            def session = readFile(sessionFile).trim()
            launchable("record tests --session ${session} --group ${repository} maven './**/target/surefire-reports' './**/target/failsafe-reports'")
          }
        }
      }
    }
  }
  parallel branches
}

infra.maybePublishIncrementals()
