#!/bin/bash

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

gh workflow run cd.yaml --ref master --repo jenkinsci/bom
${HERE}/bom-release-issue-complete-task.sh 7
