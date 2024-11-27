# MetricFunctions.ps1

function Get-ResourceMetric {
    [CmdletBinding()]
    param (
        [Parameter()]
        [datetime]
        $StartDate,
        [Parameter()]
        [datetime]
        $EndDate,
        [Parameter()]
        $MetricDefinitions,
        [Parameter()]
        $Resources
    )
    # DONE: Migrate to use get-azmetricsbatch
    try {
        
    }
    catch {
        throw $error[0]
    }
    $LocationList = $Resources.Location | Select-Object -unique
    $ResourceMetricData = @()
    $ResMetrics = @()
    foreach ($loc in $LocationList) {
        $ResourcesByLocation = if ($null -eq $Resources.Location -or $Resources.Locatikon -eq "") { $Resources | Where-Object Region -eq $loc } else { $Resources | Where-Object Location -eq $loc }
        $endpoint = "https://$($loc.Replace(' ','').ToLower()).metrics.monitor.azure.com"
        $resourceBatches = [System.Collections.Generic.List[object]]::new()
        $batchSize = 50
        for ($i = 0; $i -lt $ResourcesByLocation.Count; $i += $batchSize) {
            $resourceBatches.Add($ResourcesByLocation[$i..([math]::Min($i + $batchSize - 1, $ResourcesByLocation.Count - 1))])
        }
        foreach ($resourceBatch in $resourceBatches) {
            $resourceBatchIds = if ($null -eq $resourceBatch.id -or $null -eq $resourceBatch[0].id) { $resourceBatch.ResourceId } else { $resourceBatch.Id }
            $ResMetrics += Get-AzMetricsBatch -Endpoint $endpoint -ResourceId $resourceBatchIds `
                -Name $MetricDefinitions.metrics -Namespace ($MetricDefinitions.provider | Select-Object -Unique) `
                -Interval PT12H -StartTime $StartDate.DateTime -EndTime $EndDate.DateTime -Aggregation "Average,Total"
        }
    }
    foreach ($res in $ResMetrics) {
        $DateList = $ResMetrics.Value.timesery.Data.TimeStamp | Select-Object -Unique
        foreach ($date in $DateList) {
            $ResourceId = if ($null -eq $res.ResourceId -or $res.Resourceid -eq "") { $res.Id } else { $res.ResourceId }
            $ResourceId -match '.*/([^/]+)' | Out-Null
            $resourceName = if ($null -ne $Matches) { $Matches[1] } else { $ResourceId }
            $metricData = [PSCustomObject]@{
                ResourceName = $resourceName
                DateTime     = $date.ToString("MMM dd, yyyy, h tt")
            }
            foreach ($metric in $res.Value) {
                $aggr = ($MetricDefinitions | Where-Object metrics -eq $metric.NameValue).aggregations
                $metricDataByDate = $metric.timesery.data | Where-Object TimeStamp -eq $date
                $metricData | Add-Member -Name $metric.NameValue -Type NoteProperty -Value $metricDataByDate.$aggr
            }
            $ResourceMetricData += $metricData
        }
    }
    return $ResourceMetricData | ConvertTo-Json
}

# $ed = Get-Date
# $sd = $ed.AddDays(-7)
# $re = Get-AzLogicApp
# $MetricList = Get-Content -Path ./MetricsToCollect.csv | ConvertFrom-Csv
# $me = $MetricList | Where-Object resourcetype -eq "LogicApp"
# Get-ResourceMetric -StartDate $sd -EndDate $ed -MetricDefinitions $me -Resources $re