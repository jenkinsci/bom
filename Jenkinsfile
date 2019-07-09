node('docker') {
    checkout scm
    sh 'bash ci.sh'
    junit '**/target/surefire-reports/TEST-*.xml'
}
