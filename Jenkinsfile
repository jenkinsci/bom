node('docker') {
    def settingsXml = "${pwd tmp: true}/settings-azure.xml"
    def ok = infra.retrieveMavenSettingsFile(settingsXml)
    assert ok
    checkout scm
    def javaHome=tool 'jdk8'
    withEnv(["JAVA_HOME=$javaHome", "PATH+JAVA=$javaHome/bin", "PATH+MAVEN=${tool 'mvn'}/bin", "MAVEN_SETTINGS=$settingsXml"]) {
        sh 'bash ci.sh'
    }
    junit '**/target/surefire-reports/TEST-*.xml'
    warnError('some plugins could not be run in PCT') {
        sh 'if fgrep -q "<status>INTERNAL_ERROR</status>" sample-plugin/target/pct-report.xml; then echo some plugins failed; exit 1; fi'
    }
}
