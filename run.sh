#!/bin/sh
# Cron wrapper: load config, then run the collector.
# Adjust the path if you install somewhere other than /opt/cti.
. /opt/cti/cti.env
exec /opt/cti/cti.sh "$@"
