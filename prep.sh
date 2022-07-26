#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "${0}")"

MVN='mvn -B -ntp'
if [[ -n ${MAVEN_SETTINGS-} ]]; then
	MVN="${MVN} -s ${MAVEN_SETTINGS}"
fi

$MVN clean install ${SAMPLE_PLUGIN_OPTS:-}

ALL_LINEZ=$(
	echo weekly
	grep -F '.x</bom>' sample-plugin/pom.xml | sed -E 's, *<bom>(.+)</bom>,\1,g' | sort -rn
)
: "${LINEZ:=$ALL_LINEZ}"
echo "${LINEZ}" >target/lines.txt

rebuild=false
for LINE in $LINEZ; do
	if $rebuild; then
		$MVN -f sample-plugin clean package ${SAMPLE_PLUGIN_OPTS:-} "-P${LINE}"
	else
		rebuild=true
		pushd sample-plugin/target/test-classes/test-dependencies
		ls -1 *.hpi | sed s/.hpi//g >../../../../target/plugins.txt
		popd
	fi
	pushd sample-plugin/target
	mkdir jenkins
	# TODO keep managed splits, overriding version with the managed one
	echo '# nothing' >jenkins/split-plugins.txt
	cp -r jenkins-for-test "megawar-${LINE}"
	jar uvf megawar-$LINE/WEB-INF/lib/jenkins-core-*.jar jenkins/split-plugins.txt
	rm -rfv megawar-$LINE/META-INF/*.{RSA,SF}
	mkdir "megawar-${LINE}/WEB-INF/plugins"
	cp -rv test-classes/test-dependencies/*.hpi "megawar-${LINE}/WEB-INF/plugins"
	cd "megawar-${LINE}"
	jar c0Mf "../../../target/megawar-${LINE}.war" *
	popd
done

# TODO find a way to encode this in some POM so that it can be managed by Dependabot
version=1178.vbef3c43d0e69
pct=$HOME/.m2/repository/org/jenkins-ci/tests/plugins-compat-tester-cli/${version}/plugins-compat-tester-cli-${version}.jar
[ -f "${pct}" ] || $MVN dependency:get -Dartifact=org.jenkins-ci.tests:plugins-compat-tester-cli:${version}:jar -DremoteRepositories=https://repo.jenkins-ci.org/public/,https://repo.jenkins-ci.org/incrementals/ -Dtransitive=false
cp "${pct}" target/pct.jar

# produces: target/{megawar-*.war,pct.jar,plugins.txt,lines.txt}
