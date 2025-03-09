properties([
  disableConcurrentBuilds(abortPrevious: true),
  // buildDiscarder(logRotator(numToKeepStr: '7')),
  // pipelineTriggers([cron('54 20 * * 6')])
])

if (BRANCH_NAME == 'master' && currentBuild.buildCauses*._class == ['jenkins.branch.BranchEventCause']) {
  currentBuild.result = 'NOT_BUILT'
  error 'No longer running builds on response to master branch pushes. If you wish to cut a release, use “Re-run checks” from this failing check in https://github.com/jenkinsci/bom/commits/master'
}


def mavenEnv(Map params = [:], Closure body) {
  def attempt = 0
  def attempts = 6
  retry(count: attempts, conditions: [kubernetesAgent(handleNonKubernetes: true), nonresumable()]) {
    echo 'Attempt ' + ++attempt + ' of ' + attempts
    // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
    // node('maven-bom-cacher') {
    // timeout(120) {
    // withChecks(name: 'Tests', includeStage: true) {
    infra.withArtifactCachingProxy {
      withEnv([
        'JAVA_HOME=/opt/jdk-' + params['jdk'],
        "MAVEN_ARGS=${env.MAVEN_ARGS != null ? MAVEN_ARGS : ''} -B -ntp -Dmaven.repo.local=${WORKSPACE_TMP}/m2repo",
        "MVN_LOCAL_REPO=${WORKSPACE_TMP}/m2repo",
      ]) {
        body()
      }
    }
    // if (junit(testResults: '**/target/surefire-reports/TEST-*.xml,**/target/failsafe-reports/TEST-*.xml').failCount > 0) {
    //   // TODO JENKINS-27092 throw up UNSTABLE status in this case
    //   error 'Some test failures, not going to continue'
    // }
    // }
    // }
  }
  // }
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

node('maven-bom-cacher') {
  stage('prep') {
    mavenEnv(jdk: 21) {
      checkout scm
      withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
        withCredentials([
          usernamePassword(credentialsId: 'app-ci.jenkins.io', usernameVariable: 'GITHUB_APP', passwordVariable: 'GITHUB_OAUTH')
        ]) {
          // Load Maven Repo Cache if available
          sh '''
          mkdir -p "${MVN_LOCAL_REPO}"
          if test -f /cache-rw/maven-bom-local-repo.tar.gz;
          then
            time tar xzf /cache-rw/maven-bom-local-repo.tar.gz -C "${MVN_LOCAL_REPO}"
          fi
          '''

          sh '''
          mvn dependency:go-offline -Dmaven.repo.local=${WORKSPACE_TMP}/m2repo
          '''

          sh '''
          mvn -v
          bash prep.sh
          '''
        }
      }
      fullTestMarkerFile = fileExists 'full-test'
      weeklyTestMarkerFile = fileExists 'weekly-test'
      dir('target') {
        sh '''
        mv plugins.txt plugins.txt.orig

        head -n50 plugins.txt.orig > plugins.txt
        '''

        sh '''
        cat lines.txt
        cat plugins.txt
        '''

        def plugins = readFile('plugins.txt').split('\n')
        pluginsByRepository = parsePlugins(plugins)

        lines = readFile('lines.txt').split('\n')
        // withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
        //   lines.each { line ->
        //     def commitHashes = readFile "commit-hashes-${line}.txt"
        //     sh "launchable verify && launchable record build --name ${env.BUILD_TAG}-${line} --no-commit-collection " + commitHashes

        //     def sessionFile = "launchable-session-${line}.txt"
        //     def jdk = line == 'weekly' ? 21 : 17
        //     sh "launchable record session --build ${env.BUILD_TAG}-${line} --flavor platform=linux --flavor jdk=${jdk} >${sessionFile}"
        //     stash name: sessionFile, includes: sessionFile
        //   }
        // }
      }
      lines.each { line ->
        stash name: line, includes: "pct.sh,excludes.txt,target/pct.jar,target/megawar-${line}.war"
      }
      // infra.prepareToPublishIncrementals()
    }
  }

  // if (BRANCH_NAME == 'master' || fullTestMarkerFile || weeklyTestMarkerFile || env.CHANGE_ID && (pullRequest.labels.contains('full-test') || pullRequest.labels.contains('weekly-test'))) {
  // branches = [failFast: false]
  lines.each {line ->
    // if (line != 'weekly' && (weeklyTestMarkerFile || env.CHANGE_ID && pullRequest.labels.contains('weekly-test'))) {
    //   return
    // }
    pluginsByRepository.each { repository, plugins ->
      stage("pct-$repository-$line") {
        // branches["pct-$repository-$line"] = {
        def jdk = line == 'weekly' ? 21 : 17
        mavenEnv(jdk: jdk, nodePool: true) {
          unstash line
          withEnv([
            "PLUGINS=${plugins.join(',')}",
            "LINE=$line",
            'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=1'
          ]) {
            sh '''
                mvn -v
                du -sh "${MVN_LOCAL_REPO}"
                bash pct.sh
                du -sh "${MVN_LOCAL_REPO}"
                '''
          }
          // withCredentials([string(credentialsId: 'launchable-jenkins-bom', variable: 'LAUNCHABLE_TOKEN')]) {
          //   def sessionFile = "launchable-session-${line}.txt"
          //   unstash sessionFile
          //   def session = readFile(sessionFile).trim()
          //   sh "launchable verify && launchable record tests --session ${session} --group ${repository} maven './**/target/surefire-reports' './**/target/failsafe-reports'"
          // }
        }
        // }
      }
    }
  }

  sh '''
  cd "${MVN_LOCAL_REPO}"
  df -h .
  du -sh .
  time tar czf ../maven-bom-local-repo.tar.gz ./
  du -sh /cache-rw/*
  time cp ../maven-bom-local-repo.tar.gz /cache-rw/maven-bom-local-repo.tar.gz
  du -sh /cache-rw/*
  '''
}
// parallel branches
// }

// if (fullTestMarkerFile) {
//   error 'Remember to `git rm full-test` before taking out of draft'
// }

// infra.maybePublishIncrementals()
