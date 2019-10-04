#!/bin/bash
set -euxo pipefail
cd $(dirname $0)

MVN='mvn -B -ntp'
if [ -v MAVEN_SETTINGS ]
then
    MVN="$MVN -s $MAVEN_SETTINGS"
fi

$MVN clean install ${SAMPLE_PLUGIN_OPTS:-}

ALL_LINEZ=$(fgrep '<bom>' sample-plugin/pom.xml | sed -E 's, *<bom>(.+)</bom>,\1,g' | sort -rn)
: "${LINEZ:=$ALL_LINEZ}"
echo -n $LINEZ > target/lines.txt

rebuild=no
for LINE in $LINEZ
do
    if [ $rebuild = yes ]
    then
        $MVN -f sample-plugin clean package ${SAMPLE_PLUGIN_OPTS:-} -P$LINE
    else
        rebuild=yes
        pushd sample-plugin/target/test-classes/test-dependencies
        echo -n *.hpi | sed s/.hpi//g > ../../../../target/plugins.txt
        popd
    fi
    pushd sample-plugin/target
    mkdir jenkins
    echo '# nothing' > jenkins/split-plugins.txt
    cp -r jenkins-for-test megawar-$LINE
    jar uvf megawar-$LINE/WEB-INF/lib/jenkins-core-*.jar jenkins/split-plugins.txt
    rm -rfv megawar-$LINE/WEB-INF/detached-plugins megawar-$LINE/META-INF/*.{RSA,SF}
    mkdir megawar-$LINE/WEB-INF/plugins
    cp -rv test-classes/test-dependencies/*.hpi megawar-$LINE/WEB-INF/plugins
    cd megawar-$LINE
    jar c0Mf ../../../target/megawar-$LINE.war *
    popd
done

# TODO find a way to encode this in some POM so that it can be managed by Dependabot
version=0.3.0
pct=$HOME/.m2/repository/org/jenkins-ci/tests/plugins-compat-tester-cli/${version}/plugins-compat-tester-cli-${version}.jar
[ -f $pct ] || $MVN dependency:get -Dartifact=org.jenkins-ci.tests:plugins-compat-tester-cli:${version}-${timestamp}:jar -DremoteRepositories=https://repo.jenkins-ci.org/public/ -Dtransitive=false
cp $pct target/pct.jar

# produces: target/{megawar-*.war,pct.jar,plugins.txt,lines.txt}
