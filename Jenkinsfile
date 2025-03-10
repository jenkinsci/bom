properties([
  disableConcurrentBuilds(abortPrevious: true),
  // buildDiscarder(logRotator(numToKeepStr: '7')),
  // pipelineTriggers([cron('54 20 * * 6')])
])

node('maven-bom-cacher') {
  infra.withArtifactCachingProxy {
    withEnv([
      'JAVA_HOME=/opt/jdk-21',
      "MVN_LOCAL_REPO=${WORKSPACE_TMP}/m2repo",
    ]) {
      checkout scm

      sh '''
      mkdir -p "${MVN_LOCAL_REPO}"
      if test -f /cache-rw/maven-bom-local-repo.tar.gz;
      then
        pushd "${MVN_LOCAL_REPO}"
        time cp /cache-rw/maven-bom-local-repo.tar.gz ../
        time tar xzf ../maven-bom-local-repo.tar.gz
        rm -f ../maven-bom-local-repo.tar.gz
        popd
      fi
      '''

      sh '''
      mvn -pl sample-plugin dependency:go-offline -Dmaven.repo.local=${MVN_LOCAL_REPO}
      '''

      sh '''
      pushd "${MVN_LOCAL_REPO}"
      df -h .
      du -sh .
      time tar czf ../maven-bom-local-repo.tar.gz ./
      time cp ../maven-bom-local-repo.tar.gz /cache-rw/maven-bom-local-repo.tar.gz
      du -sh /cache-rw/*
      popd
      '''
    }
  }
}
