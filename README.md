# Bill of Materials for Jenkins plugins

This repository implements a [Maven BOM](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html#Importing_Dependencies)
which can be used in a plugin POM to more easily manage dependencies on other common plugins.
This is important because version management is a [common annoyance](https://jenkins.io/doc/developer/plugin-development/updating-parent/#understanding-requireupperbounddeps-failures-and-fixes).
See [JENKINS-47498](https://issues.jenkins-ci.org/browse/JENKINS-47498) for the background.

If you are interested in a Bill of Materials for Jenkins core components, see [this page](https://jenkins.io/doc/developer/plugin-development/dependency-management/#jenkins-core-bom).

# Usage

After selecting your plugin’s LTS baseline:

```xml
<jenkins.version>2.164.3</jenkins.version>
```

just import the [latest BOM](https://github.com/jenkinsci/bom/releases) from that line:

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.jenkins.tools.bom</groupId>
            <artifactId>bom-2.222.x</artifactId>
            <version>10</version>
            <scope>import</scope>
            <type>pom</type>
        </dependency>
    </dependencies>
</dependencyManagement>
```

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

When starting to use the BOM in an existing plugin,
you may find that many existing dependencies do not need to be expressed at all and can be deleted,
if they were added solely to satisfy the `RequireUpperBoundDeps` Enforcer rule or similar.
Maven will automatically add transitive dependencies to your classpath,
so you should only need to declare an explicit dependency on another plugin when:

* You compile against it. (Use `test` scope if it is only used in tests.)
* It is required to be present and not otherwise loaded transitively.
  (For example, `workflow-basic-steps` and `workflow-durable-task-step` are commonly required for tests which run Pipeline builds.)

The command

```sh
mvn dependency:analyze
```

can offer clues about unused plugin dependencies,
though you must evaluate each carefully since it only understands Java binary dependencies
(what is required for compilation, more or less).

# Development

For people potentially working on the BOM itself, not just consuming it.

## Updating a plugin

You can try just incrementing plugin versions in `bom/pom.xml`.
If CI passes, great!
Dependabot will try doing this as well.

In cases where two or more plugins must be updated as a unit
([JENKINS-49651](https://issues.jenkins-ci.org/browse/JENKINS-49651)),
file a PR changing the versions of both.

## Adding a new plugin

Insert a new `dependency` in _sorted_ order to `bom/pom.xml`.
Make sure it is used (perhaps transitively) in `sample-plugin/pom.xml`.
Ideally also update the sample plugin’s tests to actually exercise it,
as a sanity check.

Avoid adding transitive dependencies to `sample-plugin/pom.xml`. It is supposed
to look as much as possible like a real plugin, and a real plugin should only
declare its direct dependencies and not its transitive dependencies.

You can also add a `<classifier>tests</classifier>` entry,
for a plugin which specifies `<no-test-jar>false</no-test-jar>`.
You should introduce a POM property so that the version is not repeated.

The build will enforce that all transitive plugin dependencies are also managed.
If the build fails due to an unmanaged transitive plugin dependency, add it to
`bom/pom.xml`.

## PCT

The CI build tries running the [Plugin Compatibility Tester (PCT)](https://github.com/jenkinsci/plugin-compat-tester/)
on the particular combination of plugins being managed by the BOM.
This catches mutual incompatibilities between plugins
(as revealed by their `JenkinsRule` tests)
and the specified Jenkins LTS version.

If there is a PCT failure, fix it in the plugin with the failing test,
and when that fix is released, try updating the BOM again.

To reproduce a PCT failure locally, use something like

```sh
PLUGINS=structs,mailer TEST=InjectedTest bash local-test.sh
```

optionally also passing

```
DOCKERIZED=yes
```

to reproduce image-specific failures.

Note that to minimize build time, tests are run only on Linux, against JDK 8, and without Docker support.
It is unusual but possible for cross-component incompatibilities to only be visible in more specialized environments (such as Windows).

## LTS lines

A separate BOM artifact is available for the current LTS line and a few historical lines.
When a new LTS line is released (`jenkins-2.nnn.1`),
the main definition should be moved into its BOM (added to the aggregator POM),
and the the previous BOM made to inherit from it.
Older BOMs should only specify plugin version overrides compared to the next-newer BOM.
`sample-plugin` should be updated to use the latest line by default,
and get a new POM profile for the penultimate.
To get ahead of problems, prepare the draft PR for a line as soon as its baseline is announced.

The CI build (or just `mvn test -P2.nnn.x`) will fail if some managed plugins are too new for the LTS line.
[This script](https://gist.github.com/jglick/0a85759ea65f60e107ac5a85a5032cae)
is a handy way to find the most recently released plugin version compatible with a given line,
according to the `jenkins-infra/update-center2`.
The UC currently maintains releases for the past five lines,
so it is reasonable to retire BOMs for lines older than that.

## Releasing

`release:prepare` only runs basic tests about plugin versions, not the full PCT.
Therefore be sure to check [commit status](https://github.com/jenkinsci/bom/commits/master)
to ensure that CI builds have passed before cutting a release.

Due to a misconfiguration in Incrementals tooling (JENKINS-58641),
currently after every release you must manually run

```bash
mvn -f sample-plugin incrementals:reincrementalify
```

Commit and push the result to fix the branch build.

## Incrementals

This repository is integrated with “Incrementals” [JEP-305](https://jenkins.io/jep/305):

* Individual BOM builds, including from pull requests, are deployed and may be imported on an experimental basis by plugins.
  (Currently broken, pending JENKINS-58716.)
* Pull requests to the BOM may specify incremental versions of plugins, including unmerged PRs.
  (These should be resolved to formal release versions before the PR is merged.)

Together these behaviors should make it easier to verify compatibility of code changes still under review.

## GitHub tooling

This repository uses Dependabot to be notified automatically of available updates, mainly to plugins.
(It is not currently possible for Jenkins core updates to be tracked this way.)

Release Drafter is also used to prepare changelogs for the releases page.
