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

PostRequest = (apiPath as text, body as any) as list =>
    let
        url = BaseUrl & apiPath,
        apiToken = Extension.CurrentCredential()[Key],
        headers = CreateHeaders(apiToken),
        response = Web.Contents(
            url,
            [
                Headers = headers,
                Content = Json.FromValue(body),
                ManualStatusHandling = {400, 401, 403, 404, 422, 500}
            ]
        ),
        statusCode = Value.Metadata(response)[Response.Status],
        parsedResponse =
            if statusCode = 200 then
                Json.Document(response)
            else
                error "HTTP Error: " & Text.From(statusCode) & ". Response body: " & Text.FromBinary(response),
        data = parsedResponse[data]
    in
        data;

ToIso8601WithTZ = (dt as datetimezone) as text => DateTimeZone.ToText(dt, [Format = "O", Culture = "en-US"]);

ToHourlyDateTimeRanges = (start as datetimezone, end as datetimezone, resolution as text) as list =>
    let
        roundToHour = (dt as datetimezone) =>
            #datetimezone(
                Date.Year(dt),
                Date.Month(dt),
                Date.Day(dt),
                Time.Hour(dt),
                0,
                0,
                DateTimeZone.ZoneHours(dt),
                DateTimeZone.ZoneMinutes(dt)
            ),
        durationOneHour = #duration(0, 1, 0, 0),
        addOneHour = (dt as datetimezone) => DateTimeZone.From(dt + durationOneHour),
        roundedStart = roundToHour(start),
        hourStarts = List.Generate(() => roundedStart, each _ <= end, each addOneHour(_)),
        ranges = List.Transform(
            hourStarts,
            (hourStart) => [
                start = ToIso8601WithTZ(hourStart),
                end = ToIso8601WithTZ(addOneHour(hourStart))
            ]
        )
    in
        ranges;

ToDailyDateTimeRanges = (start as datetimezone, end as datetimezone) as list =>
    let
        roundToDay = (dt as datetimezone) =>
            #datetimezone(
                Date.Year(dt),
                Date.Month(dt),
                Date.Day(dt),
                0,
                0,
                0,
                DateTimeZone.ZoneHours(dt),
                DateTimeZone.ZoneMinutes(dt)
            ),
        addDay = (dt as datetimezone) => DateTimeZone.From(Date.AddDays(dt, 1)),
        dayStarts = List.Generate(() => roundToDay(start), each Date.From(_) <= Date.From(end), each addDay(_)),
        ranges = List.Transform(
            dayStarts, (dayStart) => [
                start = ToIso8601WithTZ(dayStart),
                end = ToIso8601WithTZ(addDay(dayStart))
            ]
        )
    in
        ranges;

ToWeeklyDateTimeRanges = (start as datetimezone, end as datetimezone) as list =>
    let
        roundToWeekStart = (dt as datetimezone) =>
            let
                dayOfWeek = Date.DayOfWeek(Date.From(dt), Day.Monday) + 1,
                mondayOfWeek = Date.AddDays(Date.From(dt), - (dayOfWeek - 1))
            in
                #datetimezone(
                    Date.Year(mondayOfWeek),
                    Date.Month(mondayOfWeek),
                    Date.Day(mondayOfWeek),
                    0,
                    0,
                    0,
                    DateTimeZone.ZoneHours(dt),
                    DateTimeZone.ZoneMinutes(dt)
                ),
        endOfWeek = (dt as datetimezone) =>
            let
                nextMonday = roundToWeekStart(dt) + #duration(7, 0, 0, 0)
            in
                #datetimezone(
                    Date.Year(nextMonday),
                    Date.Month(nextMonday),
                    Date.Day(nextMonday),
                    0,
                    0,
                    0,
                    DateTimeZone.ZoneHours(dt),
                    DateTimeZone.ZoneMinutes(dt)
                ),
        weekStarts = List.Generate(
            () => roundToWeekStart(start), each _ <= end, each DateTimeZone.From(Date.AddDays(_, 7))
        ),
        ranges = List.Transform(
            weekStarts,
            (weekStart) => [
                start = ToIso8601WithTZ(weekStart),
                end = ToIso8601WithTZ(endOfWeek(weekStart))
            ]
        )
    in
        ranges;

ToMonthlyDateTimeRanges = (start as datetimezone, end as datetimezone) as list =>
    let
        roundToMonthStart = (dt as datetimezone) =>
            #datetimezone(
                Date.Year(dt), Date.Month(dt), 1, 0, 0, 0, DateTimeZone.ZoneHours(dt), DateTimeZone.ZoneMinutes(dt)
            ),
        startOfNextMonth = (dt as datetimezone) =>
            let
                nextMonth = Date.AddMonths(Date.From(dt), 1)
            in
                #datetimezone(
                    Date.Year(nextMonth),
                    Date.Month(nextMonth),
                    1,
                    0,
                    0,
                    0,
                    DateTimeZone.ZoneHours(dt),
                    DateTimeZone.ZoneMinutes(dt)
                ),
        monthStarts = List.Generate(
            () => roundToMonthStart(start), each _ <= end, each DateTimeZone.From(Date.AddMonths(_, 1))
        ),
        ranges = List.Transform(
            monthStarts,
            (monthStart) =>
                [
                    start = ToIso8601WithTZ(monthStart),
                    end = ToIso8601WithTZ(
                        if end <= startOfNextMonth(monthStart) then end else startOfNextMonth(monthStart)
                    )
                ]
        )
    in
        ranges;

MachineProductivityMetrics = (machines as table, start as datetimezone, end as datetimezone, resolution as text) as table =>
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

ExpandMetric = (tbl as table, fieldName as text) as table =>
    Table.ExpandRecordColumn(tbl, fieldName, {"score", "time_loss"}, {fieldName & "_score", fieldName & "_time_loss"});

ExpandQuantity = (tbl as table, fieldName as text) as table =>
    Table.ExpandRecordColumn(tbl, fieldName, {"unit", "value"}, {fieldName & "_unit", fieldName & "_value"});

ExpandAvailability = (tbl as table) as table => ExpandMetric(tbl, "availability");

ExpandPerformance = (tbl as table) as table => ExpandMetric(tbl, "performance");

ExpandQuality = (tbl as table) as table => ExpandMetric(tbl, "quality");

ExpandProductivity = (tbl as table) as table => ExpandMetric(tbl, "productivity");

ExpandQuantityScrap = (tbl as table) as table => ExpandQuantity(tbl, "quantity_scrap");

ExpandQuantityYield = (tbl as table) as table => ExpandQuantity(tbl, "quantity_yield");

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
        expandedAvailability = ExpandAvailability(expandedTable),
        expandedPerformance = ExpandPerformance(expandedAvailability),
        expandedQuality = ExpandQuality(expandedPerformance),
        expandedProductivity = ExpandProductivity(expandedQuality),
        expandedQuantityScrap = ExpandQuantityScrap(expandedProductivity),
        expandedQuantityYield = ExpandQuantityYield(expandedQuantityScrap),
        expandedQuantityTotal = Table.ExpandRecordColumn(
            expandedQuantityYield, "quantity_total", {"unit", "value"}, {
                "quantity_total_unit",
                "quantity_total_value"
            }
        ),
        expandedDataQuality = Table.ExpandRecordColumn(
            expandedQuantityTotal, "data_quality", {"data_coverage", "overlap_percentage", "overlap_time"}
        ),
        expandedMaxRunSpeed = Table.ExpandRecordColumn(
            expandedDataQuality,
            "maximum_run_speed",
            {"value", "observation_period_start", "observation_period_end", "unit"},
            {"max_run_speed_value", "max_run_speed_start", "max_run_speed_end", "max_run_speed_unit"}
        )
    in
        expandedMaxRunSpeed;

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

TransformProductivityMetrics = (productivityMetrics as list) as table =>
    let
        productivityMetricsTable = Table.FromList(
            productivityMetrics, Splitter.SplitByNothing(), null, null, ExtraValues.Error
        ),
        namedTable = Value.ReplaceMetadata(
            productivityMetricsTable, Value.Metadata(productivityMetricsTable) & [Name = "Productivity Metrics"]
        ),
        expandedTable = Table.ExpandRecordColumn(
            namedTable,
            "Column1",
            {
                "start",
                "end",
                "machine",
                "availability",
                "performance",
                "quality",
                "productivity",
                "quantity_scrap",
                "quantity_yield"
            }
        ),
        expandedAvailability = ExpandAvailability(expandedTable),
        expandedPerformance = ExpandPerformance(expandedAvailability),
        expandedQuality = ExpandQuality(expandedPerformance),
        expandedProductivity = ExpandProductivity(expandedQuality),
        expandedQuantityScrap = ExpandQuantityScrap(expandedProductivity),
        expandedQuantityYield = ExpandQuantityYield(expandedQuantityScrap)
    in
        expandedQuantityYield;
