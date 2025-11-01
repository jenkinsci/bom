# Releasing

The plugin bill of materials rotates release lead responsibilities between different volunteers as listed in [BOM release leads](#bom-release-leads).
Release leads serve for two weeks, then the release lead assignment is rotated to another person.
Release leads resolve dependency update failures during their release lead assignment.
Details are described in [a week in the life of a BOM release manager](#a-week-in-the-life-of-a-bom-release-manager) with some additional information in the [plugin compatibility tester (PCT) section](CONTRIBUTING.md#pct) of the contributing guide.

## BOM release leads

| Release Date | Lead                 |
| ------------ | -------------------- |
| 2025-10-31   | Kris Stern           |
| 2025-11-07   | Kris Stern           |
| 2025-11-14   | Bruno Verachten      |
| 2025-11-21   | Bruno Verachten      |
| 2025-11-28   | Mark Waite           |
| 2025-12-05   | Mark Waite           |
| 2025-12-12   | Darin Pope           |
| 2025-12-19   | Darin Pope           |
| 2025-12-26   | Adrien Lecharpentier |
| 2026-01-02   | Adrien Lecharpentier |

## Releasing the BOM

You can cut a release using [JEP-229](https://jenkins.io/jep/229).
To save resources, `master` is built only on demand, so use **Re-run checks**  in https://github.com/jenkinsci/bom/commits/master if you wish to start.
If that build passes, a release should be published automatically when PRs matching certain label patterns are merged.
For the common case that only lots of `dependencies` PRs have been merged,
the release can be triggered manually from the **Actions** tab after a `master` build has succeeded.

If a `master` build succeeds but does not notify GitHub of the success, the release process will not run.
In one case where that happened, we were able to replay the Pipeline on the `master` branch to show the failing test was passing.
The Pipeline replay was:

```
publishChecks(name: 'pct-blueocean-plugin-weekly')
echo 'OK'
```

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

##### Handling Rollbacks

Sometimes a dependency update that was merged and released causes compatibility issues or test failures that are discovered after the BOM release. When this happens, a rollback process is needed to temporarily revert the problematic change while the issue is investigated and resolved.

###### When to Consider a Rollback

Consider rolling back a dependency update when:

- The updated dependency causes test failures in downstream plugins
- The update introduces breaking changes that affect plugin compatibility
- Critical functionality is broken after the dependency update
- The issue cannot be quickly resolved and is blocking the release process

###### Rollback Process

When a problematic dependency update needs to be rolled back, follow these steps:

1. Notify the Author

**Notify the author of the problematic change as close as possible to the actual problem area.** Leave a comment on the original PR or commit that introduced the issue, explaining the specific problems encountered.

**Example:**
```
Looks like these changes are causing issues with doing a BOM release this week. For reference:

tl;dr...two plugins that passed on the Tuesday weekly-test (foo-plugin and bar-plugin) are now failing.

For the moment so I can get the BOM release out today, I'm going to revert the PR that put in github-branch-source 1844.v4a_9883d49126.

The local BOM commands I'm running that are failing are:
- `LINE=weekly PLUGINS=bar-plugin bash local-test.sh`
- `LINE=weekly PLUGINS=foo-plugin bash local-test.sh`

As noted, when I locally go back to github-branch-source 1834.v857721ea_74c6 both tests are passing.
```

**Reference:** See [this example notification](https://github.com/jenkinsci/github-branch-source-plugin/pull/822#issuecomment-3238052920) to the plugin author.

2. Revert the Change

Create a revert commit that rolls back the problematic dependency update. In your commit message, include a link to the notification you sent to the author.

**Example commit message:**
```
Revert "chore(deps): bump org.jenkins-ci.plugins:github-branch-source from 1834.v857721ea_74c6 to 1844.v4a_9883d49126 in /bom-weekly"

Rolling back due to compatibility issues with downstream plugins.
See notification to author: https://github.com/jenkinsci/github-branch-source-plugin/pull/822#issuecomment-3238052920
```

3. Trigger Dependabot

Comment `@dependabot rebase` on the reverted PR to trigger Dependabot to reprocess the change.

4. Disable Automerge

Disable automerge for the PR to prevent it from being automatically merged again while the issue is being investigated.

5. Request Changes Review

- Click on **"Files changed"** tab in the PR
- Click **"Review changes"** 
- Select **"Request changes"**
- Add a comment explaining why changes are requested (reference the compatibility issues)
- Click **"Submit review"**

6. Add `weekly-test` Label

Add the `weekly-test` label to the PR to ensure it gets additional testing before being considered for merge again.

7. Leave the PR Open

Do not close the PR. Leave it open so that:
- The issue remains visible and can be tracked
- The author can address the compatibility issues
- Testing can be re-run once fixes are implemented

8. Convert to Draft

Convert the PR to draft status by clicking the **"Convert to draft"** link at the bottom of the Reviewers block. This signals that the PR is not ready for merge.

###### Example Rollback

For a complete example of this rollback process in action, see [BOM PR #5611](https://github.com/jenkinsci/bom/pull/5611), which demonstrates:

- Author notification with specific failure details
- Revert commit with reference to the notification
- PR converted to draft status
- Changes requested with clear explanation
- `weekly-test` label applied
- Automerge disabled

###### After the Rollback

Once the rollback is complete:

1. **Monitor the Issue**: Keep track of whether the author addresses the compatibility problems
2. **Re-test When Ready**: Once fixes are implemented, the PR can be converted back from draft and re-tested
3. **Coordinate Release**: Ensure the fixed version is properly tested before including it in the next BOM release

###### Communication

When performing rollbacks:

- Be clear and specific about the issues encountered
- Provide helpful details like failing tests or error messages  
- Reference specific versions that work vs. versions that fail
- Be respectful and collaborative - rollbacks are about maintaining stability, not blame

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
