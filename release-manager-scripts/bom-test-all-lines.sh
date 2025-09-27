#!/bin/bash

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
	echo "Error: This script requires exactly one argument."
	echo "./bom-test-all-lines.sh <comma separated list of plugins>"
	exit 1
fi

${HERE}/bom-line-test.sh weekly $1
${HERE}/bom-line-test.sh 2.528.x $1
${HERE}/bom-line-test.sh 2.516.x $1
${HERE}/bom-line-test.sh 2.504.x $1
