function new-pfaConnectionsWithPureOne {
    <#
    .SYNOPSIS
      Retrieves FlashArrays from Pure1 and creates a PowerShell connection to them.
    .DESCRIPTION
      Pulls all of the virtual IPs of the FlashArrays and identifies their FQDNs and then connects to them.
    .INPUTS
      Pure1 session and credentials.
    .OUTPUTS
      FlashArray endpoints.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  06/09/2019
      Purpose/Change: First release
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position=0,ValueFromPipeline=$True)]
        [System.Management.Automation.PSCredential]$credentials,

        [Parameter(Position=1)]
        [string]$pureOneToken
    )
    if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -eq ""))
    {
        throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
    }
    if ($null -eq $Global:pureOneRestHeader)
    {
        $Global:pureOneRestHeader = @{authorization="Bearer $($pureOnetoken)"}
    }
    $pureOneArrays = Get-PureOneArray -arrayProduct "Purity//FA"
    foreach ($pureOneArray in $pureOneArrays)
    {
        $arrayIP = (Get-PureOneArrayNetworking -virtualIP -arrayName $pureOneArray.name |Where-Object {$_.name -eq "vir0"}).address
        try {
            #try to find FQDN of Array VIP
            $arrayFqdn = ([System.Net.Dns]::GetHostByAddress(($arrayIP))).Hostname
        }
        catch {
            $arrayFqdn = $arrayIP
        }
        #Verify array can be connected to over port 443
        $arrayAlive = Test-NetConnection -ComputerName $arrayFqdn -Port 443 -InformationLevel "quiet"
        if ($arrayAlive -eq $True)
        {
            $arrayConnected = $false
            while ($arrayConnected -ne $True)
            {
                if ($null -eq $credentials)
                {
                    $credentials = Get-Credential -Message "Please enter valid FlashArray credentials for $($pureOneArray.name)"
                    if ($null -eq $credentials)
                    {
                        throw "Array registration canceled."
                    }
                }
                try {
                    new-pfaConnection -nonDefaultArray -endpoint $arrayFqdn -credentials $credentials -ignoreCertificateError |Out-Null
                    $arrayConnected = $True
                }
                catch 
                {
                    if ($Global:Error[0] -like "*invalid credentials*")
                    {
                        Write-Warning -Message "Bad credentials. Please enter valid credentials for $($pureOneArray.name)"
                        $credentials = $null
                    }
                }
            }
        }
        else {
            Write-Error -Message "FlashArray $($pureOneArray.name) could not be found on the network. Skipping this array."
        }
    }
}
function get-leastBusyPfaConnection {
    <#
    .SYNOPSIS
      Retrieves the FlashArray with the lowest busy meter over the specified time.
    .DESCRIPTION
      Returns the FlashArray connection that was the least busy in the overall specified time.
    .INPUTS
      FlashArray connections.
    .OUTPUTS
      FlashArray connection.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  06/09/2019
      Purpose/Change: First release
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Position=0,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray[]]$flasharray,

        [Parameter(Position=1)]
        [switch]$average,

        [Parameter(Position=2)]
        [switch]$maximum,

        [Parameter(Position=3)]
        [int16]$daysToSample,

        [Parameter(Position=4)]
        [Decimal]$maxCapacityFullAllowed,

        [Parameter(Position=5)]
        [Decimal]$maxCapacityFullPreferred,

        [Parameter(Position=6)]
        [string]$pureOneToken
    )
    if (($null -eq $Global:pureOneRestHeader) -and ($pureOneToken -eq ""))
    {
        throw "No access token found in the global variable or passed in. Run the cmdlet New-PureOneRestConnection to authenticate."
    }
    if ($null -eq $Global:pureOneRestHeader)
    {
        $Global:pureOneRestHeader = @{authorization="Bearer $($pureOnetoken)"}
    }
    if ($null -eq $flasharray)
    {
        $flasharray = $Global:AllFlashArrays 
    }
    if ($null -eq $flasharray)
    {
        throw "You must either pass in FlashArray connections or populate them with new-pfaConnectionsWithPureOne"
    }
    if (($maximum -eq $true) -and ($average -eq $true))
    {
        throw "Please only specify average or maximum as true."
    }
    if (($maximum -eq $false) -and ($average -eq $false))
    {
        $maximum = $True
    }
    if ($maxCapacityFullAllowed -eq 0)
    {
        $maxCapacityFullAllowed = .90
    }
    if (($maxCapacityFullAllowed -le 0) -or ($maxCapacityFullAllowed -ge 1))
    {
        throw "Please enter a percent full between 0 and 1 (entered value is $($maxCapacityFullAllowed))"
    }
    if ($maxCapacityFullPreferred -eq 0)
    {
        $maxCapacityFullPreferred = .75
    }
    if (($maxCapacityFullPreferred -le 0) -or ($maxCapacityFullPreferred -ge 1))
    {
        throw "Please enter a percent full between 0 and 1 (entered value is $($maxCapacityFullPreferred))"
    }
    if ($maxCapacityFullPreferred -gt $maxCapacityFullAllowed)
    {
        throw "The max capacity full must be lower than the max capacity allowed"
    }
    #set granularity to total interval, aka return one overall number for entire time period
    $metricDetails = Get-PureOneMetricDetail -metricName "array_total_load"
    $pureOneDaysToSampleAllowed = ($metricDetails.availabilities.retention / 1000 / 60 / 60 / 24)
    if ($daysToSample -eq 0)
    {
        $daysToSample = ($metricDetails.availabilities.retention / 1000 / 60 / 60 / 24)
    }
    elseif ($daysToSample -gt $pureOneDaysToSampleAllowed)
    {
        throw "Specified days to sample is too far in the past. Pure1 only supports up $($pureOneDaysToSampleAllowed)"
    }
    $granularity = $daysToSample * 24 * 60 * 60 * 1000
    $endTime = Get-Date
    $endTime = $endTime.ToUniversalTime()
    $startTime = $endTime.AddDays(-$daysToSample)
    $startTime = $startTime.ToUniversalTime()
    $arraySerial = @()
    foreach ($fa in $flasharray)
    {
        $arraySerial += (Get-PfaArrayAttributes -array $fa).id
    }
    $busyMeters = Get-PureOneArrayBusyMeter -objectId $arraySerial -average:$average -maximum:$maximum -startTime $startTime -endTime $endTime -granularity $granularity
    $leastBusyArray = $null
    $leastBusyCapacityArray = $null
    foreach ($busyMeter in $busyMeters)
    {
        $fa = get-pfaConnectionFromArrayId -arrayId $busyMeter.resources.id 
        $totalSpace = Get-PfaArraySpaceMetrics -Array $fa
        $percentCapacityFull = $totalSpace.total / $totalSpace.capacity
        if ($percentCapacityFull -gt $maxCapacityFullAllowed)
        {
            continue
        }
        elseif ($percentCapacityFull -lt $maxCapacityFullPreferred) 
        {
            if ($null -eq $leastBusyArray)
            {
                $leastBusyArray = $busyMeter
            }
            if ($leastBusyArray.data[0][1] -gt $busyMeter.data[0][1])
            {
                $leastBusyArray = $busyMeter
            }
        }
        elseif ($percentCapacityFull -gt $maxCapacityFullPreferred) 
        {
            if ($null -eq $leastBusyCapacityArray)
            {
                $leastBusyCapacityArray = $busyMeter
            }
            if ($leastBusyCapacityArray.data[0][1] -gt $busyMeter.data[0][1])
            {
                $leastBusyCapacityArray = $busyMeter
            }
        }
    }
    if ($null -ne $leastBusyArray)
    {
        return (get-pfaConnectionFromArrayId -arrayId $leastBusyArray.resources.id)
    }
    elseif ($null -ne $leastBusyCapacityArray)
    {
        return (get-pfaConnectionFromArrayId -arrayId $leastBusyCapacityArray.resources.id)
    }
}
