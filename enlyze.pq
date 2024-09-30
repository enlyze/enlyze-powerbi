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

// API Client helpers
FetchPaginated = loadModule("ApiClient.pqm")[FetchPaginated];

// API Response Conversion
Transformers = loadModule("Transforms.pqm");
TransformSites = Transformers[TransformSites];
TransformMachines = Transformers[TransformMachines];
TransformDowntimes = Transformers[TransformDowntimes];
TransformProductionRuns = Transformers[TransformProductionRuns];
TransformProductivityMetrics = Transformers[TransformProductivityMetrics];
TransformProducts = Transformers[TransformProducts];

MachineProductivityMetrics = loadModule("MachineProductivityMetrics.pqm");

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
                    }
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

enlyze = [
    Authentication = [
        Key = [
            Label = "ENLYZE API Token",
            KeyLabel = "ENLYZE API TOKEN"
        ]
    ],
    Label = "ENLYZE"
];

enlyze.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = {Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp")},
    LearnMoreUrl = "https://docs.enlyze.com/",
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
