#!/bin/bash

issueNumber=$(gh issue list --limit 1 --state open --label release --json number --jq=".[].number")
gh issue unpin $issueNumber
gh issue close $issueNumber
