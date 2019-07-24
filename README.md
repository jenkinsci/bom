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

just import the [latest BOM](https://github.com/jenkinsci/bom/releases) from that line:

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

(The patch component of the BOM version, `1` in this example,
is unrelated to the patch component of the Jenkins LTS version, `4` in this example.
Generally you should select the latest of each patch component independently.
The major and minor components, in this example `2` and `138` respectively, must match.)

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

To reproduce a PCT failure locally, use something like

```sh
PLUGINS=structs,mailer TEST=InjectedTest bash local-test.sh
```

Note that to minimize build time, tests are run only on Linux, against JDK 8, and without Docker support.
It is unusual but possible for cross-component incompatibilities to only be visible in more specialized environments (such as Windows).

## LTS lines

The `master` branch should track the current LTS line.
A few historical lines are also tracked by branches,
for use from plugins which are not yet ready to depend on the latest.
Each line is released independently with `maven-release-plugin`.
When a new LTS line is released (`jenkins-2.xxx.1`),
a new BOM branch should be cut from the current `master`,
and `master` made to track the new line.

The CI build (or just `mvn test`) will fail if some managed plugins are too new for the LTS line.
[This script](https://gist.github.com/jglick/0a85759ea65f60e107ac5a85a5032cae)
is a handy way to find the most recently released plugin version compatible with a given line,
according to the `jenkins-infra/update-center2` (which currently maintains releases for the past five lines).

General changes (such as to CI infrastructure), and most dependency updates, should be done in `master` first.
Commits from `master` should be merged into the next older LTS branch,
and from there into the branch one older, and so on.
This ensures that CI-related changes propagate to all branches without manual copy-and-paste.
Merge conflicts should be resolved in favor of the `HEAD`,
so that the branches differ from `master` only in POMs (and perhaps in sample plugin code).

To be safe, rather than directly pushing merges, prepare them in a PR branch:

```sh
git checkout -b 2.164.x-merge 2.164.x
git merge master
git push fork
# file a PR from youracct:2.164.x-merge → jenkinsci:2.164.x
git checkout -b 2.150.x-merge 2.150.x
git merge 2.164.x-merge
git push fork
# etc.
```

and only merge the PR if CI passes.

## Releasing

`release:prepare` only runs basic tests about plugin versions, not the full PCT.
Therefore be sure to check [commit status for the selected branch](https://github.com/jenkinsci/bom/commits/master)
to ensure that CI builds have passed before cutting a release.

Due to a misconfiguration in Incrementals tooling,
currently after every release you must manually edit `sample-plugin/pom.xml`
and reset `version` to `${revision}${changelist}`
and set `revision` to that of the top-level `pom.xml`.
Commit and push the result to fix the branch build.

## Incrementals

This repository is integrated with “Incrementals” [JEP-305](https://jenkins.io/jep/305):

* Individual BOM builds, including from pull requests, are deployed and may be imported on an experimental basis by plugins.
* Pull requests to the BOM may specify incremental versions of plugins, including unmerged PRs.
  (These should be resolved to formal release versions before the PR is merged.)

Together these behaviors should make it easier to verify compatibility of code changes still under review.

## GitHub tooling

This repository uses Dependabot to be notified automatically of available updates, mainly to plugins.
(It is not currently possible for Jenkins core updates to be tracked this way.)

Release Drafter is also used to prepare changelogs for the releases page.
