# Incident Drill Schedule (ST-R-001)

## Purpose
Monthly incident drills ensure the team stays practiced in incident response, runbooks stay current, and gaps are identified before real incidents occur.

## Drill Cadence
| Month | Week | Scenario | Lead | Backup |
|-------|------|----------|------|--------|
| Jan   | 2    | Parser regression | TBD | TBD |
| Feb   | 2    | UI failure | TBD | TBD |
| Mar   | 2    | Routing backlog | TBD | TBD |
| Apr   | 2    | SharedCache refresh failure | TBD | TBD |
| May   | 2    | PortBatch missing | TBD | TBD |
| Jun   | 2    | Dispatcher throughput drop | TBD | TBD |
| Jul   | 2    | Parser regression | TBD | TBD |
| Aug   | 2    | UI failure | TBD | TBD |
| Sep   | 2    | Routing backlog | TBD | TBD |
| Oct   | 2    | Cache provider fallback | TBD | TBD |
| Nov   | 2    | BulkStage latency spike | TBD | TBD |
| Dec   | 2    | Rollback execution | TBD | TBD |

## Drill Scenarios

### 1. Parser Regression
**Trigger:** Simulated parser failure via corrupted fixture file.
**Runbook:** None (new scenario template).
**Success Criteria:**
- Identify the failure within 5 minutes
- Locate the offending host/log within 10 minutes
- Rollback or fix applied within 15 minutes
- Telemetry bundle captured for evidence

### 2. UI Failure
**Trigger:** Simulated WPF crash or frozen UI via mock.
**Runbook:** None (new scenario template).
**Success Criteria:**
- Identify UI failure from telemetry within 5 minutes
- Capture diagnostic logs within 10 minutes
- Restart or recover UI within 10 minutes

### 3. Routing Backlog
**Trigger:** Artificially delay dispatcher queue.
**Runbook:** [INC0001 Routing Queue Delay](Incident_INC0001_RoutingQueueDelay.md)
**Success Criteria:**
- Identify queue delay spike in QueueDelaySummary within 5 minutes
- Run Analyze-DispatcherGaps and correlate gap within 10 minutes
- Document findings within 15 minutes

### 4. SharedCache Refresh Failure
**Trigger:** Simulate cache miss storm.
**Runbook:** [INC0002 SharedCache Refresh](Incident_INC0002_SharedCacheRefresh.md)
**Success Criteria:**
- Identify AccessRefresh spike in telemetry within 5 minutes
- Run shared-cache diagnostics within 10 minutes
- Determine root cause within 15 minutes

### 5. PortBatch Missing
**Trigger:** Suppress PortBatchReady events.
**Runbook:** [INC0003 PortBatch Missing](Incident_INC0003_PortBatchMissing.md)
**Success Criteria:**
- Identify missing events within 5 minutes
- Run synthesis/recovery within 10 minutes

### 6. Dispatcher Throughput Drop
**Trigger:** Throttle dispatcher via settings.
**Runbook:** [INC0006 Dispatcher Throughput Drop](Incident_INC0006_DispatcherThroughputDrop.md)
**Success Criteria:**
- Identify throughput drop in telemetry within 5 minutes
- Correlate with scheduler metrics within 10 minutes

### 7. Rollback Execution
**Trigger:** Practice full rollback workflow.
**Runbook:** [PlanR Rollback Bundle](../plans/PlanR_IncidentResponse.md)
**Success Criteria:**
- Create rollback bundle within 5 minutes
- Verify bundle contents within 5 minutes
- Practice restore/verification steps

## Drill Execution

### Pre-Drill Checklist
- [ ] Confirm drill lead and backup availability
- [ ] Ensure test environment is ready (fixtures, logs reset)
- [ ] Review relevant runbook before drill
- [ ] Start timing from drill announcement

### During Drill
1. Lead announces drill scenario start (capture start time)
2. Participant(s) follow runbook to identify and respond
3. Observer captures timing milestones
4. Lead calls drill complete when success criteria met

### Post-Drill
1. Run `Tools\Invoke-IncidentDrill.ps1 -RecordResults` to capture outcomes
2. Review gaps in runbook or tooling
3. Update runbook with lessons learned
4. File drill results under `Logs/Drills/<date>_<scenario>.json`

## Drill Result Template
```json
{
  "DrillId": "DRILL-2026-01-001",
  "Scenario": "Parser regression",
  "DrillDate": "2026-01-14T10:00:00Z",
  "Lead": "TBD",
  "Participants": [],
  "TimingsMins": {
    "IdentifyIssue": 0,
    "LocateRootCause": 0,
    "ApplyFix": 0,
    "VerifyRecovery": 0
  },
  "TotalDurationMins": 0,
  "SuccessCriteriaMet": true,
  "GapsIdentified": [],
  "RunbookUpdatesNeeded": [],
  "Notes": ""
}
```

## Metrics
Track these metrics across drills:
- Mean time to identify (MTTI)
- Mean time to resolve (MTTR)
- Runbook coverage (scenarios with runbooks vs. without)
- Gap closure rate (identified gaps fixed by next drill)

## References
- [Plan R - Incident Response](../plans/PlanR_IncidentResponse.md)
- [Rollback Bundle Script](../../Tools/New-RollbackBundle.ps1)
- [Incident Postmortem Intake](../StateTrace_IncidentPostmortem_Intake.md)
