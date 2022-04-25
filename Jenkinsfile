properties([disableConcurrentBuilds(abortPrevious: true)])

def mavenEnv(Map params = [:], Closure body) {
    def agentContainerLabel = params['jdk'] == 8 ? 'maven' : 'maven-' + params['jdk']
    node(agentContainerLabel) { // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
        timeout(90) {
            sh 'mvn -version'
            def settingsXml = "${pwd tmp: true}/settings-azure.xml"
            def ok = infra.retrieveMavenSettingsFile(settingsXml)
            assert ok
            withEnv(["MAVEN_SETTINGS=$settingsXml"]) {
                body()
            }
            if (junit(testResults: '**/target/surefire-reports/TEST-*.xml', allowEmptyResults: true, skipMarkingBuildUnstable: !!params['skipMarkingBuildUnstable']).failCount > 0) {
                // TODO JENKINS-27092 throw up UNSTABLE status in this case
                error 'Some test failures, not going to continue'
            }
        }
    }
}

def plugins
def lines
def failFast

stage('prep') {
    mavenEnv(jdk: 11) {
        checkout scm
        failFast = Boolean.parseBoolean(readFile('failFast').trim())
        withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
            sh 'bash prep.sh'
        }
        dir('target') {
            plugins = readFile('plugins.txt').split('\n')
            lines = readFile('lines.txt').split('\n')
            lines = [lines[0], lines[-1]] // run PCT only on newest and oldest lines, to save resources
            stash name: 'pct', includes: 'pct.jar'
            lines.each {stash name: "megawar-$it", includes: "megawar-${it}.war"}
        }
        stash name: 'pct.sh', includes: 'pct.sh'
        stash name: 'excludes.txt', includes: 'excludes.txt'
        infra.prepareToPublishIncrementals()
    }
}

branches = [failFast: failFast]
lines.each {line ->
    plugins.each { plugin ->
        branches["pct-$plugin-$line"] = {
          def attempt = 0
          def attempts = 2
          retry(attempts) { // in case of transient node outages
            echo 'Attempt ' + ++attempt + ' of ' + attempts
            mavenEnv(jdk: line == 'weekly' ? 17 : 11, skipMarkingBuildUnstable: attempt < attempts) {
                deleteDir()
                unstash 'pct.sh'
                unstash 'excludes.txt'
                unstash 'pct'
                unstash "megawar-$line"
                withEnv(["PLUGINS=$plugin", "LINE=$line", 'EXTRA_MAVEN_PROPERTIES=surefire.rerunFailingTestsCount=4']) {
                    sh 'mv megawar-$LINE.war megawar.war && bash pct.sh'
                }
            }
          }
        }
    }
}
parallel branches

infra.maybePublishIncrementals()
