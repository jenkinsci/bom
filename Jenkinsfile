properties([disableConcurrentBuilds(abortPrevious: true), buildDiscarder(logRotator(numToKeepStr: '7'))])

if (BRANCH_NAME == 'master' && currentBuild.buildCauses*._class == ['jenkins.branch.BranchEventCause']) {
  error 'No longer running builds on response to master branch pushes. If you wish to cut a release, use “Re-run checks” from this failing check in https://github.com/jenkinsci/bom/commits/master'
}

def mavenEnv(Map params = [:], Closure body) {
  def attempt = 0
  def attempts = 3
  retry(count: attempts, conditions: [kubernetesAgent(handleNonKubernetes: true), nonresumable()]) {
    echo 'Attempt ' + ++attempt + ' of ' + attempts
    // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
    node('maven-bom') {
      timeout(120) {
        withEnv(["JAVA_HOME=/opt/jdk-$params.jdk"]) {
          infra.withArtifactCachingProxy {
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
def createSubset(plugins, subsetGroups) {
  def result = [:]
  result << plugins
  result.keySet().removeAll(subsetGroups)
  result
}

def lines
def fullTest = env.CHANGE_ID && pullRequest.labels.contains('full-test')
def isSubset = env.CHANGE_ID && !pullRequest.labels.contains('skip-launchable-subset')
def subsets = [:]

stage('prep') {
  mavenEnv(jdk: 11) {
    checkout scm
    withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
      withCredentials([
        usernamePassword(credentialsId: 'app-ci.jenkins.io', usernameVariable: 'GITHUB_APP', passwordVariable: 'GITHUB_OAUTH')
      ]) {
        sh '''
        mvn -v
        bash prep.sh
        '''
      }
    }
    dir('target') {
      def plugins = readFile('plugins.txt').split('\n')
      def pluginsByRepository = parsePlugins(plugins)

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
          launchable("record session --build ${env.BUILD_TAG}-${line} --flavor platform=linux --flavor jdk=${jdk} ${isSubset ? '' : '--observation '}--link \"View session in CI\"=${env.BUILD_URL} >${sessionFile}")
          def session = readFile(sessionFile).trim()
          def subsetFile = "launchable-subset-${line}.txt"
          launchable("subset --session ${session} --split --target 20% --get-tests-from-previous-sessions --output-exclusion-rules maven >${subsetFile}")
          def subset = readFile(subsetFile).trim()
          launchable("inspect subset --subset-id ${subset}")
          launchable("split-subset --subset-id ${subset} --split-by-groups --output-exclusion-rules maven")
          def subsetGroups = [] as Set
          if (fileExists('subset-groups.txt')) {
            subsetGroups << readFile('subset-groups.txt').split('\n').toSet()
            sh 'rm subset-groups.txt'
          }
          subsets[line] = createSubset(pluginsByRepository, subsetGroups)
          sh "ls ../excludes.txt subset-*.txt | xargs -I{} bash -c 'cat {} >>excludes-${line}.txt && echo >>excludes-${line}.txt'"
          sh "cat excludes-${line}.txt | grep -v ^\$ | grep -v ^# | grep -v InjectedTest | sort -u >excludes-${line}.txt.new && mv excludes-${line}.txt.new excludes-${line}.txt"
          sh "cat excludes-${line}.txt"
        }
      }
    }
    lines.each { line ->
      stash name: line, includes: "pct.sh,target/excludes-${line}.txt,launchable-session-${line}.txt,target/pct.jar,target/megawar-${line}.war"
    }
    infra.prepareToPublishIncrementals()
  }
}

branches = [failFast: !fullTest]
lines.each {line ->
  subsets[line].each { repository, plugins ->
    branches["pct-$repository-$line"] = {
      def jdk = line == 'weekly' ? 17 : 11
      mavenEnv(jdk: jdk) {
        unstash line
        withEnv([
          "PLUGINS=${plugins.join(',')}",
          "LINE=$line",
          'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=1'
        ]) {
          sh '''
          mvn -v
          bash pct.sh
          '''
        }
        launchable.install()
        withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
          launchable('verify')
          def session = readFile("launchable-session-${line}.txt").trim()
          launchable("record tests --session ${session} --group ${repository} maven './**/target/surefire-reports' './**/target/failsafe-reports'")
        }
      }
    }
  }
}
parallel branches

infra.maybePublishIncrementals()
