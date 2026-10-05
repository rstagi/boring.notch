#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/agent-activity-tests
xcrun swiftc BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift \
    BoringNotchXPCHelper/BoringNotchXPCHelper.swift tests/ExternalNotificationActionsTests.swift \
    -o .build/agent-activity-tests/action-tests
.build/agent-activity-tests/action-tests
