node('docker') {
    checkout scm
    sh 'bash ci.sh'
    junit '**/target/surefire-reports/TEST-*.xml'
    warnError('some plugins could not be run in PCT') {
        sh 'fgrep -L "<status>INTERNAL_ERROR</status>" sample-plugin/target/pct-report.xml'
    }
}
