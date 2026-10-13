#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/agent-activity-tests
xcrun swiftc boringNotch/models/ExternalNotifyEvent.swift \
    boringNotch/models/AgentActivityQueue.swift boringNotch/managers/ExternalNotifyServer.swift \
    tests/ExternalNotifyServerTests.swift -o .build/agent-activity-tests/server-tests
.build/agent-activity-tests/server-tests
