#!/bin/bash

if [[ $# -ne 2 ]]; then
	echo "Error: This script requires exactly one argument."
	echo "./bom-release-issue-job-running.sh <Jenkins build number>"
	exit 1
fi

git checkout master
git pull
issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number")
updatedBody=$(gh issue view $issueNumber --json body --jq ".body" | sed 's/\[\ \] Trigger/[x] Trigger/' | sed "s/BUILDNUMBER/$1/")
gh issue edit $issueNumber --body $updatedBody
