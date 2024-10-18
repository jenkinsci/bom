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
		- [ ] Lock primary branch
		- [ ] Trigger [Jenkins build](https://ci.jenkins.io/job/Tools/job/bom/job/master/BUILDNUMBER/)
		- [ ] Unlock primary branch
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
gh issue edit $issueNumber --add-label "release"
gh issue pin $issueNumber
