#!/bin/bash

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

releaseName=$(gh release list --limit 1 --json isLatest,name --jq ".[] | select (.isLatest == true) | .name" --exclude-drafts --exclude-pre-releases --repo jenkinsci/bom)
issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number" --repo jenkinsci/bom)
gh issue comment $issueNumber --body "New release: [https://github.com/jenkinsci/bom/releases/tag/$releaseName](https://github.com/jenkinsci/bom/releases/tag/$releaseName)"  --repo jenkinsci/bom
${HERE}/bom-release-issue-complete-task.sh 9