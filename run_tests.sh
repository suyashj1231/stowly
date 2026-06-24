#!/bin/bash
# Regression test suite for Stowly. Run before shipping UI/logic changes so
# previously-fixed bugs (URL handling, sort labels, folder icons) don't creep back.
set -e
echo "Running Stowly tests…"
swift test "$@"
