#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Error: This script requires exactly one argument."
	echo "./bom-release-issue-add-release-comment.sh <GitHub issue id>"
	exit 1
fi

git checkout master
git pull
releaseName=$(gh release list --limit 1 --json isLatest,name --jq ".[].name")
gh issue comment $1 --body "New release: [https://github.com/jenkinsci/bom/releases/tag/$releaseName](https://github.com/jenkinsci/bom/releases/tag/$releaseName)"
