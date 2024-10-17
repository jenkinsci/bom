#!/bin/bash

git checkout master
git pull
releaseName=$(gh release list --limit 1 --json isLatest,name --jq ".[].name")
issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number")
gh issue comment $issueNumber --body "New release: [https://github.com/jenkinsci/bom/releases/tag/$releaseName](https://github.com/jenkinsci/bom/releases/tag/$releaseName)"
