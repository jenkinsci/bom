#!/bin/bash

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

${HERE}/bom-release-issue-complete-task.sh 2
${HERE}/bom-get-branch-protection.sh
