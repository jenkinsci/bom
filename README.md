# Bill of Materials for Jenkins plugins

This repository implements a [Maven BOM](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html#Importing_Dependencies)
which can be used in a plugin POM to more easily manage dependencies on other common plugins.
This is important because version management is a [common annoyance](https://jenkins.io/doc/developer/plugin-development/updating-parent/#understanding-requireupperbounddeps-failures-and-fixes).
See [JENKINS-47498](https://issues.jenkins-ci.org/browse/JENKINS-47498) for the background.

A secondary purpose of this repository is to regularly perform plugin compatibility testing (PCT) against new or forthcoming releases of core and plugins.

If you are interested in a Bill of Materials for Jenkins core components, see [this page](https://jenkins.io/doc/developer/plugin-development/dependency-management/#jenkins-core-bom).

# Usage

After [selecting your plugin’s LTS baseline](https://www.jenkins.io/doc/developer/plugin-development/choosing-jenkins-baseline/):

```xml
<jenkins.version>2.426.3</jenkins.version>
```

just import the [latest BOM](https://repo.jenkins-ci.org/public/io/jenkins/tools/bom) from that line:

```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.jenkins.tools.bom</groupId>
            <artifactId>bom-2.426.x</artifactId>
            <version>…</version>
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

A [BOM tutorial video](https://www.jenkins.io/doc/developer/tutorial-improve/use-plugin-bill-of-materials/) is available in the [Jenkins developer documentation](https://www.jenkins.io/doc/developer/tutorial-improve/).

## Depending on `bom-weekly`

The `bom-weekly` line is a special artifact that follows the weekly release of Jenkins core.
You would only depend on it when you are actively tracking the weekly release line.

Some examples of when you would use it:
- You run tests in your plugin against the weekly version of Jenkins
- You depend on the Jenkins core weekly line and update it regularly, ([example](https://github.com/jenkins-infra/pipeline-steps-doc-generator))

You would not use it:
- When you are temporarily depending on the weekly line but do not plan to update it on every release
  - This would cause dependabot build failures when a plugin is updated only on the weekly line (if you depend on it)

## Depending on older versions

Sometimes a plugin maintainer may prefer to require an older version of Jenkins as its minimum version.
Refer to [choosing a Jenkins version](https://www.jenkins.io/doc/developer/plugin-development/choosing-jenkins-baseline/) for more details.

When an older Jenkins version is used, then the matching older version of the plugin bill of materials should be used.

| BOM Line    | Version               | Comment                      |
| ----------- | --------------------- | ---------------------------- |
| bom-2.346.x | 1763.v092b_8980a_f5e  | Last LTS to support Java 8   |
| bom-2.361.x | 2102.v854b_fec19c92   | First LTS to require Java 11 |
| bom-2.375.x | 2198.v39c76fc308ca    |                              |
| bom-2.387.x | 2543.vfb_1a_5fb_9496d |                              |
| bom-2.401.x | 2745.vc7b_fe4c876fa_  |                              |

The latest versions of all BOM lines are available from the [Jenkins artifact repository](https://repo.jenkins-ci.org/public/io/jenkins/tools/bom).

# Development

For people potentially working on the BOM itself, not just consuming it.

## Updating a plugin

You can try just incrementing plugin versions in `bom/pom.xml`.
If CI passes, great!
Dependabot will try doing this as well.

In cases where two or more plugins must be updated as a unit
([JENKINS-49651](https://issues.jenkins-ci.org/browse/JENKINS-49651)),
file a PR changing the versions of both.

## When to add a new plugin

Though the primary purpose of this repository is to manage the set of versions of dependencies used by dependents,
a secondary purpose is to provide plugin compatibility testing (PCT).
For example, risky changes to core or plugins are often run through this test suite to find potential problems.

For this reason, it can be desirable to add plugins to the managed set even when they have no dependents.
The more critical a plugin is, the more it would benefit from plugin compatibility testing and thus inclusion in the managed set.
While different people have different definitions as to what constitutes "critical", some common definitions are:

- In the default list of suggested plugins
- In the list of the top 100 (or 250) plugins
- In the list of plugins with more than 10,000 (or 1,000) users

Since any PCT issues with a plugin that is in the managed set must be dealt with in a timely manner,
it is key that all plugins in the managed set have active maintainers that are able to cut releases when needed.

A good candidate for inclusion in the managed set is a critical plugin with an active maintainer,
regardless of whether or not it has dependents.

A plugin that is not critical could be tolerated in the managed set,
as long as it poses a low maintenance burden and has an active maintainer.

A critical plugin without a maintainer poses a dilemma:
while inclusion in the managed set provides desirable compatibility testing,
it also results in friction when changes need to be made for PCT purposes and nobody is around to release them.
Ideally, this dilemma would be resolved by someone adopting the plugin.
In the worst case, such plugins can be excluded from the managed set.

## How to add a new plugin

Insert a new `dependency` in _sorted_ order to `bom-weekly/pom.xml`.
Make sure it is used (perhaps transitively) in `sample-plugin/pom.xml`.
Ideally also update the sample plugin’s tests to actually exercise it,
as a sanity check.

Avoid adding transitive dependencies to `sample-plugin/pom.xml`. It is supposed
to look as much as possible like a real plugin, and a real plugin should only
declare its direct dependencies and not its transitive dependencies.

You should also add a `<classifier>tests</classifier>` entry,
for a plugin which specifies `<no-test-jar>false</no-test-jar>`.
You should introduce a POM property so that the version is not repeated.

The build will enforce that all transitive plugin dependencies are also managed.
If the build fails due to an unmanaged transitive plugin dependency, add it to
`bom-weekly/pom.xml`.

## PCT

The CI build can run the [Plugin Compatibility Tester (PCT)](https://github.com/jenkinsci/plugin-compat-tester/)
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

optionally also passing either

```
LINE=2.426.x
```

or

```
DOCKERIZED=true
```

to reproduce image-specific failures.

You can also pass

```sh
PCT_OPTS=--local-checkout-dir=/path/to/plugin
```

to check a local patch without waiting for incrementals deployment,
if you have switched the version in `bom-weekly/pom.xml` to a `*-SNAPSHOT`.

To minimize cloud resources, PCT is not run at all by default on pull requests, only some basic sanity checks.
Add the label `full-test` to run PCT in a PR.
If you lack triage permission and so cannot add this label, then you may instead

```bash
echo 'TODO delete me' > full-test
git add full-test
git commit -m 'Run full tests'
```

while keeping the PR in draft until tests pass and this file can be deleted.

Similarly, the `weekly-test` label (or marker file) can be used to run tests on weekly releases in isolation.

To further minimize build time, tests are run only on Linux, against Java 11, and without Docker support.
It is unusual but possible for cross-component incompatibilities to only be visible in more specialized environments (such as Windows).

## LTS lines

A separate BOM artifact is available for the latest weekly, current LTS line and a few historical lines.
BOMs should only specify plugin version overrides compared to the next-newer BOM.
`sample-plugin` will use the weekly line by default,
and get a new POM profile for the others.
To get ahead of problems, prepare the draft PR for a line as soon as its baseline is announced.

The CI build (or just `mvn test -P2.nnn.x`) will fail if some managed plugins are too new for the LTS line.
[This script](https://gist.github.com/jglick/0a85759ea65f60e107ac5a85a5032cae)
is a handy way to find the most recently released plugin version compatible with a given line,
according to the `jenkins-infra/update-center2`.

The [developer documentation](https://www.jenkins.io/doc/developer/plugin-development/choosing-jenkins-baseline/) recommends the last releases of each of the previous two LTS baselines.
BOMs for the current LTS release and two prior LTS releases are typically retained.
BOMs older than the two prior LTS releases will generally be retired in order to better manage evaluation costs and maintenance efforts.

## Releasing

You can cut a release using [JEP-229](https://jenkins.io/jep/229).
To save resources, `master` is built only on demand, so use **Re-run checks**  in https://github.com/jenkinsci/bom/commits/master if you wish to start.
If that build passes, a release should be published automatically when PRs matching certain label patterns are merged.
For the common case that only lots of `dependencies` PRs have been merged,
the release can be triggered manually from the **Actions** tab after a `master` build has succeeded.

## Incrementals

This repository is integrated with “Incrementals” [JEP-305](https://jenkins.io/jep/305):

* Individual BOM builds, including from pull requests, are deployed and may be imported on an experimental basis by plugins.
  (The plugin’s POM must use the `gitHubRepo` property as shown in [workflow-step-api-plugin #58](https://github.com/jenkinsci/workflow-step-api-plugin/pull/58/files).)
* Pull requests to the BOM may specify incremental versions of plugins, including unmerged PRs.
  (These should be resolved to formal release versions before the PR is merged.)

Together these behaviors should make it easier to verify compatibility of code changes still under review.

## GitHub tooling

This repository uses Dependabot to be notified automatically of available updates, mainly to plugins.
(It is not currently possible for Jenkins core updates to be tracked this way.)

Release Drafter is also used to prepare changelogs for the releases page.
