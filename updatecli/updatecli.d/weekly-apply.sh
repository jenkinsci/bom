#!/bin/bash

set -eux -o pipefail

# Script "weekly-apply.sh"
# The script checks the current weekly version in the sample plugin
# - if different than $1 and DRY_RUN is set to:
#   - "false" then it updates it with the value of $1
#   - "true" then it only reports the value of $1
# - otherwise it exits without any value reported
existing_version=$(mvn help:evaluate -f sample-plugin -Dexpression=jenkins.version -q -DforceStdout)

if test "$1" == "$(echo "${existing_version}")"
then
  ## No change
  # early return with no output
  exit 0
else
  if test "$DRY_RUN" == "false"
  then
    ## Value changed to $1" - NO dry run
    mvn versions:set-property -DgenerateBackupPoms=false -Dproperty=jenkins.version -DnewVersion="$1"
  fi
  # Report on stdout
  echo "$1"
  exit 0
fi
