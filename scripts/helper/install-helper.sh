#!/bin/sh
# SPDX-License-Identifier: MIT
# Installs the fan helper as a system service. The app runs this as root after macOS asks for approval.
set -eu

LABEL=io.github.rupajsen.notchutils.fanhelper
RESOURCES=$(cd "$(dirname "$0")" && pwd)
HELPER=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist

launchctl bootout "system/$LABEL" 2>/dev/null || true

install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
install -o root -g wheel -m 755 "$RESOURCES/../MacOS/NotchUtilsFanHelper" "$HELPER"
install -o root -g wheel -m 644 "$RESOURCES/$LABEL.plist" "$PLIST"

launchctl bootstrap system "$PLIST"
