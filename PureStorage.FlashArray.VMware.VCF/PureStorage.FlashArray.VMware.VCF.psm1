function Initialize-PfaVcfWorkloadDomain {
  <#
  .SYNOPSIS
    Configures a workload domain for Pure Storage
  .DESCRIPTION
    Connects to each ESXi host, configures initiators on the FlashArray and provisions a VMFS. If something fails it will cleanup any changes.
  .INPUTS
    FQDNs or IPs of each host, valid credentials, a FlashArray connection, a datastore name and size.
  .OUTPUTS
    Returns host group.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/24/2020
    Purpose/Change: Core support
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -ignoreCertificateError -defaultArray
    PS C:\ $creds = get-credential
    PS C:\ Initialize-PfaVcfWorkloadDomain -esxiHosts "esxi-02.purecloud.com","esxi-04.purecloud.com" -credentials $creds -datastoreName "vcftest" -sizeInTB 16 -fc
    
    Creates a host group and hosts and provisions a 16 TB VMFS to the hosts over FC
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -ignoreCertificateError -defaultArray
    PS C:\ $creds = get-credential
    PS C:\ $allHosts = @()
    PS C:\ Import-Csv C:\hostList.csv | ForEach-Object {$allHosts += $_.hostnames} 
    PS C:\ Initialize-PfaVcfWorkloadDomain -esxiHosts $allHosts -credentials $creds -datastoreName "vcftest" -sizeInTB 16 -fc
    
    Creates a host group and hosts and provisions a 16 TB VMFS to the hosts over FC. This takes in a csv file of ESXi host FQDNs with one csv header called hostnames
  
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

      [Parameter(Position=0,mandatory=$true)]
      [string[]]$EsxiHostFqdn,

      [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
      [System.Management.Automation.PSCredential]$EsxiHostCredential,

      [Parameter(Position=3,mandatory=$true,ParameterSetName='VMFS')]
      [string]$DatastoreName,

      [Parameter(Position=4,ParameterSetName='VMFS')]
      [int]$SizeInGB,

      [Parameter(Position=5,ParameterSetName='VMFS')]
      [int]$SizeInTB,

      [Parameter(Position=6)]
      [ValidateSet('iSCSI','FC')]
      [string]$Protocol,

      [Parameter(Position=7,mandatory=$true,ParameterSetName='vVol')]
      [switch]$Vvol,

      [Parameter(Position=8,mandatory=$True)]
      [string]$FlashArrayFqdn,

      [Parameter(Position=9,mandatory=$true)]
      [System.Management.Automation.PSCredential]$FlashArrayCredential,

      [Parameter(Position=10,mandatory=$true)]
      [string]$VcfNetworkPool
    
  )
  if ($psversiontable.PSEdition -ne "Core")
  {
    throw "The cmdlet Initialize-PfaVcfWorkloadDomain is only supported with PowerShell Core (7.x or later)."
  }
  Write-Progress -id 1 -Activity "VCF and Pure ESXi Host Commission Process" -Status "Verifying input" -PercentComplete 5
  $vcfpools = Get-VCFNetworkPool
  if (($vcfpools.name -contains $VcfNetworkPool) -ne $true)
  {
    throw "Invalid VCF network pool ($($vcfnetworkpool)). Please verify network pools with Get-VCFNetworkPool"
  }
  Write-Debug -Message ($vcfpools| out-string)
  $ErrorActionPreference = "stop"
  if ($Vvol -ne $true)
  {
    if (($sizeInGB -eq 0) -and ($sizeInTB -eq 0))
    {
        throw "Please enter a size in GB or TB"
    }
    elseif (($sizeInGB -ne 0) -and ($sizeInTB -ne 0)) {
        throw "Please only enter a size in TB or GB, not both."
    }
    elseif ($sizeInGB -ne 0) {
        $volSize = $sizeInGB * 1024 *1024 *1024   
    }
    else {
        $volSize = $sizeInTB * 1024 *1024 *1024 * 1024
    }
  }
  Write-Progress -id 1 -Activity "VCF and Pure ESXi Host Commission Process" -Status "Connecting to Resources" -PercentComplete 10
  Write-Progress -parentid 1 -Id 2 -Activity "Connecting to FlashArray" -Status "Connecting to $($FlashArrayFqdn)" -PercentComplete 50
  $flasharray = New-PfaArray -EndPoint $FlashArrayFqdn -Credentials $FlashArrayCredential -IgnoreCertificateError
  $foundProtocol = checkFaProtocol -flasharray $flasharray -protocol $Protocol -ErrorAction stop
  Write-Progress -parentid 1 -Id 2 -Activity "Connecting to FlashArray" -Status "Connected to $($FlashArrayFqdn)" -PercentComplete 100
  $esxiConnections = @()
  for ($i =0;$i -lt $EsxiHostFqdn.count;$i++)
  {
    Write-Progress -parentid 1 -Id 2 -Activity "Connecting to ESXi hosts" -Status "Connecting to $($EsxiHostFqdn[$i])" -PercentComplete ($i/$EsxiHostFqdn.count)
    $esxiConnections += connect-viserver -Server $EsxiHostFqdn[$i] -Credential ($EsxiHostCredential) -ErrorAction Stop
  }
  Write-Progress -parentid 1 -Id 2 -Activity "Connecting to ESXi hosts" -Status "Connected to $($EsxiHostFqdn.Count) ESXi hosts" -PercentComplete 100
  $faHosts = @()
  Write-Progress -id 1 -Activity "VCF and Pure ESXi Host Commission Process" -Status "Configuring storage connection for ESXi hosts" -PercentComplete 30
  for ($i =0;$i -lt $esxiConnections.count;$i++)
  {
    Write-Progress -parentid 1 -Id 2 -Activity "Configuring ESXi hosts on FlashArray" -Status "Configuring $($esxiConnections[$i].name)" -PercentComplete ($i/$esxiConnections.count)
    $foundHost = $null
    $foundHost = Get-PfaHostFromVmHost -esxi (get-vmhost $esxiConnections[$i].name) -Flasharray $flasharray -ErrorAction SilentlyContinue
    if ($null -ne $foundHost)
    {
      if ($null -ne $foundHost.hgroup)
      {
        throw "The host $($esxiConnections[$i].name) is already in a host group on the FlashArray. Please ensure it is not in-use and remove it from the group named $($foundHost.hgroup) ."
      }
      if ($foundprotocol -eq "iSCSI") 
      {
          if (0 -ne $foundHost[0].wwn.count)
          {
            throw "The host $($esxiConnections[$i].name) is already configured on the FlashArray for FC. Mixed mode is not supported by VMware."
          }
      }
      else 
      {
          if (0 -ne $foundHost[0].iqn.count)
          {
            throw "The host $($esxiConnections[$i].name) is already configured on the FlashArray for iSCSI. Mixed mode is not supported by VMware."
          }
      }
      $faHosts += $foundHost.name
    }
    else {
      if ($foundProtocol -eq "iSCSI")
      {
        $faHosts += (New-PfaHostFromVmHost -esxi (get-vmhost $esxiConnections[$i].name) -Iscsi -Flasharray $flasharray -ErrorAction Stop).name 
      }
      elseif ($foundProtocol -eq "FC") {
        $faHosts += (New-PfaHostFromVmHost -esxi (get-vmhost $esxiConnections[$i].name) -FC -Flasharray $flasharray -ErrorAction Stop).name  
      }
    }
  }
  Write-Debug -Message ($faHosts| out-string)
  $groupName = ("vCF-WorkloadDomain-" + (get-random -Maximum 9999 -Minimum 1000))
  $hostGroup = New-PfaRestOperation -resourceType "hgroup/$($groupName)" -restOperationType POST -flasharray $flasharray -SkipCertificateCheck  -ErrorAction stop
  if ($fahosts.count -gt 0)
  {
    if ($fahosts.count -gt 1)
    {
      $hostsJson = $fahosts |ConvertTo-Json
    }
    else {
      $hostsJson = ("[" + ($fahosts |ConvertTo-Json) + "]")
    }
    $hostGroup = New-PfaRestOperation -resourceType "hgroup/$($groupName)" -restOperationType PUT -flasharray $flasharray -jsonBody "{`"addhostlist`":$($hostsJson)}" -SkipCertificateCheck  -ErrorAction stop 
    Write-Debug -Message $hostGroup
  }
  Write-Progress -parentid 1 -Id 2 -Activity "Configuring ESXi hosts on FlashArray" -Status "Configured $($esxiConnections.count) hosts on FlashArray" -PercentComplete 100
  Write-Progress -id 1 -Activity "VCF and Pure ESXi Host Commission Process" -Status "Configuring physical storage." -PercentComplete 50
  if (![string]::IsNullOrWhiteSpace($DatastoreName))
  {
    Write-Progress -parentid 1 -Id 2 -Activity "Provisioning a VMFS datastore from the FlashArray." -Status "Creating Volume" -PercentComplete 25
    $newVol = New-PfaRestOperation -resourceType "volume/$($datastoreName)" -restOperationType POST -flasharray $flasharray -jsonBody "{`"size`":`"$($volSize)`"}" -SkipCertificateCheck -ErrorAction Stop 
    Write-Debug -Message $newVol
    New-PfaRestOperation -resourceType "hgroup/$($groupName)/volume/$($newVol.name)" -restOperationType POST -flasharray $flasharray -SkipCertificateCheck -ErrorAction Stop |Out-Null
    $newNAA =  "naa.624a9370" + $newVol.serial.toLower()
    $esxi = $esxiConnections |Select-Object -Last 1
    Write-Progress -parentid 1 -Id 2 -Activity "Provisioning a VMFS datastore from the FlashArray." -Status "Rescanning HBAs" -PercentComplete 50
    get-vmhost $esxi.name |Get-VMHostStorage -RescanAllHba  |Out-Null
    Write-Progress -parentid 1 -Id 2 -Activity "Provisioning a VMFS datastore from the FlashArray." -Status "Formatting VMFS" -PercentComplete 75
    get-vmhost $esxi.name |new-datastore -name $datastoreName -vmfs -Path $newNAA -FileSystemVersion 6 -ErrorAction Stop |Out-Null
    Write-Progress -parentid 1 -Id 2 -Activity "Provisioning a VMFS datastore from the FlashArray." -Status "Complete." -PercentComplete 100
  }
  else {
    Write-Progress -parentid 1 -Id 2 -Activity "Provisioning a vVol protocol endpoint from the FlashArray." -Status "Creating PE" -PercentComplete 25
    $protocolEndpoint = "vVol-Protocol-Endpoint"    
    New-PfaRestOperation -resourceType volume/$($protocolEndpoint)?protocol_endpoint=true -restOperationType POST -flasharray $flasharray -SkipCertificateCheck -ErrorAction SilentlyContinue |Out-Null
    try
    {
      Write-Progress -parentid 1 -Id 2 -Activity "Provisioning a vVol protocol endpoint from the FlashArray." -Status "Connecting PE" -PercentComplete 75
      New-PfaRestOperation -resourceType "hgroup/$($groupName)/volume/$($protocolEndpoint)" -restOperationType POST -flasharray $flasharray -SkipCertificateCheck -ErrorAction Stop |Out-Null
    }
    catch
    {
      if ($_.Exception -notlike "*Connection already exists.*")
      {
          throw $_.Exception
      }
    }
  }
  Write-Progress -id 1 -Activity "VCF and Pure ESXi Host Commission Process" -Status "Final Host Configuration" -PercentComplete 70
  foreach ($esxiConnection in $esxiConnections)
  {
      Write-Progress -parentid 1 -Id 2 -Activity "Configuring ESXi hosts." -Status "Enabling SSH on $($esxiConnections.count) hosts" -PercentComplete 25
      #prepare for VCF commissioning 
      $esxi = get-vmhost $esxiConnection.name
      $esxi|Get-VMHostService |Where-Object { $_.Key -eq "TSM-SSH"} |Start-vmhostService |Out-Null
      Write-Progress -parentid 1 -Id 2 -Activity "Rescanning all hosts." -Status "Rescanning $($esxiConnections.count) hosts" -PercentComplete 50
      $esxi | Get-VMHostStorage -RescanAllHba  |Out-Null
      Write-Progress -parentid 1 -Id 2 -Activity "Rescanning all hosts." -Status "Complete" -PercentComplete 100
  } 
  if ($Vvol -eq $true)
  {
    Write-Progress -parentid 1 -Id 2 -Activity "Registering VASA Provider with VCF SDDC Manager." -Status "Adding VASA Provider" -PercentComplete 25
    $foundProviders = Get-PfaVcfVasaProvider
    $mgmtIP = New-PfaRestOperation -resourceType network -restOperationType GET -flasharray $flasharray -SkipCertificateCheck |Where-Object {$_.name -like "CT0.eth0"}
    $foundProvider = $foundProviders |Where-Object {$_.url -like "*$($mgmtIP.address)*"} 
    Write-Progress -parentid 1 -Id 2 -Activity "Registering VASA Provider with VCF SDDC Manager." -Status "Adding VASA Provider" -PercentComplete 50
    if ([string]::IsNullOrWhiteSpace($foundProvider))
    {
      New-PfaVcfVasaProvider -arrayAddress $FlashArrayFqdn -ArrayCredential $FlashArrayCredential -Protocol $foundProtocol
    }
    else {
     if ($foundProvider.storageContainers.protocolType -ne $foundProtocol)
     {
        Write-Warning -Message "The VASA provider for this array is already registered but the storage container is already registered with $($foundProtocol). VCF only allows a storage container to be registered via one protocol at a time."
     }
    }
    Write-Progress -parentid 1 -Id 2 -Activity "Registering VASA Provider with VCF SDDC Manager." -Status "Added VASA Provider" -PercentComplete 100
  }
  $hostSpecs = @()
  Write-Progress -id 1 -Activity "VCF and Pure ESXi Host Commission Process" -Status "Commissioning Hosts" -PercentComplete 85
  Write-Progress -parentid 1 -Id 2 -Activity "Generating JSON for host validation." -Status "Generating" -PercentComplete 25
  foreach ($EsxiHost in $EsxiHostFqdn)
  {
    $hostspec = New-Object -TypeName psobject
    $hostspec | Add-Member -MemberType NoteProperty -Name fqdn -value $EsxiHost
    $hostspec | Add-Member -MemberType NoteProperty -Name username -value $EsxiHostCredential.UserName
    if ($Vvol -eq $true)
    {
      $hostspec | Add-Member -MemberType NoteProperty -Name storageType -value "VVOL"
    }
    else {
      $hostspec | Add-Member -MemberType NoteProperty -Name storageType -value "FC"
    }
    $hostspec | Add-Member -MemberType NoteProperty -Name password -value ($EsxiHostCredential.Password |ConvertFrom-SecureString -AsPlainText)
    $hostspec | Add-Member -MemberType NoteProperty -Name networkPoolName -value $VcfNetworkPool
    $hostspec | Add-Member -MemberType NoteProperty -Name networkPoolId -value ($vcfpools |Where-Object {$_.name -eq $VcfNetworkPool}).id
    if ($Vvol -eq $true)
    {
      $hostspec | Add-Member -MemberType NoteProperty -Name vvolStorageProtocolType -value $foundProtocol.ToUpper()
    }
    $hostSpecs += $hostspec
  } 
  Write-Progress -parentid 1 -Id 2 -Activity "Generating JSON for host validation." -Status "Generated" -PercentComplete 100
  $hostJson =  $hostSpecs  |ConvertTo-Json
  Write-Debug -Message $hostJson
  #refresh VCF connection
  $headers = @{"Accept" = "application/json"}
  $response = Invoke-RestMethod -Method PATCH -Uri "https://$($sddcManager)/v1/tokens/access-token/refresh" -Headers $headers -body $global:refreshToken -SkipCertificateCheck
  $Global:accessToken = $response
  $vcfHeader = @{authorization="Bearer $($Global:accessToken)"}
  #validate host configuration
  Write-Progress -parentid 1 -Id 2 -Activity "Adding hosts to SDDC Manager" -Status "Submitting for validation." -PercentComplete 5
  $hostValidationTask = Invoke-RestMethod -Method POST -URI "https://$($sddcManager)/v1/hosts/validations"  -ContentType application/json -headers $vcfHeader -body $hostJson -SkipCertificateCheck
  Do 
  {
      Write-Progress -parentid 1 -Id 2 -Activity "Adding hosts to SDDC Manager." -Status "Waiting for validation" -PercentComplete 25
      $hostValidationTaskResponse = Invoke-RestMethod -Method GET -URI "https://$($sddcManager)/v1/hosts/validations/$($hostValidationTask.id)" -Headers $vcfHeader -ContentType application/json -SkipCertificateCheck
      Start-Sleep -Seconds 5
  }
  While ($hostValidationTaskResponse.executionStatus -eq "IN_PROGRESS")
  Write-Debug -Message $hostValidationTaskResponse
  Write-Progress -parentid 1 -Id 2 -Activity "Adding hosts to SDDC Manager." -Status "Validated" -PercentComplete 45
  if ($hostValidationTaskResponse.executionStatus -eq "COMPLETED" -and $hostValidationTaskResponse.resultStatus -eq "SUCCEEDED") 
  {
      Write-Progress -parentid 1 -Id 2 -Activity "Adding hosts to SDDC Manager." -Status "Commissioning" -PercentComplete 50
      $commissionHostsTask = Invoke-RestMethod -Method POST -URI "https://$sddcManager/v1/hosts/" -headers $vcfHeader -ContentType application/json -body $hostJson -SkipCertificateCheck
  }
  else {
      throw "There was a problem validating the hosts: $($hostValidationTaskResponse.validationChecks.errorResponse.message)"
  }
  Do 
  {
    Write-Progress -parentid 1 -Id 2 -Activity "Adding hosts to SDDC Manager." -Status "Waiting for commissioning to complete" -PercentComplete 75
      $hostCommissionTaskResponse = Invoke-RestMethod -Method GET -URI "https://$($sddcManager)/v1/tasks/$($commissionHostsTask.id)" -Headers $vcfHeader -ContentType application/json -SkipCertificateCheck
      Start-Sleep -Seconds 5
  }
  While ($null -eq $hostCommissionTaskResponse.completionTimestamp)
  Write-Debug -Message $hostCommissionTaskResponse
  if ($hostCommissionTaskResponse.status -eq "Successful")
  {
    $commissionedHosts = @()
    foreach ($hostResourceId in $hostCommissionTaskResponse.resources.resourceid) 
    {
      $commissionedHosts += Get-VcfHost -id $hostResourceId
    }
  }
  else {
      throw "There was a problem commissioning the hosts: $($hostCommissionTaskResponse.subtasks)"
  }
  Write-Progress -parentid 1 -Id 2 -Activity "Adding hosts to SDDC Manager." -Status "Commissioning complete" -PercentComplete 100
  Write-Progress -id 1 -Activity "VCF and Pure ESXi Host Commission Process" -Status "Process Complete" -PercentComplete 100
  return $commissionedHosts
}
function Get-PfaVcfVasaProvider {
    <#
    .SYNOPSIS
      Returns all VASA Providers registered in SDDC Manager.
    .DESCRIPTION
      Returns all VASA Providers registered in SDDC Manager.
    .INPUTS
      None 
    .OUTPUTS
      Returns the VASA Provider(s)
    .EXAMPLE
      PS C:\ Get-PfaVcfVasaProvider
  
      Returns all VASA Providers registered in SDDC Manager.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/25/2020
      Purpose/Change: First release
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>
    if ($psversiontable.PSEdition -ne "Core")
    {
      throw "The cmdlet Get-PfaVcfVasaProvider is only supported with PowerShell Core (7.x or later)."
    }
    $vcfHeader = @{authorization="Bearer $($Global:accessToken)"} 
    $vasaProviders = (Invoke-RestMethod -SkipCertificateCheck -Headers $vcfHeader -Method GET -Uri "https://$($sddcManager)/v1/vasa-providers"  -ContentType "application/json").elements
    if ($null -ne $vasaProviders)
    {
        return $vasaProviders
    }
    else {
        return $null
    }
}  
function New-PfaVcfVasaProvider {
    <#
    .SYNOPSIS
      Adds a VASA Provider to SDDC Manager.
    .DESCRIPTION
      Connects to a FlashArray pulls the correct information, and registers its CTO VASA provider with SDDC Manager.
    .INPUTS
      FlashArray IP or FQDN, user name and password.
    .OUTPUTS
      Returns the VASA Provider registration.
    .EXAMPLE
      PS C:\ New-PfaVcfVasaProvider -arrayAddress flasharray-m50-1 -username pureuser -password *********
  
      Connects to a FlashArray pulls the correct information, and registers its CTO VASA provider with SDDC Manager.
    .EXAMPLE
      PS C:\ New-PfaVcfVasaProvider -arrayAddress flasharray-m50-1 -credential (get-credential)
  
      Connects to a FlashArray pulls the correct information, and registers its CTO VASA provider with SDDC Manager.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  09/25/2020
      Purpose/Change: First release
  
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>
    [CmdletBinding(DefaultParameterSetName='Username')]
    Param(
            [Parameter(Position=0,mandatory=$True)]
            [string]$ArrayAddress,

            [Parameter(Position=1,ParameterSetName='Username',mandatory=$true)]
            [string]$Username,

            [Parameter(Position=2,mandatory=$True,ParameterSetName='Username')]
            [securestring]$Password,

            [Parameter(Position=3,ValueFromPipeline=$True,mandatory=$true,ParameterSetName='Creds')]
            [System.Management.Automation.PSCredential]$ArrayCredential,
            
            [Parameter(Position=4)]
            [ValidateSet('iSCSI','FC')]
            [string]$Protocol
    )
    if ($psversiontable.PSEdition -ne "Core")
    {
      throw "The cmdlet New-PfaVcfVasaProvider is only supported with PowerShell Core (7.x or later)."
    }
    if ($null -eq $ArrayCredential)
    {
        $ArrayCredential = New-Object System.Management.Automation.PSCredential ($Username, $Password)
    }
    $fa = New-PfaArray -EndPoint $ArrayAddress -Credentials $ArrayCredential -IgnoreCertificateError
    $mgmtIP = New-PfaRestOperation -resourceType network -restOperationType GET -flasharray $fa -SkipCertificateCheck |Where-Object {$_.name -like "CT0.eth0"}
    $arrayname = New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $fa -SkipCertificateCheck
    $foundProtocol = checkFaProtocol -flasharray $fa -protocol $Protocol -ErrorAction stop
    $FaName = ("$($arrayname.array_name)-CT0") 
    $VasaUrl = ("https://$($mgmtIP.address):8084/version.xml") 
    $stdPassword = ConvertFrom-SecureString $ArrayCredential.password -AsPlainText
    $vasaBody = "{
        `"name`": `"$($FaName)`",
        `"storageContainers`": [ {
            `"name`": `"Vvol container`",
            `"protocolType`": `"$($foundProtocol)`"
        } ],
        `"url`": `"$($VasaUrl)`",
        `"users`": [ {
            `"password`": `"$($stdPassword)`",
            `"username`": `"$($ArrayCredential.UserName)`"
        } ]
    }"
    Write-Debug $vasaBody
    $vcfHeader = @{authorization="Bearer $($Global:accessToken)"} 
    $vasaProvider = Invoke-RestMethod -SkipCertificateCheck -Headers $vcfHeader -Method POST -Uri "https://$($sddcManager)/v1/vasa-providers" -Body $vasaBody -ContentType "application/json"
    return $vasaProvider
}  
function checkDefaultFlashArray{
    if ($null -eq $Global:DefaultFlashArray)
    {
        throw "You must pass in a FlashArray connection or create a default FlashArray connection with New-Pfaconnection"
    }
    else 
    {
        return $Global:DefaultFlashArray
    }
}
function checkFaProtocol{
  [CmdletBinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [PurePowerShell.PureArray]$Flasharray,

        [Parameter(Position=1,mandatory=$true)]
        [string]$Protocol
    )
    $arrayname = New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $Flasharray -SkipCertificateCheck
    $arrayPorts = New-PfaRestOperation -resourceType port -restOperationType GET -flasharray $Flasharray -SkipCertificateCheck
    $iscsi = $false
    $fc = $false
    
    if (($arrayPorts |where-object {$null -ne $_.iqn}).count -ne 0)
    {
        $iscsi = $true
    }
    if (($arrayPorts |where-object {$null -ne $_.wwn}).count -ne 0)
    {
        $fc = $true
    }
    if (($iscsi -eq $true) -and ($fc -eq $false))
    {
        $FoundProtocol = "iSCSI"
    }
    if (($iscsi -eq $false) -and ($fc -eq $True))
    {
        $FoundProtocol = "FC"
    }
    if (($iscsi -eq $false) -and ($fc -eq $false))
    {
        throw "Neither Fibre Channel or iSCSI ports were found on the input array $($arrayname.array_name)"
    }
    if (($iscsi -eq $true) -and ($fc -eq $true))
    {
        if ([string]::IsNullOrWhiteSpace($Protocol))
        {
            throw "Both Fibre Channel and iSCSI found on this array. Please specify the desired protocol in the -protocol parameter (iSCSI or FC)"
        }
        $FoundProtocol = $Protocol
    }
    if (![string]::IsNullOrWhiteSpace($Protocol))
    {
        if ($Protocol -ne $FoundProtocol)
        {
            throw "Specified protocol $($protocol) is not found on the array. Only $($foundProtocol) is found on $($arrayname.array_name)"
        }
    }
    return $FoundProtocol
}

