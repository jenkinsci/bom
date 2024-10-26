#!/bin/bash

./bom-release-issue-complete-task.sh 11
issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number" --repo jenkinsci/bom)
gh issue unpin $issueNumber --repo jenkinsci/bom
gh issue close $issueNumber --repo jenkinsci/bom
