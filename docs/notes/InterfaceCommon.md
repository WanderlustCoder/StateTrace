# InterfaceCommon Helper Module

- Location: Modules/InterfaceCommon.psm1
- Exports: Get-StringPropertyValue, Set-PortRowDefaults (hostname/isSelected defaults), Get-PortSortFallbackKey.
- Consumers: InterfaceModule, DeviceRepositoryModule, CompareViewModule, DeviceInsightsModule, ViewStateService, FilterStateModule, ParserPersistenceModule.
- Usage: import the module (it auto-imports where present) and call helpers instead of duplicating PSObject property checks or port sort fallback literals.
- Notes: Keep using approved verbs via Set-PortRowDefaults for external callers; Ensure-PortRowDefaults is internal.

