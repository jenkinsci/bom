def buildNumber = BUILD_NUMBER as int; if (buildNumber > 1) milestone(buildNumber - 1); milestone(buildNumber) // JENKINS-43353 / JENKINS-58625

def mavenEnv(body) {
    node('maven') { // no Dockerized tests; https://github.com/jenkins-infra/documentation/blob/master/ci.adoc#container-agents
        timeout(60) {
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

// TODO would much rather parallelize *all* PCT tests, but (INFRA-2283) ci.jenkins.io just falls over when we try.
// Running in parallel by plugin but serially by line works, albeit slowly, since workflow-cps is a bottleneck.
// So we try to manually constrain parallelism.
def semaphore = 30 // 50× parallelism usually works; 84× seems to fail reliably.
branches = [failFast: failFast]
lines.each {line ->
    plugins.each { plugin ->
        branches["pct-$plugin-$line"] = {
            // TODO JENKINS-29037 would be useful here to wait with a longer period
            waitUntil {if (semaphore > 0) {semaphore--; true} else {false}} // see JENKINS-27127
            assert semaphore >= 0
            try {
                mavenEnv {
                    deleteDir()
                    unstash 'pct.sh'
                    unstash 'pct'
                    unstash "megawar-$line"
                    withEnv(["PLUGINS=$plugin", "LINE=$line"]) {
                        sh 'mv megawar-$LINE.war megawar.war && bash pct.sh'
                    }
                }
            } finally {
                semaphore++
            }
        }
    }
}
parallel branches

infra.maybePublishIncrementals()
