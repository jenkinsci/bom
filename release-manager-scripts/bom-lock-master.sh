#!/bin/bash

git checkout master
git pull
gh api \
	/repos/jenkinsci/bom/branches/master/protection \
	--method PUT \
	--header "Accept: application/vnd.github+json" \
	--header "X-GitHub-Api-Version: 2022-11-28" \
	-F "lock_branch=true" \
	-F "enforce_admins=false" \
	-F "required_pull_request_reviews=null" \
	-F "required_status_checks[strict]=false" \
	-f "required_status_checks[contexts][]=Jenkins" \
	-F "restrictions=null" \
	--silent

issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number")

updatedBody=$(gh issue view $issueNumber --json body --jq ".body" | sed 's/\[\ \] Lock/[x] Lock/')
gh issue edit $issueNumber --body $updatedBody
./bom-get-branch-protection.sh
