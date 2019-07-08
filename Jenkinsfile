node('maven') {
    checkout scm
    sh 'mvn -B -ntp -Dmaven.test.failure.ignore install'
    junit '**/target/surefire-reports/TEST-*.xml'
}
