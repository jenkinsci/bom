def mavenEnv(body) {
    // TODO use label 'maven' for startup speed and newer Maven
    // (means no Dockerized tests like in durable-task)
    // but as in aci branch, https://github.com/jenkinsci/jnlp-agents/pull/2 means no git
    // (try https://github.com/carlossg/docker-maven/issues/110#issuecomment-497693840)
    node('docker') {
        def settingsXml = "${pwd tmp: true}/settings-azure.xml"
        def ok = infra.retrieveMavenSettingsFile(settingsXml)
        assert ok
        def javaHome=tool 'jdk8'
        withEnv(["JAVA_HOME=$javaHome", "PATH+JAVA=$javaHome/bin", "PATH+MAVEN=${tool 'mvn'}/bin", "MAVEN_SETTINGS=$settingsXml"]) {
            body()
        }
        junit testResults: '**/target/surefire-reports/TEST-*.xml', allowEmptyResults: true
        if (currentBuild.result == 'UNSTABLE') {
            error 'Some test failures, not going to continue'
        }
    }
}

def plugins

stage('prep') {
    mavenEnv {
        checkout scm
        def tmp = pwd tmp: true
        withEnv(["SAMPLE_PLUGIN_OPTS=-Dmaven.repo.local=$tmp/m2repo -Dset.changelist -Dexpression=changelist -Doutput=$tmp/changelist help:evaluate"]) {
            sh 'bash prep.sh'
        }
        dir('sample-plugin/target') {
            plugins = readFile('plugins.txt').split(' ')
            stash name: 'pct', includes: 'megawar.war,pct.jar'
        }
        stash name: 'ci', includes: 'pct.sh'
        def changelist = readFile("$tmp/changelist")
        dir("$tmp/m2repo") {
            archiveArtifacts artifacts: "**/*$changelist/*$changelist*", excludes: '**/sample/'
        }
    }
}

branches = [failFast: true]
plugins.each { plugin ->
    branches["pct-$plugin"] = {
        mavenEnv {
            deleteDir()
            unstash 'ci'
            unstash 'pct'
            withEnv(["PLUGINS=$plugin"]) {
                sh 'bash pct.sh'
            }
            warnError('some plugins could not be run in PCT') {
                sh 'if fgrep -q "<status>INTERNAL_ERROR</status>" pct-report.xml; then echo PCT failed; exit 1; fi'
            }
        }
    }
}
parallel branches

infra.maybePublishIncrementals()
