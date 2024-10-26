#!/bin/bash

gh workflow run cd.yaml --ref master --repo jenkinsci/bom
./bom-release-issue-complete-task.sh 6