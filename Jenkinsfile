def buildNumber = BUILD_NUMBER as int; if (buildNumber > 1) milestone(buildNumber - 1); milestone(buildNumber) // JENKINS-43353 / JENKINS-58625

def mavenEnv(body) {
    node('maven') { // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
        timeout(90) {
            sh 'mvn -version'
            def settingsXml = "${pwd tmp: true}/settings-azure.xml"
            def ok = infra.retrieveMavenSettingsFile(settingsXml)
            assert ok
            withEnv(["MAVEN_SETTINGS=$settingsXml"]) {
                body()
            }
            if (junit(testResults: '**/target/surefire-reports/TEST-*.xml', allowEmptyResults: true).failCount > 0) {
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
    mavenEnv {
        checkout scm
        failFast = Boolean.parseBoolean(readFile('failFast').trim())
        withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
            sh 'bash prep.sh'
        }
        dir('target') {
            plugins = readFile('plugins.txt').split(' ')
            lines = readFile('lines.txt').split(' ')
            lines = [lines[0], lines[-1]] // run PCT only on newest and oldest lines, to save resources
            stash name: 'pct', includes: 'pct.jar'
            lines.each {stash name: "megawar-$it", includes: "megawar-${it}.war"}
        }
        stash name: 'pct.sh', includes: 'pct.sh'
        infra.prepareToPublishIncrementals()
    }
}

branches = [failFast: failFast]
lines.each {line ->
    plugins.each { plugin ->
      if (plugin != 'pipeline-model-definition') { // TODO re-enable once pipeline-model-definition tests are stable
        branches["pct-$plugin-$line"] = {
          retry(2) { // in case of transient node outages
            mavenEnv {
                deleteDir()
                unstash 'pct.sh'
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
}
parallel branches

infra.maybePublishIncrementals()
