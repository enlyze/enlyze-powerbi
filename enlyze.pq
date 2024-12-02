[Version = "1.0.0"]
section enlyze;

loadModule = (fileName as text) =>
    let
        binary = Extension.Contents(fileName), asText = Text.FromBinary(binary)
    in
        try
            Expression.Evaluate(asText, #shared) catch (e) =>
                error
                    [
                        Reason = "loadModule Failure",
                        Message.Format = "Loading '#{0}' failed - '#{1}': '#{2}'",
                        Message.Parameters = {fileName, e[Reason], e[Message]},
                        Detail = [File = fileName, Error = e]
                    ];

Table.ToNavigationTable = loadModule("Table.ToNavigationTable.pqm");

FetchPaginated = loadModule("ApiClient.pqm")[FetchPaginated];
PaginatedPostRequest = loadModule("ApiClient.pqm")[PaginatedPostRequest];

TransformProductivityMetrics = loadModule("ProductivityMetrics.Transform.pqm")[TransformProductivityMetrics];
TransformProductionRuns = loadModule("ProductionRuns.Transform.pqm")[TransformProductionRuns];
TransformSites = loadModule("Sites.Transform.pqm")[TransformSites];
TransformMachines = loadModule("Machines.Transform.pqm")[TransformMachines];
TransformProducts = loadModule("Products.Transform.pqm")[TransformProducts];
TransformDowntimes = loadModule("Downtimes.Transform.pqm")[TransformDowntimes];
TransformTimeseriesData = loadModule("TimeseriesData.Transform.pqm")[TransformTimeseriesData];
TransformVariables = loadModule("Variables.Transform.pqm")[TransformVariables];

MachineProductivityMetrics = loadModule("MachineProductivityMetrics.pqm");
TimeseriesData = loadModule("TimeseriesData.pqm");

[DataSource.Kind = "enlyze", Publish = "enlyze.Publish"]
shared enlyze.Contents = () =>
    let
        NavTable = Table.ToNavigationTable(
            #table(
                {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
                {
                    {
                        "Downtimes",
                        "downtimes",
                        TransformDowntimes(FetchPaginated("/downtimes", null)),
                        "Table",
                        "Table",
                        true
                    },
                    {
                        "Production Runs",
                        "productionRuns",
                        TransformProductionRuns(FetchPaginated("/production-runs", null)),
                        "Table",
                        "Table",
                        true
                    },
                    {
                        "Machines",
                        "machines",
                        TransformMachines(FetchPaginated("/machines", null)),
                        "Table",
                        "Table",
                        true
                    },
                    {"Sites", "sites", TransformSites(FetchPaginated("/sites", null)), "Table", "Table", true},
                    {
                        "Products",
                        "products",
                        TransformProducts(FetchPaginated("/products", null)),
                        "Table",
                        "Table",
                        true
                    },
                    {
                        "Machine Productivity Metrics",
                        "machineProductivityMetrics",
                        MachineProductivityMetrics,
                        "Function",
                        "Function",
                        true
                    },
                    {
                        "Variables",
                        "variables",
                        TransformVariables(FetchPaginated("/variables", null)),
                        "Table",
                        "Table",
                        true
                    },
                    {"Timeseries", "Timeseries", TimeseriesData, "Function", "Function", true}
                }
            ),
            {"Key"},
            "Name",
            "Data",
            "ItemKind",
            "ItemName",
            "IsLeaf"
        )
    in
        NavTable;

shared enlyze.ConnectionTest = () => enlyze.Contents(){[Key = "sites"]}[Data];

enlyze = [
    Authentication = [
        Key = [
            Label = "ENLYZE API Key",
            KeyLabel = "ENLYZE API Key"
        ]
    ],
    Label = "ENLYZE",
    TestConnection = (dataSourcePath) => {"enlyze.ConnectionTest"}
];

enlyze.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = {Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp")},
    LearnMoreUrl = "https://docs.enlyze.com/platform/power-bi",
    SourceImage = enlyze.Icons,
    SourceTypeImage = enlyze.Icons
];

enlyze.Icons = [
    Icon16 = {
        Extension.Contents("ENLYZE16.png"),
        Extension.Contents("ENLYZE20.png"),
        Extension.Contents("ENLYZE24.png"),
        Extension.Contents("ENLYZE32.png")
    },
    Icon32 = {
        Extension.Contents("ENLYZE32.png"),
        Extension.Contents("ENLYZE40.png"),
        Extension.Contents("ENLYZE48.png"),
        Extension.Contents("ENLYZE64.png")
    }
];
