#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "${0}")"

# Tracked by ./updatecli/updatecli.d/plugin-compat-tester.yml
pct_version=1337.vd1853588a_0c6
pct="$(mvn -Dexpression=settings.localRepository -q -DforceStdout help:evaluate)/org/jenkins-ci/tests/plugins-compat-tester-cli/${pct_version}/plugins-compat-tester-cli-${pct_version}.jar"
[ -f "${pct}" ] || mvn dependency:get -Dartifact=org.jenkins-ci.tests:plugins-compat-tester-cli:${pct_version}:jar -DremoteRepositories=repo.jenkins-ci.org::default::https://repo.jenkins-ci.org/public/,incrementals::default::https://repo.jenkins-ci.org/incrementals/ -Dtransitive=false
cp "${pct}" target/pct.jar

# produces: target/pct.jar
