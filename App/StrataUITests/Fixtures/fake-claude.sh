#!/bin/sh
# Stands in for `claude` in FixFlowTests. It ships in the test bundle and the test links it into the fixture home:
# the sandboxed test runner quarantines files it writes itself, and macOS won't run a quarantined script.
# $0 is the link, so calls.txt lands next to it in the fixture.
echo "$(pwd -P) $*" > "$(dirname "$0")/calls.txt"
echo "Successfully uninstalled plugin: kit (scope: user)"
