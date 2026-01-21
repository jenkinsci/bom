# Contributing

For people working on the BOM itself, not just consuming it.

## Updating a plugin

You can try just incrementing plugin versions in `bom/pom.xml`.
If CI passes, great!
Renovate will try doing this as well.

In cases where two or more plugins must be updated as a unit as noted in
[JENKINS-49651](https://github.com/jenkinsci/jenkins/issues/22601),
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

> [!TIP]
> You can use `mvn spotless:apply` to sort the pom.xmls.

Make sure it is used (perhaps transitively) in `sample-plugin/pom.xml`.
Ideally, also update the sample plugin’s tests to actually exercise it,
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
LINE=2.516.x
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
