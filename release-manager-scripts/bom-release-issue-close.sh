#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Error: This script requires exactly one argument."
    echo "./bom-release-issue-close.sh <GitHub issue id>
    exit 1
fi

git checkout master
git pull
gh issue unpin $1
gh issue close $1