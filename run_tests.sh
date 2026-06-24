#!/bin/bash
# Regression test suite for ReelPlanner. Run before shipping UI/logic changes so
# previously-fixed bugs (URL handling, sort labels, folder icons) don't creep back.
set -e
echo "Running ReelPlanner tests…"
swift test "$@"
