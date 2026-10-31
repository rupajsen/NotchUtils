#!/bin/sh
# SPDX-License-Identifier: MIT
# Removes the fan helper. Stopping it returns the fans to automatic.
set -u

LABEL=io.github.rupajsen.notchutils.fanhelper

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL"
rm -f "/var/run/$LABEL.sock"
