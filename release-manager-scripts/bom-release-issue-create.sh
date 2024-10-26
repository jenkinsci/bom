#!/bin/bash

if [[ $# -ne 1 ]]; then
	echo "Error: This script requires exactly one argument."
	echo "./bom-release-issue-create.sh <yyyy-MM-dd>"
	exit 1
fi

releaseManager=$(gh api user -q .login)
bodyValue=$(
	cat <<-EOM
		A new release is being scheduled.
		Release manager: @$releaseManager

		# Release progress
		* [ ] 1. run \`./bom-lock-master.sh\` before the job runs
		  * currently, the job is [scheduled to run at 11:HH am UTC (actual 11:26am)](https://github.com/jenkinsci/bom/blob/master/Jenkinsfile#L4)
		* [ ] 2. wait to verify that job started at [ci.jenkins.io](https://ci.jenkins.io/job/Tools/job/bom/job/master/)			
		* [ ] 3. run \`./bom-release-issue-job-running.sh <buildNumber>\`
		  * Example: \`./bom-release-issue-job-running.sh 1234\`
		* [ ] 4. wait for build to make it through the \`prep\` stage then (typically) take a 1.5-2 hr break
		* [ ] 5. (LOOP) if there are any failures, fix until everything is successful
		* [ ] 6. run \`./bom-run-cd-workflow.sh\`
		  * wait for the release process to complete
		  * this takes 7-8 minutes
		* [ ] 7. manually edit the auto-generated release notes
		  * remove \`<!-- Optional: add a release summary here -->\`
		  * remove \`<details>\`
		  * remove \`<summary>XYZ changes</summary>\`
		  * remove \`</details>\`
		* [ ] 8. run \`./bom-release-issue-add-release-comment.sh\`
		* [ ] 9. run \`./bom-unlock-master.sh\`
		* [ ] 10. verify that the [branch is unlocked](https://github.com/jenkinsci/bom/settings/branch_protection_rules/6421306)
		* [ ] 11. run \`./bom-release-issue-close.sh\`
	EOM
)
issueNumber=$(gh api \
	--method POST \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	/repos/jenkinsci/bom/issues \
	-f "title=[RELEASE] New release for $1" \
	-f "body=$bodyValue" \
	-f "assignees[]=$releaseManager" \
	--jq ".number")
echo $issueNumber
gh issue edit $issueNumber --add-label "release" --repo jenkinsci/bom
gh issue pin $issueNumber --repo jenkinsci/bom
