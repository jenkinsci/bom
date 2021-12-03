#!/bin/bash

set -eux -o pipefail

# Script "weekly-apply.sh"
# The script checks the current weekly version in the sample plugin
# - if different than $1 and DRY_RUN is set to:
#   - "false" then it updates it with the value of $1
#   - "true" then it only reports the value of $1
# - otherwise it exits without any value reported

# if the parent pom is already built no need to rebuild the whole project (faster build time)
existing_version=$(awk -F "[><]" '/jenkins.version/{print $3;exit}' ./sample-plugin/pom.xml)

if test "$1" == "$(echo "${existing_version}")"
then
  ## No change
  # early return with no output
  exit 0
else
  if test "$DRY_RUN" == "false"
  then
    ## Value changed to $1" - NO dry run
    sed -i -e "17s#<jenkins.version>[0-9]\+.[0-9]\+</jenkins.version>#<jenkins.version>$1</jenkins.version>#" ./sample-plugin/pom.xml
  fi
  # Report on stdout
  echo "$1"
  exit 0
fi
