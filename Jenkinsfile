node('docker') {
    def settingsXml = "${pwd tmp: true}/settings-azure.xml"
    def ok = infra.retrieveMavenSettingsFile(settingsXml)
    assert ok
    checkout scm
    withEnv(["JAVA_HOME=${tool 'jdk8'}", 'PATH+JAVA=${JAVA_HOME}/bin', "PATH+MAVEN=${tool 'mvn'}/bin", "MAVEN_SETTINGS=$settingsXml"]) {
        sh 'echo $PATH; which java; which jar' // TODO
        sh 'bash ci.sh'
    }
    junit '**/target/surefire-reports/TEST-*.xml'
    warnError('some plugins could not be run in PCT') {
        sh 'fgrep -L "<status>INTERNAL_ERROR</status>" sample-plugin/target/pct-report.xml'
    }
}
