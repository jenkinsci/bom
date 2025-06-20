# Contributing

For people potentially working on the BOM itself, not just consuming it.

## BOM release leads

| Release Date | Lead                 |
| ------------ | -------------------- |
| 2025-06-27   | Bruno Verachten      |
| 2025-07-04   | Bruno Verachten      |
| 2025-07-11   | Basil Crow           |
| 2025-07-18   | Basil Crow           |
| 2025-07-25   | Adrien Lecharpentier |
| 2025-08-01   | Adrien Lecharpentier |
| 2025-08-08   | Kris Stern           |
| 2025-08-15   | Kris Stern           |
| 2025-08-22   | Mark Waite           |
| 2025-08-29   | Mark Waite           |

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

[!TIP]
You can use `mvn spotless:apply` to sort the pom.xmls.

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
LINE=2.479.x
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

## A week in the life of a BOM release manager

A BOM release manager is in charge of BOM releases for 2 weeks.

As a BOM release manager, you'll be working directly with the `jenkinsci/bom` repository. Said differently, think hard before using your fork of the `bom` repository.

### Task handling

#### Dependabot created PRs

This will probably be the majority of work you'll do.

In a perfect world, a Dependabot PR will just auto-merge into `master` and you won't have to do anything.

In a not so perfect world, a Dependabot PR will fail to build. Most of the time, it's because a plugin is too new for older LTS lines. The way you'll resolve this issue is to pin the older version to the correct LTS line.

[!TIP]
If you do have to do work on a PR, make sure to assign the PR to yourself so others can see that you are actively looking at the PR.

The easiest way to work on the PR is to use the `gh` CLI to checkout the PR:

* `gh pr checkout <PR id>`

Then you can work on the PR. Once done, push your changes back to the PR. If everything is successful, the PR will auto-merge. At this point, you can delete the local branch:

* `git branch -D <branchName>`

#### Known issues and examples

There are some known issues that commonly need to be addressed by the BOM release manager.

##### Dependency requires Jenkins 2.xxx.y or higher

This message shows that a plugin requires a newer Jenkins LTS than one or more of the LTS lines supported by the BOM. Pin the older version to the correct LTS line to resolve the issue.  Some pull requests that pin older plugin versions include:

* [cloudbees-folder 6.959.v4ed5cc9e2dd4](https://github.com/jenkinsci/bom/pull/3979)
* [git-client 4.0.0 and git 5.0.0](https://github.com/jenkinsci/bom/pull/1663)
* [reverse-proxy-auth 1.8.0](https://github.com/jenkinsci/bom/pull/3930)

##### Failed to load - update required

This message usually shows that an optional dependency of a plugin is not being updated by the [Plugin Compatibility Tester (PCT)](https://github.com/jenkinsci/plugin-compat-tester/) and that update is needed by another plugin. This is a [known issue](https://github.com/jenkinsci/bom/issues/3158) in PCT. Workarounds include:

* Add the optional dependency in test scope to the affected plugin. The workaround leaves an unnecessary test dependency in the affected plugin in order to avoid the issue
* Pin an older version of the optional plugin on older LTS lines if the issue is not visible in the weekly line. This only works if the specific issue is not visible on the weekly line.

Some pull requests that add the optional dependency in test scope include:

* [Customer folder icon add test dependency on config-file-provider](https://github.com/jenkinsci/custom-folder-icon-plugin/pull/282) and [issue 280](https://github.com/jenkinsci/custom-folder-icon-plugin/issues/280)
* [Mark trilead API as test even if not needed](https://github.com/jenkinsci/mina-sshd-api-plugin/pull/91), followed by [remove trilead](https://github.com/jenkinsci/mina-sshd-api-plugin/pull/98)

A pull request that pins an older version of the optional plugin is:

* [Pin htmlpublisher 1.36 for older lines](https://github.com/jenkinsci/bom/pull/3975)

#### Manually created PRs

When there is a manually generated PR, there's probably a pretty good chance as the BOM release manager you won't have to do anything. The person opening the PR should open the PR as `draft`. As a BOM release manager, feel free to look at a `draft` PR, but don't spend much time on it.

On the other hand, if the person reaches out for help, be sure to help them.

### Day of week tasks

This section goes over the expectations and work items for the BOM release manager during their on-call cycle.

The scripts that are referenced are in the `release-manager-scripts` directory.
Open a terminal and `cd` to that directory before running the scripts.
Alternatively, you can call them from wherever you want, just know that they are located in the `release-manager-scripts` directory.

#### Thursday (Prep for BOM release)

* run `./bom-release-issue-create.sh <yyyy-MM-dd>`
  * Example: `./bom-release-issue-create.sh 2024-10-14`
  * use the desired date of the release, not the date when you create the ticket
* on the newly created issue, manually set `Type` to `Task`
  * at the time of writing (2024-10-14), there is no `gh` option to set the Type
* check the CRON expression to see if the pre-release build will be executed at a time suited for you
  * this can also be used to change when the release happened if you prefer the release to be made on thurday
  * run `./bom-release-issue-complete-task.sh 1`
* Locally run tests for `warnings-ng` for all current LINEs and weekly
  * `./bom-test-all-lines.sh warnings-ng`

#### Friday (BOM release day)

* run `./bom-lock-master.sh` before the job runs
  * currently, the job is [scheduled to run at 11:HH am UTC (actual 11:26am)](https://github.com/jenkinsci/bom/blob/master/Jenkinsfile#L4)
* verify that the [branch is locked](https://github.com/jenkinsci/bom/settings/branch_protection_rules/6421306)
* wait to verify that job started at [ci.jenkins.io](https://ci.jenkins.io/job/Tools/job/bom/job/master/)
* run `./bom-release-issue-job-running.sh <buildNumber>`
  * Example: `./bom-release-issue-job-running.sh 1234`
* wait for build to make it through the `prep` stage then (typically) take a 1.5-2 hr break
* [LOOP] if there are any failures, fix until everything is successful
* run `./bom-run-cd-workflow.sh`
* wait for the release process to complete
  * this takes 7-8 minutes
* manually edit the auto-generated release notes
  * remove `<!-- Optional: add a release summary here -->`
  * remove `<details>`
  * remove `<summary>XYZ changes</summary>`
  * remove `</details>`
* run `./bom-release-issue-add-release-comment.sh`
* run `./bom-unlock-master.sh`
* verify that the [branch is unlocked](https://github.com/jenkinsci/bom/settings/branch_protection_rules/6421306)
* run `./bom-release-issue-close.sh`

For tasks that don't have a specific script, i.e. tasks 1, 5, 6, 8 and 11, you can run `./bom-release-issue-complete-task.sh <task number>` to check the box off without having to manually edit the issue.

#### Saturday/Sunday/Monday

* business as usual tasks

#### Tuesday (test the new weekly)

* run the Dependabot dependency graph checks
  * open [Dependency graph for sample-plugin/pom.xml](https://github.com/jenkinsci/bom/network/updates/5427365/jobs)
  * click on "Check for updates" button in upper right hand corner of table
  * open [Dependency graph for bom-weekly/pom.xml](https://github.com/jenkinsci/bom/network/updates/10189727/jobs)
  * click on "Check for updates" button in upper right hand corner of table
* wait for both of the Dependabot dependency graph checks to complete
* check to see if any new dependabot PRs were opened. If there were, make sure they clear and merge before continuing.
* Open the pinned [Dependency Dashboard](https://github.com/jenkinsci/bom/issues/2500) issue
* Once the weekly build has completed, you will see a line that says "Update dependency org.jenkins-ci.main:jenkins-war to v2.`XYZ`", where `XYZ` is the weekly build number. Click the checkbox next to that line to start the full test.
* Once the box is checked, a new PR will be created by renovate named "Update dependency org.jenkins-ci.main:jenkins-war to v2.`XYZ`" where `XYZ` is the weekly build number. This will fire off a full `weekly` build that will take about 1.5-2 hours to complete.
* If everything succeeds, the PR will auto-merge.
* Once the auto-merge completes, go back to the [Dependency Dashboard](https://github.com/jenkinsci/bom/issues/2500) issue and check the box for "Check this box to trigger a request for Renovate to run again on this repository". This will remove the "Update dependency..." line from the issue.

#### Wednesday

* business as usual tasks

## Using `gh` CLI

As someone that is "on-call" for managing BOM, there are a few helpful aliases/scripts that you can create to make your life easier.

### Pre-requisites

These aliases use `git`, `sed` and `gh`. If you haven't installed `gh` yet, do that and go ahead and login using:

`gh auth login`

You'll answer the questions:

* Where do you use GitHub?
  * GitHub.com
* What is your preferred protocol for Git operations on this host?
  * HTTPS
* Authenticate Git with your GitHub credentials?
  * Y
* How would you like to authenticate GitHub CLI?
  * Login with a web browser
* Copy your one time code from the command line then press `Enter`
* Depending on if you are already logged into GitHub with the browser that opened, you may have a few different steps. Eventually, you should get to a "Device Activation" screen. Click on the `Continue` button beside your avatar.
* Enter the code you copied from the command line and click `Continue`
* Now you'll be on the "Authorize GitHub CLI" screen. Click on the "Authorize github" button at the bottom of the page.
  * You may be asked to confirm access in various forms. Just follow the instructions.
* Once you complete the web login, look back at your command prompt. You should see that the login process has completed.

Once you are logged in, you can use the scripts in `release-manager-scripts`.

### Scripts

#### bom-release-issue-create.sh

This script creates the boilerplate GitHub issue for the weekly BOM release, as well as pinning the issue.

#### bom-release-issue-job-running.sh

This script updates the body of the GitHub issue by checking the `Trigger` task item.

#### bom-release-issue-add-release-comment.sh

This script adds a comment to the GitHub issue with the latest release number.

#### bom-release-issue-close.sh

This script unpins and closes the GitHub issue.

#### bom-lock-master.sh

This script:

* locks the `master` branch
* updates the GitHub issue body by checking the `Lock branch` task item.

#### bom-unlock-master.sh

This script:

* unlocks the `master` branch
* updates the GitHub issue body by checking the `Unlock branch` task item.

#### bom-get-branch-protection.sh

This script returns the lock state of the `master` branch.

#### bom-line-test.sh

This is a helper script to test a plugin against a specific Jenkins line.

#### bom-test-all-lines.sh

This is a helper script that calls `bom-line-test.sh` for all active Jenkins lines.
