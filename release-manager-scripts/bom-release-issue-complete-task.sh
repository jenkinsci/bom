#!/bin/bash
if [[ $# -ne 1 ]]; then
	echo "Error: This script requires exactly one argument."
	echo "./bom-release-issue-complete-task.sh <task number>"
	exit 1
fi

taskNumber=$1
issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number" --repo jenkinsci/bom)
updatedBody=$(gh issue view $issueNumber --json body --jq ".body" --repo jenkinsci/bom | sed "s/\[\ \] $taskNumber\./[x] $taskNumber./")
gh issue edit $issueNumber --body "$updatedBody"  --repo jenkinsci/bom