let
    navTable = enlyze.Contents(),
    machines = navTable{[Key="machines"]}[Data],
    downtimes = navTable{[Key="downtimes"]}[Data],

    start = #datetimezone(2024, 1, 1, 0, 0, 0, 0, 0), 
    end = #datetimezone(2024, 1, 7, 0, 0, 0, 0, 0),
    resolution = "daily",

    productivityMetrics = navTable{[Key="machineProductivityMetrics"]}[Data](
        machines, 
        start, 
        end, 
        resolution
    )
in
    downtimes
