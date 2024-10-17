#!/bin/bash
git checkout master
git pull
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/jenkinsci/bom/branches/master/protection \
  --jq ".lock_branch"
