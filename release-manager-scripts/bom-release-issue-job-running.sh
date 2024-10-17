#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Error: This script requires exactly two arguments."
    echo "./bom-release-issue-job-running.sh <GitHub issue id> <Jenkins build number>"
    exit 1
fi

git checkout master
git pull
updatedBody=$(gh issue view $1 --json body --jq ".body" | sed 's/\[\ \] Trigger/[x] Trigger/' | sed "s/BUILDNUMBER/$2/")
gh issue edit $1 --body $updatedBody