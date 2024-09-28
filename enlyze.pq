[Version = "1.0.0"]
section enlyze;

BaseUrl = "https://app.enlyze.com/api/v2";

CommonHeaders = [
    #"Content-Type" = "application/json",
    #"user-agent" = "enlyze-powerbi/1.0.0"
];

ProductivityMetricsTableSchema = type table [
    start = datetimezone,
    end = datetimezone,
    machine = text,
    availability_score = nullable number,
    availability_time_loss = nullable number,
    performance_score = nullable number,
    performance_time_loss = nullable number,
    quality_score = nullable number,
    quality_time_loss = nullable number,
    productivity_score = nullable number,
    productivity_time_loss = nullable number,
    quantity_scrap_value = nullable number,
    quantity_scrap_unit = nullable text,
    quantity_yield_value = nullable number,
    quantity_yield_unit = nullable text
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

ToIso8601 = (dt as datetimezone) as text => DateTimeZone.ToText(dt, [Format = "O", Culture = "en-US"]);

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
            hourStarts, (hourStart) => [
                start = ToIso8601(hourStart),
                end = ToIso8601(addOneHour(hourStart))
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
                start = ToIso8601(dayStart),
                end = ToIso8601(addDay(dayStart))
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
            weekStarts, (weekStart) => [
                start = ToIso8601(weekStart),
                end = ToIso8601(endOfWeek(weekStart))
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
                    start = ToIso8601(monthStart),
                    end = ToIso8601(if end <= startOfNextMonth(monthStart) then end else startOfNextMonth(monthStart))
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
        dateTimeRanges =
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
        _ = Diagnostics.Trace(TraceLevel.Error, "Generated Date Ranges:", Text.From(dateTimeRanges)),
        accumulated = List.Accumulate(
            machineUuids,
            #table(ProductivityMetricsTableSchema, {}),
            (state, machineUuid) =>
                let
                    responseData = PostRequest(
                        "/machines/" & machineUuid & "/productivity-metrics", [datetime_ranges = dateTimeRanges]
                    ),
                    responseDataWithMachine = List.Transform(
                        responseData, (r) => Record.AddField(r, "machine", machineUuid)
                    )
                in
                    Table.Combine({state, TransformProductivityMetrics(responseDataWithMachine)})
        )
    in
        accumulated;

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
        expandedQuantityYield = ExpandQuantityYield(expandedQuantityScrap),
        localizedTable = Table.TransformColumns(
            expandedQuantityYield,
            {
                {"start", each DateTimeZone.ToLocal(DateTimeZone.From(_))},
                {"end", each DateTimeZone.ToLocal(DateTimeZone.From(_))}
            }
        )
    in
        Table.ChangeType(localizedTable, ProductivityMetricsTableSchema);

// table should be an actual Table.Type, or a List.Type of Records
Table.ChangeType = (table, tableType as type) as nullable table =>
    // we only operate on table types
    if (not Type.Is(tableType, type table)) then
        error "type argument should be a table type"
    else
    // if we have a null value, just return it
    if (table = null) then
        table
    else
        let
            columnsForType = Type.RecordFields(Type.TableRow(tableType)),
            columnsAsTable = Record.ToTable(columnsForType),
            schema = Table.ExpandRecordColumn(columnsAsTable, "Value", {"Type"}, {"Type"}),
            previousMeta = Value.Metadata(tableType),
            // make sure we have a table
            parameterType = Value.Type(table),
            _table =
                if (Type.Is(parameterType, type table)) then
                    table
                else if (Type.Is(parameterType, type list)) then
                    let
                        asTable = Table.FromList(table, Splitter.SplitByNothing(), {"Column1"}),
                        firstValueType = Value.Type(Table.FirstValue(asTable, null)),
                        result =
                        // if the member is a record (as expected), then expand it.
                        if (Type.Is(firstValueType, type record)) then
                            Table.ExpandRecordColumn(asTable, "Column1", schema[Name])
                        else
                            error
                                Error.Record(
                                    "Error.Parameter",
                                    "table argument is a list, but not a list of records",
                                    [
                                        ValueType = firstValueType
                                    ]
                                )
                    in
                        if (List.IsEmpty(table)) then
                            #table({"a"}, {})
                        else
                            result
                else
                    error
                        Error.Record(
                            "Error.Parameter",
                            "table argument should be a table or list of records",
                            [
                                ValueType = parameterType
                            ]
                        ),
            reordered = Table.SelectColumns(_table, schema[Name], MissingField.UseNull),
            // process primitive values - this calls Table.TransformColumnTypes
            map = (t) =>
                if Type.Is(t, type table) or Type.Is(t, type list) or Type.Is(t, type record) or t = type any then
                    null
                else
                    t,
            mapped = Table.TransformColumns(schema, {"Type", map}),
            omitted = Table.SelectRows(mapped, each [Type] <> null),
            existingColumns = Table.ColumnNames(reordered),
            removeMissing = Table.SelectRows(omitted, each List.Contains(existingColumns, [Name])),
            primativeTransforms = Table.ToRows(removeMissing),
            changedPrimatives = Table.TransformColumnTypes(reordered, primativeTransforms),
            // Get the list of transforms we use for Record types
            recordColumns = Table.SelectRows(schema, each Type.Is([Type], type record)),
            recordTypeTransformations = Table.AddColumn(
                recordColumns, "RecordTransformations", each (r) => Record.ChangeType(r, [Type]), type function
            ),
            recordChanges = Table.ToRows(
                Table.SelectColumns(recordTypeTransformations, {"Name", "RecordTransformations"})
            ),
            // Get the list of transforms we use for List types
            listColumns = Table.SelectRows(schema, each Type.Is([Type], type list)),
            listTransforms = Table.AddColumn(
                listColumns, "ListTransformations", each (t) => List.ChangeType(t, [Type]), Function.Type
            ),
            listChanges = Table.ToRows(Table.SelectColumns(listTransforms, {"Name", "ListTransformations"})),
            // Get the list of transforms we use for Table types
            tableColumns = Table.SelectRows(schema, each Type.Is([Type], type table)),
            tableTransforms = Table.AddColumn(
                tableColumns, "TableTransformations", each (t) => @Table.ChangeType(t, [Type]), Function.Type
            ),
            tableChanges = Table.ToRows(Table.SelectColumns(tableTransforms, {"Name", "TableTransformations"})),
            // Perform all of our transformations
            allColumnTransforms = recordChanges & listChanges & tableChanges,
            changedRecordTypes =
                if (List.IsEmpty(allColumnTransforms)) then
                    changedPrimatives
                else
                    Table.TransformColumns(changedPrimatives, allColumnTransforms, null, MissingField.Ignore),
            // set final type
            withType = Value.ReplaceType(changedRecordTypes, tableType)
        in
            if (List.IsEmpty(Record.FieldNames(columnsForType))) then
                table
            else
                withType meta previousMeta;

// If given a generic record type (no predefined fields), the original record is returned
Record.ChangeType = (record as record, recordType as type) =>
    let
        // record field format is [ fieldName = [ Type = type, Optional = logical], ... ]
        fields =
            try
                Type.RecordFields(recordType)
            otherwise
                error "Record.ChangeType: failed to get record fields. Is this a record type?",
        fieldNames = Record.FieldNames(fields),
        fieldTable = Record.ToTable(fields),
        optionalFields = Table.SelectRows(fieldTable, each[Value][Optional])[Name],
        requiredFields = List.Difference(fieldNames, optionalFields),
        // make sure all required fields exist
        withRequired = Record.SelectFields(record, requiredFields, MissingField.UseNull),
        // append optional fields
        withOptional = withRequired & Record.SelectFields(record, optionalFields, MissingField.Ignore),
        // set types
        transforms = GetTransformsForType(recordType),
        withTypes = Record.TransformFields(withOptional, transforms, MissingField.Ignore),
        // order the same as the record type
        reorder = Record.ReorderFields(withTypes, fieldNames, MissingField.Ignore)
    in
        if (List.IsEmpty(fieldNames)) then
            record
        else
            reorder;

List.ChangeType = (list as list, listType as type) =>
    if (not Type.Is(listType, type list)) then
        error "type argument should be a list type"
    else
        let
            listItemType = Type.ListItem(listType),
            transform = GetTransformByType(listItemType),
            modifiedValues = List.Transform(list, transform),
            typed = Value.ReplaceType(modifiedValues, listType)
        in
            typed;

// Returns a table type for the provided schema table
Schema.ToTableType = (schema as table) as type =>
    let
        toList = List.Transform(schema[Type], (t) => [Type = t, Optional = false]),
        toRecord = Record.FromList(toList, schema[Name]),
        toType = Type.ForRecord(toRecord, false),
        previousMeta = Value.Metadata(schema)
    in
        type table (toType) meta previousMeta;

// Returns a list of transformations that can be passed to Table.TransformColumns, or Record.TransformFields
// Format: {"Column", (f) => ...} .... ex: {"A", Number.From}
GetTransformsForType = (_type as type) as list =>
    let
        fieldsOrColumns =
            if (Type.Is(_type, type record)) then
                Type.RecordFields(_type)
            else if (Type.Is(_type, type table)) then
                Type.RecordFields(Type.TableRow(_type))
            else
                error "GetTransformsForType: record or table type expected",
        toTable = Record.ToTable(fieldsOrColumns),
        transformColumn = Table.AddColumn(
            toTable, "Transform", each GetTransformByType([Value][Type]), Function.Type
        ),
        transformMap = Table.ToRows(Table.SelectColumns(transformColumn, {"Name", "Transform"}))
    in
        transformMap;

GetTransformByType = (_type as type) as function =>
    if (Type.Is(_type, type number)) then
        Number.From
    else if (Type.Is(_type, type text)) then
        Text.From
    else if (Type.Is(_type, type date)) then
        Date.From
    else if (Type.Is(_type, type datetime)) then
        DateTime.From
    else if (Type.Is(_type, type duration)) then
        Duration.From
    else if (Type.Is(_type, type datetimezone)) then
        DateTimeZone.From
    else if (Type.Is(_type, type logical)) then
        Logical.From
    else if (Type.Is(_type, type time)) then
        Time.From
    else if (Type.Is(_type, type record)) then
        (t) => if (t <> null) then @Record.ChangeType(t, _type) else t
    else if (Type.Is(_type, type table)) then
        (t) => if (t <> null) then @Table.ChangeType(t, _type) else t
    else if (Type.Is(_type, type list)) then
        (t) => if (t <> null) then @List.ChangeType(t, _type) else t
    else
        (t) => t;
