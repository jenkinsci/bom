#!/bin/bash

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 2 ]]; then
	echo "Error: This script requires exactly two arguments."
	echo "./bom-line-test.sh <LINE> <comma separated list of plugins>"
	exit 1
fi

LINE=$1 PLUGINS=$2 TEST=InjectedTest bash ${HERE}/../local-test.sh
