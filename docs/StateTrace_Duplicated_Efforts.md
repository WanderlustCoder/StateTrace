**Scope**
- Quick inventory of duplicated implementations across Modules/, with references noted as path:line.

**Template Loading**
- Modules/DeviceLogParserModule.psm1:493 re-implements vendor template JSON parsing already handled by Modules/TemplatesModule.psm1:266, maintaining a second cache and separate file resolution.
- Divergent caches risk drift when templates change; consider exposing TemplatesModule\Get-ConfigurationTemplateData to parser workers instead of bespoke caching.

**Debug Switch Guards**
- Modules/DatabaseModule.psm1:12, Modules/DeviceLogParserModule.psm1:4, Modules/ParserWorker.psm1:3, Modules/CompareViewModule.psm1:24 each define fallback initialization for $Global:StateTraceDebug.
- Consolidating this guard (for example in TelemetryModule or a shared prelude) would avoid duplicated strict-mode scaffolding and reduce future maintenance.

**Span Debug Logging**
- Modules/DeviceRepositoryModule.psm1:1062 and Modules/SpanViewModule.psm1:45 both create Logs\\Debug directories and append SpanDebug.log entries with near-identical formatting.
- Extracting a shared Span logging helper would eliminate redundant directory checks and keep telemetry formatting consistent.

**Db Result Normalization**
- Modules/DeviceDetailsModule.psm1:77, Modules/DeviceRepositoryModule.psm1:441, Modules/InterfaceModule.psm1:200, Modules/TemplatesModule.psm1:242 repeat the same pattern to coerce Invoke-DbQuery output between DataTable instances and generic enumerables.
- A DatabaseModule utility (for example ConvertTo-RowList) could collapse the boilerplate and enforce consistent null handling.

**ViewStateService Bootstrap**
- Modules/DeviceInsightsModule.psm1:6 and Modules/InterfaceModule.psm1:6 contain near-identical logic to probe for ViewStateService.psm1 and import it globally when missing.
- Providing a single helper (perhaps ViewStateService\Ensure-Loaded) would prevent UI modules from duplicating this import and error handling code.

**Concurrency Heuristics**
- Modules/ParserWorker.psm1:54 (Get-AutoScaleConcurrencyProfile) and Modules/ParserRunspaceModule.psm1:208 (Get-AdaptiveThreadBudget) both derive thread ceilings and job batching limits from device queues.
- Unifying the heuristics inside a shared scheduler service would simplify tuning and keep autoscale behaviour consistent between worker discovery and runspace orchestration.
