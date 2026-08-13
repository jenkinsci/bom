#!/usr/bin/env bash

# Sourced by prep.sh, prep-megawar.sh and pct.sh; sets $INCREMENTALS_PROFILE.
#
# Consuming incremental dependencies is opt-in per pull request: either commit a
# file named `consume-incrementals` to the repository root or add the
# `consume-incrementals` label (which the Jenkinsfile turns into
# CONSUME_INCREMENTALS=true). Otherwise the profile inherited from the parent POM
# is explicitly deactivated, so that incremental versions cannot be resolved by
# accident and must be switched to formal releases before merge.

if [[ -f "$(dirname "${BASH_SOURCE[0]}")/consume-incrementals" || ${CONSUME_INCREMENTALS-} == true ]]; then
	INCREMENTALS_PROFILE=-Pconsume-incrementals
else
	INCREMENTALS_PROFILE=-P-consume-incrementals
fi
