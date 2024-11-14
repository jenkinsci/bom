#!/bin/bash

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

${HERE}/bom-release-issue-complete-task.sh 12
issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number" --repo jenkinsci/bom)
gh issue unpin $issueNumber --repo jenkinsci/bom
gh issue close $issueNumber --repo jenkinsci/bom
