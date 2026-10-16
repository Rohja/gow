#!/usr/bin/env bash
source /smoke-common/lib.sh

assert_has umu-run bwrap
assert_shared_ok /usr/bin/bwrap
assert_path /opt/gow/startup-app.sh /var/umu /game

smoke_report
