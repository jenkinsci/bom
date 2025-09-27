// Do not trigger build regularly on change requests as it costs a lot
String cronTrigger = ''
if(env.BRANCH_NAME == "master") {
  cronTrigger = '57 23 * * 4' // Thursday evening in Dallas, Texas, USA (almost midnight UTC)
}

properties([
  disableConcurrentBuilds(abortPrevious: true),
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
              "MAVEN_ARGS=${env.MAVEN_ARGS != null ? MAVEN_ARGS : ''} -B -ntp -Dmaven.repo.local=${WORKSPACE_TMP}/m2repo",
              "MVN_LOCAL_REPO=${WORKSPACE_TMP}/m2repo",
            ]) {
              // Load Maven Repo Cache if available
              sh '''
              mkdir -p "${MVN_LOCAL_REPO}"
              if test -f /cache/maven-bom-local-repo.tar.gz;
              then
                pushd "${MVN_LOCAL_REPO}"
                time cp /cache/maven-bom-local-repo.tar.gz ../
                time tar xzf ../maven-bom-local-repo.tar.gz ./
                rm ../maven-bom-local-repo.tar.gz
                popd
              fi
              '''

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

def pluginsByRepository
def lines
def fullTestMarkerFile
def weeklyTestMarkerFile

stage('prep') {
  mavenEnv(jdk: 21) {
    checkout scm
    withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
      withCredentials([
        usernamePassword(credentialsId: 'app-ci.jenkins.io', usernameVariable: 'GITHUB_APP', passwordVariable: 'GITHUB_OAUTH')
      ]) {
        sh '''
        mvn -v
        echo "Starting artifact caching proxy pre-heat"
        mvn -ntp dependency:go-offline
        echo "Finished artifact caching proxy pre-heat"
        bash prep.sh
        '''
      }
    }
    fullTestMarkerFile = fileExists 'full-test'
    weeklyTestMarkerFile = fileExists 'weekly-test'
    dir('target') {
      def plugins = readFile('plugins.txt').split('\n')
      pluginsByRepository = parsePlugins(plugins)

      lines = readFile('lines.txt').split('\n')
      lines = [lines[0], lines[-1]] // Save resources by running PCT only on newest and oldest lines
      withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
        lines.each { line ->
          def commitHashes = readFile "commit-hashes-${line}.txt"
          sh "launchable verify && launchable record build --name ${env.BUILD_TAG}-${line} --no-commit-collection " + commitHashes

          def sessionFile = "launchable-session-${line}.txt"
          def jdk = line == 'weekly' ? 21 : 17
          sh "launchable record session --build ${env.BUILD_TAG}-${line} --flavor platform=linux --flavor jdk=${jdk} >${sessionFile}"
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

if (BRANCH_NAME == 'master' || fullTestMarkerFile || weeklyTestMarkerFile || env.CHANGE_ID && (pullRequest.labels.contains('full-test') || pullRequest.labels.contains('weekly-test'))) {
  branches = [failFast: false]
  lines.each {line ->
    if (line != 'weekly' && (weeklyTestMarkerFile || env.CHANGE_ID && pullRequest.labels.contains('weekly-test'))) {
      return
    }
    pluginsByRepository.each { repository, plugins ->
      // TODO https://github.com/SonarSource/sonar-scanner-jenkins/pull/314
      if (repository == 'sonarqube-plugin') {
        return
      }
      branches["pct-$repository-$line"] = {
        def jdk = line == 'weekly' ? 21 : 17
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
          withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
            def sessionFile = "launchable-session-${line}.txt"
            unstash sessionFile
            def session = readFile(sessionFile).trim()
            sh "launchable verify && launchable record tests --session ${session} --group ${repository} maven './**/target/surefire-reports' './**/target/failsafe-reports'"
          }
        }
      }
    }
  }
  parallel branches
}

if (fullTestMarkerFile) {
  error 'Remember to `git rm full-test` before taking out of draft'
}

infra.maybePublishIncrementals()
