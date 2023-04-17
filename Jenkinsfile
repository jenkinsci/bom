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
    podTemplate(
        cloud: 'cik8s-bom',
        yaml: '''---
apiVersion: "v1"
kind: "Pod"
spec:
  containers:
    - name: jnlp
      image: jenkinsciinfra/jenkins-agent-ubuntu-22.04@sha256:35420f09777717099416fb80f334f5c5d34d09ac29743c12be21dbb0e1628f1f
      imagePullPolicy: "IfNotPresent"
      command:
        - "/usr/local/bin/jenkins-agent"
      env:
        - name: "PATH"
          value: "/opt/jdk-11/bin:/home/jenkins/.asdf/shims:/home/jenkins/.asdf/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
        - name: "ARTIFACT_CACHING_PROXY_PROVIDER"
          value: "aws"
        - name: "JENKINS_AGENT_WORKDIR"
          value: "/home/jenkins/agent"
        - name: "JENKINS_JAVA_OPTS"
          value: "-XX:+PrintCommandLineFlags"
        - name: "JENKINS_JAVA_BIN"
          value: "/opt/jdk-11/bin/java"
      resources:
        limits:
          memory: "8Gi"
          cpu: "4"
        requests:
          memory: "8Gi"
          cpu: "4"
      securityContext:
        privileged: false
      tty: false
      volumeMounts:
        - mountPath: "/home/jenkins/.m2/repository"
          name: "volume-1"
          readOnly: false
        - mountPath: "/tmp"
          name: "volume-0"
          readOnly: false
  volumes:
  - emptyDir:
      medium: "Memory"
    name: "volume-0"
  - emptyDir:
      medium: ""
    name: "volume-1"
  nodeSelector:
    ci.jenkins.io/agents-density: 23
  tolerations:
    - key: "ci.jenkins.io/bom"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
'''
        ) {
          node(POD_LABEL) {
            timeout(120) {
              withEnv(["JAVA_HOME=/opt/jdk-$params.jdk"]) {
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
      if (env.CHANGE_ID && !fullTest) {
        // run PCT only on newest and oldest lines, to save resources (but check all lines on deliberate master builds)
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
    lines.each { line ->
      stash name: line, includes: "pct.sh,excludes.txt,target/pct.jar,target/megawar-${line}.war"
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
        unstash line
        withEnv([
          "PLUGINS=$plugins",
          "LINE=$line",
          'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=1'
        ]) {
          sh 'bash pct.sh'
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
