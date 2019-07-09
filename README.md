# Introduction

As proposed in [JENKINS-47498](https://issues.jenkins-ci.org/browse/JENKINS-47498),
this repository implements a [Maven BOM](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html#Importing_Dependencies)
which can be used in a plugin POM to more easily manage dependencies on other common plugins.
This is important because version management is a [common annoyance](https://jenkins.io/doc/developer/plugin-development/updating-parent/#understanding-requireupperbounddeps-failures-and-fixes).

# Usage

After selecting your plugin’s LTS baseline:

```xml
<jenkins.version>2.138.4</jenkins.version>
```

just import the latest BOM from that line:

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.jenkins.tools.bom</groupId>
            <artifactId>bom</artifactId>
            <version>2.138.1</version>
            <scope>import</scope>
            <type>pom</type>
        </dependency>
    </dependencies>
</dependencyManagement>
```

(The patch component of the BOM version is unrelated to the patch component of the Jenkins LTS version.
The major and minor components should match.)

Now you can declare dependencies on many plugins without needing to specify a version:

```xml
<dependency>
    <groupId>org.jenkins-ci.plugins.workflow</groupId>
    <artifactId>workflow-cps</artifactId>
    <scope>test</scope>
</dependency>
```

You can always override a version managed by the BOM if you wish,
but if you find the need to use a newer version,
first try just updating the version in the BOM and cutting a new release of it.

# Development

For people potentially working on the BOM itself, not just consuming it.

## Updating a plugin

You can try just incrementing plugin versions in `bom/pom.xml`.
If CI passes, great!
Dependabot will try doing this as well.

## Adding a new plugin

Insert a new `dependency` in _sorted_ order to `bom/pom.xml`.
Make sure it is used (perhaps transitively) in `sample-plugin/pom.xml`.
Ideally also update the sample plugin’s tests to actually exercise it,
as a sanity check.

You can also add a `<classifier>tests</classifier>` entry,
for a plugin which specifies `<no-test-jar>false</no-test-jar>`.
You should introduce a POM property so that the version is not repeated.

The build will enforce that all transitive plugin dependencies are also managed.

## PCT

The CI build tries running the [Plugin Compatibility Tester (PCT)](https://github.com/jenkinsci/plugin-compat-tester/)
on the particular combination of plugins being managed by the BOM.
This catches mutual incompatibilities between plugins
(as revealed by their `JenkinsRule` tests)
and the specified Jenkins LTS version.

If there is a PCT failure, fix it in the plugin with the failing test,
and when that fix is released, try updating the BOM again.

## LTS lines

The `master` branch should track the current LTS line.
A few historical lines are also tracked by branches,
for use from plugins which are not yet ready to depend on the latest.
The CI build (or just `mvn test`) will fail if some managed plugins are too new for the LTS line.
[This script](https://gist.github.com/jglick/0a85759ea65f60e107ac5a85a5032cae)
is a handy way to find the most recently released plugin version compatible with a given line,
according to the `jenkins-infra/update-center2` (which currently maintains releases for the past five lines).
