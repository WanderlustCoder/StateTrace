<!-- LANDMARK: ST-D-003 dispatcher gaps fixtures - incremental loading sample -->
# Incremental Loading Samples

This folder contains minimal JSON fixtures used by Analyze-DispatcherGaps tests.

PortBatchIntervalsSample.json is a trimmed interval report with only the fields
consumed by the analyzer: StartTimeUtc, EndTimeUtc, GapSeconds, GapMinutes,
StartHost, EndHost. It pairs with the queue summary fixture in
Data/Samples/TelemetryBundles/Sample-ReleaseBundle/Routing/QueueDelaySummary-20250101.json.
