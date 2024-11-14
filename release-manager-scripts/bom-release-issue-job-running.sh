#!/bin/bash

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
	echo "Error: This script requires exactly one argument."
	echo "./bom-release-issue-job-running.sh <Jenkins build number>"
	exit 1
fi

issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number" --repo jenkinsci/bom)
gh issue comment $issueNumber --body "[https://ci.jenkins.io/job/Tools/job/bom/job/master/$1/](https://ci.jenkins.io/job/Tools/job/bom/job/master/$1/)"  --repo jenkinsci/bom
${HERE}/bom-release-issue-complete-task.sh 3
${HERE}/bom-release-issue-complete-task.sh 4
