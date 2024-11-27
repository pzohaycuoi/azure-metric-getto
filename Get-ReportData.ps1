[CmdletBinding()]
param (
    [Parameter()]
    [datetime]
    $EndDate = (Get-Date),
    [Parameter()]
    [datetime]
    $StartDate = ($EndDate.AddDays(-7))
)

$MetricList = Get-Content -Path ./MetricsToCollect.csv | ConvertFrom-Csv  #TODO: maybe add class for datamodel?
$JobMapping = @{
    Vm            = "./result/VmMetrics.csv"
    FunctionApp   = "./result/FunctionAppMetrics.csv"
    LogicApp      = "./result/LogicAppMetrics.csv"
    MySQL         = "./result/MySQL.csv"
    AzureSQL      = "./result/AzureSQL.csv"
    AKS           = "./result/AKS.csv"
    AzureFirewall = "./result/AzureFirewall.csv"
}
$RgList = Get-AzResourceGroup

# VM
$VMs = $RgList | ForEach-Object -ThrottleLimit 5 -Parallel {
    Get-AzVM -ResourceGroupName $_.ResourceGroupName
}
$MetricDefinitions = $MetricList | Where-Object resourcetype -eq "VM"
Start-Job -Name "GetMetric-VM" -InitializationScript { . ./Get-ResourceMetric.ps1 } -ScriptBlock {
    Get-ResourceMetric -StartDate $using:StartDate -EndDate $using:EndDate `
        -MetricDefinitions $using:MetricDefinitions -Resources $using:VMs 
}

$FuncApps = Get-AzFunctionApp
$MetricDefinitions = $MetricList | Where-Object resourcetype -eq "FunctionApp"
Start-Job -Name "GetMetric-FunctionApp" -InitializationScript { . ./Get-ResourceMetric.ps1 } -ScriptBlock { 
    Get-ResourceMetric -StartDate $using:StartDate -EndDate $using:EndDate `
        -MetricDefinitions $using:MetricDefinitions -Resources $using:FuncApps 
}

# # Logic App
$LogicApps = Get-AzLogicApp
$MetricDefinitions = $MetricList | Where-Object resourcetype -eq "LogicApp"
. .\Get-ResourceMetric.ps1
Get-ResourceMetric -StartDate $StartDate -EndDate $EndDate -MetricDefinitions $MetricDefinitions -Resources $LogicApps | ConvertFrom-Json | Export-Csv $JobMapping.LogicApp
# Start-Job -Name "GetMetric-LogicApp" -InitializationScript { . .\Get-ResourceMetric.ps1 } -ScriptBlock {
#     Get-ResourceMetric -StartDate $using:StartDate -EndDate $using:EndDate `
#         -MetricDefinitions $using:MetricDefinitions -Resources $using:LogicApps -
# } -Debug #TODO: DONT FKIN KNOW WHY JOB THROW FREAKIN EXCEPTION FKIN SHIT DRIVING ME CRAZY


# MySQL
$MySQLs = Get-AzMySqlFlexibleServer
$MetricDefinitions = $MetricList | Where-Object resourcetype -eq "MySQL"
Start-Job -Name "GetMetric-MySQL" -InitializationScript { . ./Get-ResourceMetric.ps1 } -ScriptBlock {
    Get-ResourceMetric -StartDate $using:StartDate -EndDate $using:EndDate `
        -MetricDefinitions $using:MetricDefinitions -Resources $using:MySQLs 
}

# AzureSQLe
$AzureSQLServerList = Get-AzSqlServer
$AzureSQLs = $AzureSQLServerList | ForEach-Object -ThrottleLimit 5 -Parallel {
    Get-AzSqlDatabase -ServerName $_.ServerName -ResourceGroupName $_.ResourceGroupName
}
$MetricDefinitions = $MetricList | Where-Object resourcetype -eq "AzureSQL"
Start-Job -Name "GetMetric-AzureSQL" -InitializationScript { . ./Get-ResourceMetric.ps1 } -ScriptBlock {
    Get-ResourceMetric -StartDate $using:StartDate -EndDate $using:EndDate `
        -MetricDefinitions $using:MetricDefinitions -Resources $using:AzureSQLs 
}

# AKS
$AKSs = Get-AzAksCluster
$MetricDefinitions = $MetricList | Where-Object resourcetype -eq "AKS"
Start-Job -Name "GetMetric-AKS" -InitializationScript { . ./Get-ResourceMetric.ps1 } -ScriptBlock {
    Get-ResourceMetric -StartDate $using:StartDate -EndDate $using:EndDate `
        -MetricDefinitions $using:MetricDefinitions -Resources $using:AKSs 
}

# AzureFirewall
$AzureFirewalls = Get-AzFirewall
$MetricDefinitions = $MetricList | Where-Object resourcetype -eq "AzureFirewall"
Start-Job -Name "GetMetric-AzureFirewall" -InitializationScript { . ./Get-ResourceMetric.ps1 } -ScriptBlock {
    Get-ResourceMetric -StartDate $using:StartDate -EndDate $using:EndDate `
        -MetricDefinitions $using:MetricDefinitions -Resources $using:AzureFirewalls 
}

# Export report
$timeout = New-TimeSpan -Seconds 100
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
while ($stopwatch.elapsed -lt $timeout) {
    $Jobs = Get-job -name "GetMetric-*" 
    foreach ($job in ($Jobs | Where-Object State -eq "Completed")) {
        Receive-Job -Job $job | ConvertFrom-Json | Export-Csv ($JobMapping.($job.name.Replace("GetMetric-", "")))
        Remove-Job $job
    }
    $Jobs | Where-Object State -eq "Failed" | Receive-Job -AutoRemoveJob -Wait
    if ((Get-job -name "GetMetric-*").count -eq 0) {
        break
    }
    Start-Sleep -Seconds 5
}