#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/agent-activity-tests
xcrun swiftc boringNotch/models/ExternalNotifyEvent.swift \
    boringNotch/models/AgentActivityQueue.swift tests/AgentActivityQueueTests.swift \
    -o .build/agent-activity-tests/queue-tests
.build/agent-activity-tests/queue-tests
