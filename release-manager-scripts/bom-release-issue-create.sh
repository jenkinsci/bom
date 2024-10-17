#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Error: This script requires exactly two arguments."
    echo "./bom-release-issue-create.sh <yyyy-MM-dd> <GitHub id>"
    exit 1
fi

git checkout master
git pull
releaseManager=$2
bodyValue=$(cat <<-EOM
A new release is being scheduled.
Release manager: @$2

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
  -f "assignees[]=$2" \
  --jq ".number")
echo $issueNumber
gh issue pin $issueNumber