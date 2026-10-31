#!/bin/zsh
# SPDX-License-Identifier: MIT
# Runs the fan controller against simulated Macs. Touches no real hardware and needs no root.
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release FanControllerChecks
