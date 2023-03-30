properties([disableConcurrentBuilds(abortPrevious: true)])

def mavenEnv(Map params = [:], Closure body) {
  def attempt = 0
  def attempts = 3
  retry(count: attempts, conditions: [kubernetesAgent(), nonresumable()]) {
    echo 'Attempt ' + ++attempt + ' of ' + attempts
    node("maven-$params.jdk") { // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
        timeout(120) {
            sh 'mvn -version'
            infra.withArtifactCachingProxy {
                withEnv(["MAVEN_ARGS=-Dmaven.repo.local=${WORKSPACE_TMP}/m2repo"]) {
                    body()
                }
            }
            if (junit(testResults: '**/target/*-reports/TEST-*.xml').failCount > 0) {
                // TODO JENKINS-27092 throw up UNSTABLE status in this case
                error 'Some test failures, not going to continue'
            }
        }
    }
  }
}

def plugins
def lines
def fullTest = env.CHANGE_ID && pullRequest.labels.contains('full-test')

stage('prep') {
    mavenEnv(jdk: 11) {
        checkout scm
        withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
            sh 'bash prep.sh'
        }
        dir('target') {
            plugins = readFile('plugins.txt').split('\n')
            lines = readFile('lines.txt').split('\n')
            if (!fullTest) {
                lines = [lines[0], lines[-1]] // run PCT only on newest and oldest lines, to save resources
            }
            stash name: 'pct', includes: 'pct.jar'
            lines.each {stash name: "megawar-$it", includes: "megawar-${it}.war"}
        }
        stash name: 'pct.sh', includes: 'pct.sh'
        stash name: 'excludes.txt', includes: 'excludes.txt'
        infra.prepareToPublishIncrementals()
    }
}

branches = [failFast: !fullTest]
lines.each {line ->
    plugins.each { plugin ->
        branches["pct-$plugin-$line"] = {
            def jdk = line == 'weekly' ? 17 : 11
            mavenEnv(jdk: jdk) {
                deleteDir()
                unstash 'pct.sh'
                unstash 'excludes.txt'
                unstash 'pct'
                unstash "megawar-$line"
                launchable.install()
                launchable('verify')
                withEnv(["PLUGINS=$plugin", "LINE=$line", 'EXTRA_MAVEN_PROPERTIES=maven.test.failure.ignore=true:surefire.rerunFailingTestsCount=4']) {
                    sh 'mv megawar-$LINE.war megawar.war && bash pct.sh'
                }
                launchable("record tests --no-build maven './**/target/surefire-reports'")
            }
        }
    }
}
parallel branches

infra.maybePublishIncrementals()
