@{
    # List of module filenames to import at startup.  The order of the modules
    Modules = @(
        'ThemeModule.psm1',
        # Core parser and helper modules
        'ParserWorker.psm1',
        'DatabaseModule.psm1',
        'DeviceRepositoryModule.psm1',
        'DeviceCatalogModule.psm1',
        'FilterStateModule.psm1',
        'DeviceDetailsModule.psm1',
        'DeviceInsightsModule.psm1',
        'DeviceDataModule.psm1',
        # Vendor-specific modules
        'AristaModule.psm1',
        'BrocadeModule.psm1',
        'CiscoModule.psm1',
        # Interface and view modules
        'InterfaceModule.psm1',
        'SpanViewModule.psm1',
        'SearchInterfacesViewModule.psm1',
        'SummaryViewModule.psm1',
        'TemplatesViewModule.psm1',
        'AlertsViewModule.psm1',
        'CompareViewModule.psm1',
        'TemplatesModule.psm1'
    )
}

