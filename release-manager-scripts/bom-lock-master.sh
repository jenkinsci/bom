#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Error: This script requires exactly one argument."
	echo "./bom-lock-master.sh <GitHub issue id>"
	exit 1
fi

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

updatedBody=$(gh issue view $1 --json body --jq ".body" | sed 's/\[\ \] Lock/[x] Lock/')
gh issue edit $1 --body $updatedBody
./bom-get-branch-protection.sh
