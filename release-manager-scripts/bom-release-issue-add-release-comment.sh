#!/bin/bash

releaseName=$(gh release list --limit 1 --json isLatest,name --jq ".[] | select (.isLatest == true) | .name" --exclude-drafts --exclude-pre-releases)
issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number")
gh issue comment $issueNumber --body "New release: [https://github.com/jenkinsci/bom/releases/tag/$releaseName](https://github.com/jenkinsci/bom/releases/tag/$releaseName)"
