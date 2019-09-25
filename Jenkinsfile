def buildNumber = BUILD_NUMBER as int; if (buildNumber > 1) milestone(buildNumber - 1); milestone(buildNumber) // JENKINS-43353 / JENKINS-58625

def mavenEnv(body) {
    node('maven') { // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
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

def plugins
def lines

stage('prep') {
    mavenEnv {
        checkout scm
        withEnv(['SAMPLE_PLUGIN_OPTS=-Dset.changelist']) {
            sh 'bash prep.sh'
        }
        dir('target') {
            plugins = readFile('plugins.txt').split(' ')
            lines = readFile('lines.txt').split(' ')
            stash name: 'pct', includes: 'pct.jar'
            lines.each {stash name: "megawar-$it", includes: "megawar-${it}.war"}
        }
        stash name: 'ci', includes: 'pct.sh'
        infra.prepareToPublishIncrementals()
    }
}

branches = [failFast: true]
plugins.each { plugin ->
    lines.each {line ->
        branches["pct-$plugin-$line"] = {
            mavenEnv {
                deleteDir()
                unstash 'ci'
                unstash 'pct'
                unstash "megawar-$line"
                withEnv(["PLUGINS=$plugin", "LINE=$line"]) {
                    sh 'mv megawar-$LINE.war megawar.war && bash pct.sh'
                }
            }
        }
    }
}
parallel branches

infra.maybePublishIncrementals()
