[Version = "1.0.0"]
section enlyze;

BaseUrl = "https://app.enlyze.com/api/v2";

CommonHeaders = [
    #"Content-Type" = "application/json",
    #"user-agent" = "enlyze-powerbi/1.0.0"
];

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

Table.ToNavigationTable = (
    tbl as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(tbl),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta [
            NavigationTable.NameColumn = nameColumn,
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn,
            Preview.DelayColumn = itemNameColumn,
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(tbl, newTableType)
    in
        navigationTable;

CreateHeaders = (apiToken as text) as record =>
    Record.Combine({CommonHeaders, [#"Authorization" = "Bearer " & apiToken]});

FetchPage = (apiPath as text, cursor as nullable text) =>
    let
        apiUrl = BaseUrl & apiPath,
        apiToken = Extension.CurrentCredential()[Key],
        url = if cursor = null then apiUrl else apiUrl & "?cursor=" & cursor,
        headers = CreateHeaders(apiToken),
        parsedResponse = Json.Document(Web.Contents(url, [Headers = headers]))
    in
        parsedResponse;

FetchPaginated = (apiPath as text, cursor as nullable text) as list =>
    let
        currentPage = FetchPage(apiPath, cursor),
        nextCursor = currentPage[metadata][next_cursor],
        data = currentPage[data],
        remainingData = if nextCursor = null then {} else @FetchPaginated(apiPath, nextCursor)
    in
        List.Combine({data, remainingData});

ToHourlyDateTimeRanges = (start as datetime, end as datetime, resolution as text) as list =>
    let
        roundToHour = (dt as datetime) =>
            DateTime.FromText(
                Text.From(Date.From(dt)) & " " & Text.PadStart(Text.From(Time.Hour(dt)), 2, "0") & ":00:00"
            ),
        durationOneHour = #duration(0, 1, 0, 0),
        roundedStart = roundToHour(start),
        hourStarts = List.Generate(() => roundedStart, each _ <= end, each _ + durationOneHour),
        ranges = List.Transform(
            hourStarts,
            (hourStart) =>
                [
                    start = hourStart,
                    end = if hourStart + durationOneHour > end then end else hourStart + #duration(0, 0, 59, 59)
                ]
        )
    in
        ranges;

ToDailyDateTimeRanges = (start as datetime, end as datetime) as list =>
    let
        roundToDay = (dt as datetime) => DateTime.FromText(Text.From(Date.From(dt)) & " 00:00:00"),
        endOfDay = (dt as datetime) => dt + #duration(0, 23, 59, 59),
        dayStarts = List.Generate(() => roundToDay(start), each _ <= Date.From(end), each Date.AddDays(_, 1)),
        ranges = List.Transform(
            dayStarts,
            (dayStart) =>
                [
                    start = dayStart,
                    end = if Date.From(dayStart) = Date.From(end) then end else endOfDay(dayStart)
                ]
        )
    in
        ranges;

ToWeeklyDateTimeRanges = (start as datetime, end as datetime) as list =>
    let
        // Function to round down to the start of the week (Monday 00:00:00)
        roundToWeekStart = (dt as datetime) =>
            let
                dayOfWeek = Date.DayOfWeek(Date.From(dt), Day.Monday) + 1,
                mondayOfWeek = Date.From(dt) - #duration(dayOfWeek - 1, 0, 0, 0)
            in
                DateTime.FromText(Text.From(mondayOfWeek) & " 00:00:00"),
        // Function to get the end of the week (Sunday 23:59:59)
        endOfWeek = (dt as datetime) => roundToWeekStart(dt) + #duration(6, 23, 59, 59),
        weekStarts = List.Generate(() => roundToWeekStart(start), each _ <= end, each _ + #duration(7, 0, 0, 0)),
        ranges = List.Transform(
            weekStarts,
            (weekStart) =>
                [
                    start = weekStart,
                    end = if Date.From(endOfWeek(weekStart)) >= Date.From(end) then end else endOfWeek(weekStart)
                ]
        )
    in
        ranges;

ToMonthlyDateTimeRanges = (start as datetime, end as datetime) as list =>
    let
        roundToMonthStart = (dt as datetime) => DateTime.FromText(Text.From(Date.StartOfMonth(dt)) & " 00:00:00"),
        endOfMonth = (dt as datetime) => DateTime.FromText(Text.From(Date.EndOfMonth(dt)) & " 23:59:59"),
        monthStarts = List.Generate(() => roundToMonthStart(start), each _ <= end, each Date.AddMonths(_, 1)),
        ranges = List.Transform(
            monthStarts,
            (monthStart) =>
                [
                    start = monthStart,
                    end = if Date.From(endOfMonth(monthStart)) >= Date.From(end) then end else endOfMonth(monthStart)
                ]
        )
    in
        ranges;

MachineProductivityMetrics = (machines as table, start as datetime, end as datetime, resolution as text) as table =>
    let
        machineUuids = Table.Column(machines, "uuid"),
        validResolutions = {"hourly", "daily", "weekly", "monthly"},
        validatedResolution =
            if List.Contains(validResolutions, resolution) then
                resolution
            else
                error "Invalid resolution. Please choose 'hourly', 'daily', 'weekly', or 'monthly'.",
        dateRanges =
            if validatedResolution = "hourly" then
                ToHourlyDateTimeRanges(start, end, resolution)
            else if validatedResolution = "daily" then
                ToDailyDateTimeRanges(start, end)
            else if validatedResolution = "weekly" then
                ToWeeklyDateTimeRanges(start, end)
            else if validatedResolution = "monthly" then
                ToMonthlyDateTimeRanges(start, end)
            else
                error "Invalid resolution. Please choose 'hourly', 'daily', 'weekly', or 'monthly'.",
        _ = Diagnostics.Trace(TraceLevel.Error, "Generated Date Ranges:", Text.From(dateRanges)),
        emptyTable = #table(
            type table [
                start = datetime,
                end = datetime,
                machine = text,
                availability_score = number,
                availability_time_loss = number,
                performance_score = number,
                performance_time_loss = number,
                quality_score = number,
                quality_time_loss = number,
                productivity_score = number,
                productivity_time_loss = number
            ],
            {}
        )
    in
        emptyTable;

TransformMachines = (machines as list) as table =>
    let
        machinesTable = Table.FromList(machines, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        namedTable = Value.ReplaceMetadata(machinesTable, Value.Metadata(machinesTable) & [Name = "Machines"]),
        expandedTable = Table.ExpandRecordColumn(namedTable, "Column1", {"name", "uuid", "site", "genesis_date"}),
        machinesWithMetrics = Table.AddColumn(
            expandedTable,
            "Productivity Metrics",
            (row) =>
                (start as datetime, end as datetime, resolution as text) =>
                    MachineProductivityMetrics({row}, start, end, resolution)
        )
    in
        machinesWithMetrics;

TransformSites = (sites as list) as table =>
    let
        sitesTable = Table.FromList(sites, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        namedTable = Value.ReplaceMetadata(sitesTable, Value.Metadata(sitesTable) & [Name = "Sites"]),
        expandedTable = Table.ExpandRecordColumn(namedTable, "Column1", {"uuid", "name", "address"})
    in
        expandedTable;

TransformProductionRuns = (productionRuns as list) as table =>
    let
        productionRunsTable = Table.FromList(
            productionRuns, Splitter.SplitByNothing(), null, null, ExtraValues.Error
        ),
        namedTable = Value.ReplaceMetadata(
            productionRunsTable, Value.Metadata(productionRunsTable) & [Name = "Production Runs"]
        ),
        expandedTable = Table.ExpandRecordColumn(
            namedTable,
            "Column1",
            {
                "uuid",
                "machine",
                "production_order",
                "product",
                "start",
                "end",
                "average_throughput",
                "quantity_total",
                "quantity_scrap",
                "quantity_yield",
                "availability",
                "performance",
                "quality",
                "productivity",
                "maximum_run_speed",
                "data_quality"
            }
        ),
        expandedAvailability = Table.ExpandRecordColumn(
            expandedTable, "availability", {"score", "time_loss"}, {"availability_score", "availability_time_loss"}
        ),
        expandedPerformance = Table.ExpandRecordColumn(
            expandedAvailability, "performance", {"score", "time_loss"}, {
                "performance_score",
                "performance_time_loss"
            }
        ),
        expandedProductivity = Table.ExpandRecordColumn(
            expandedPerformance,
            "productivity",
            {"score", "time_loss"},
            {"productivity_score", "productivity_time_loss"}
        ),
        expandedQuality = Table.ExpandRecordColumn(
            expandedProductivity, "quality", {"score", "time_loss"}, {"quality_score", "quality_time_loss"}
        ),
        expandedDataQuality = Table.ExpandRecordColumn(
            expandedQuality, "data_quality", {"data_coverage", "overlap_percentage", "overlap_time"}
        ),
        expandedMaxRunSpeed = Table.ExpandRecordColumn(
            expandedDataQuality,
            "maximum_run_speed",
            {"value", "observation_period_start", "observation_period_end", "unit"},
            {"max_run_speed_value", "max_run_speed_start", "max_run_speed_end", "max_run_speed_unit"}
        ),
        expandedQuantityTotal = Table.ExpandRecordColumn(
            expandedMaxRunSpeed, "quantity_total", {"unit", "value"}, {"quantity_total_unit", "quantity_total_value"}
        ),
        expandedQuantityScrap = Table.ExpandRecordColumn(
            expandedQuantityTotal, "quantity_scrap", {"unit", "value"}, {
                "quantity_scrap_unit",
                "quantity_scrap_value"
            }
        ),
        expandedQuantityYield = Table.ExpandRecordColumn(
            expandedQuantityScrap, "quantity_yield", {"unit", "value"}, {
                "quantity_yield_unit",
                "quantity_yield_value"
            }
        )
    in
        expandedQuantityYield;

TransformDowntimes = (downtimes as list) as table =>
    let
        downtimesTable = Table.FromList(downtimes, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        namedTable = Value.ReplaceMetadata(downtimesTable, Value.Metadata(downtimesTable) & [Name = "Downtimes"]),
        expandedTable = Table.ExpandRecordColumn(
            namedTable, "Column1", {"uuid", "machine", "comment", "type", "updated", "reason", "start", "end"}
        ),
        expandedUpdated = Table.ExpandRecordColumn(
            expandedTable,
            "updated",
            {"first_name", "last_name", "timestamp"},
            {"updated_first_name", "updated_last_name", "updated_timestamp"}
        ),
        expandedReason = Table.ExpandRecordColumn(
            expandedUpdated, "reason", {"uuid", "name", "category"}, {
                "reason_uuid",
                "reason_name",
                "reason_category"
            }
        )
    in
        expandedReason;
