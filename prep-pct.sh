#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "${0}")"

# Tracked by .github/renovate.json
# TODO https://github.com/jenkinsci/plugin-compat-tester/pull/769
pct_version=1577.ve79fb_972e37e
pct="$(mvn -Dexpression=settings.localRepository -q -DforceStdout help:evaluate)/org/jenkins-ci/tests/plugins-compat-tester-cli/${pct_version}/plugins-compat-tester-cli-${pct_version}.jar"
[ -f "${pct}" ] || mvn dependency:get -Dartifact=org.jenkins-ci.tests:plugins-compat-tester-cli:${pct_version}:jar -DremoteRepositories=repo.jenkins-ci.org::default::https://repo.jenkins-ci.org/public/,incrementals::default::https://repo.jenkins-ci.org/incrementals/ -Dtransitive=false
cp "${pct}" target/pct.jar

# produces: target/pct.jar
