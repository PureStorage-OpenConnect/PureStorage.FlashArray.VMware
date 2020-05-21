function Get-PfavVolReplicationGroup {
    <#
    .SYNOPSIS
      Returns FlashArray Replication Groups
    .DESCRIPTION
      Takes in storage policy, a vVol datastore, a VM, or no inputs, and returns source and/or target replication groups.
    .INPUTS
      Storage Policy, vVol datastore, source or target
    .OUTPUTS
      Replication groups
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  05/13/2020
      Purpose/Change: Function creation
    .EXAMPLE
      PS C:\ Get-PfavVolReplicationGroup

      Returns all FlashArray vVol Replication Groups from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1    
      PS C:\ Get-PfavVolReplicationGroup -faultDomain $fd

      Returns all FlashArray vVol Replication Groups from the specified fault domain (FlashArray) which has a vVol datastore that is mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfavVolReplicationGroup -source

      Returns all source FlashArray vVol Replication Groups from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1    
      PS C:\ Get-PfavVolReplicationGroup -faultDomain $fd -source

      Returns all FlashArray vVol source Replication Groups from the specified fault domain (FlashArray) which has a vVol datastore that is mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfavVolReplicationGroup -target

      Returns all target FlashArray vVol Replication Groups from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfavVolReplicationGroup -testFailover

      Returns all FlashArray vVol Replication Groups that are in the middle of a test failover from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfavVolReplicationGroup -failedOver

      Returns all FlashArray vVol Replication Groups that have been failed over from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfavVolReplicationGroup -VM (get-vm vVolVM-01)

      Returns the FlashArray vVol replication group for the virtual machine named vVolVM-01 
    .EXAMPLE
      PS C:\ Get-PfavVolReplicationGroup -policy (Get-SpbmStoragePolicy vVolStoragePolicy)

      Returns all the FlashArray vVol replication groups that are valid for the storage policy from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding(DefaultParameterSetName='DefaultSet')]
    Param(
            [Parameter(ParameterSetName='VM',Position=0,ValueFromPipeline=$True,mandatory=$true)]
            [ValidateScript({
                $ds = $_ |get-datastore |where-object {$_.Type -eq 'VVOL'} | where-object {$_.ExtensionData.Info.VvolDS.StorageArray[0].VendorId -eq "PURE"}
                if ($null -eq $ds)
                {
                    throw "This VM is not using a Pure Storage vVol datastore."
                }
                else {
                  $true
                }
              })]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,

            [Parameter(ParameterSetName='Datastore',Position=1,ValueFromPipeline=$True)]
            [ValidateScript({
              if ($_.Type -ne 'VVOL')
              {
                  throw "The entered datastore is not a vVol datastore. It is type $($_.Type). Please only enter a vVol datastore"
              }
              elseif ($_.ExtensionData.Info.VvolDS.StorageArray[0].VendorId -ne "PURE") 
              {
                throw "This is not a Pure Storage vVol datastore"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(ParameterSetName='Datastore',Position=2,ValueFromPipeline=$True,mandatory=$true)]
            [ValidateScript({
                $rules = $_.AnyOfRuleSets.Allofrules.capability |Where-Object {$_.Name -like "*com.purestorage.storage.replication*"}
                if ($null -eq $rules)
                {
                    throw "This is not a Pure Storage replication-based policy."
                }
                else {
                  $True
                }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$policy,

            [Parameter(ParameterSetName='DefaultSet',Position=3)]
            [Switch]$source,

            [Parameter(ParameterSetName='DefaultSet',Position=4)]
            [Switch]$target,

            [Parameter(ParameterSetName='DefaultSet',Position=5)]
            [Switch]$testFailover,

            [Parameter(ParameterSetName='DefaultSet',Position=6)]
            [Switch]$failedOver,

            [Parameter(ParameterSetName='DefaultSet',Position=7)]
            [ValidateScript({
              if ($_.StorageArray.VendorId -ne "PURE")
              {
                  throw "This is not a Pure Storage fault domain (FlashArray)."
              }
              else {
                $True
              }
            })]
            [VMware.VimAutomation.Storage.Types.V1.Spbm.Replication.SpbmFaultDomain]$faultDomain
    )
    if ($null -ne $datastore)
    {
      $pureReplicationGroups = Get-SpbmReplicationGroup -Datastore $datastore -StoragePolicy $policy
    }
    elseif ($null -ne $policy) {
      $pureReplicationGroups = Get-SpbmReplicationGroup -StoragePolicy $policy
    }
    elseif ($null -ne $vm) {
      $pureReplicationGroups = Get-SpbmReplicationGroup -VM $vm
    }
    else {
      if ($null -ne $faultDomain)
      {
        $pureReplicationGroups = Get-SpbmReplicationGroup -FaultDomain $faultDomain
      }
      else 
      {
        $vp = Get-VasaProvider |Where-Object {$_.Namespace -eq "com.purestorage"}
        $pureReplicationGroups = Get-SpbmReplicationGroup -VasaProvider $vp
      }
      $groupfilter = @()
      if ($source -eq $True)
      {
        $groupfilter += "Source"
      }
      if ($target -eq $True)
      {
        $groupfilter += "Target"
      }
      if ($testFailover -eq $True)
      {
        $groupfilter += "InTest"
      }
      if ($failedOver -eq $True)
      {
        $groupfilter += "FailedOver"
      }
      if ($groupfilter.count -ge 1)
      {
        $pureReplicationGroups = $pureReplicationGroups  | Where-Object {$_}| Where-Object {$groupfilter.contains($_.State.ToString())}
      }
    }
    Write-Debug ($pureReplicationGroups |format-list * |Out-String)
    return $pureReplicationGroups
}
function Get-PfavVolReplicationGroupPartner {
  <#
  .SYNOPSIS
    Returns any partner FlashArray Replication Groups for a specified group.
  .DESCRIPTION
    Takes in a replication group and some optional filters
  .INPUTS
    Storage Policy, vVol datastore, source or target
  .OUTPUTS
    Replication groups
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/14/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ $vm = get-vm srmvm
    PS C:\ $group = $vm |Get-PfavVolReplicationGroup
    PS C:\ Get-PfavVolReplicationGroupPartner -replicationGroup $group
    
    Finds the replication group a VM's storage is assigned to and returns the target replication group(s). 
  .EXAMPLE
    PS C:\ $vm = get-vm srmvm
    PS C:\ $group = $vm |Get-PfavVolReplicationGroup
    PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1
    PS C:\ Get-PfavVolReplicationGroupPartner -replicationGroup $group -faultDomain $fd
    
    Finds the replication group a VM's storage is assigned to and returns the target replication group for the specified fault domain (FlashArray). 
  .EXAMPLE
    PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1  
    PS C:\ $targetGroup = Get-PfavVolReplicationGroup -target -faultDomain $fd
    PS C:\ Get-PfavVolReplicationGroupPartner -replicationGroup $targetGroup
    
    Finds the source replication group of the specified target replication group. 

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
          [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
          [VMware.VimAutomation.ViCore.Types.V1.Storage.ReplicationGroup]$replicationGroup,
          
          [Parameter(Position=2,ValueFromPipeline=$True)]
          [ValidateScript({
            if ($_.StorageArray.VendorId -ne "PURE")
            {
                throw "This is not a Pure Storage fault domain (FlashArray)."
            }
            else {
              $True
            }
          })]
          [VMware.VimAutomation.Storage.Types.V1.Spbm.Replication.SpbmFaultDomain]$faultDomain
  )
  if ($replicationGroup.state.ToString() -eq "Source")
  {
    $pureReplicationGroups = Get-PfavVolReplicationGroup -testFailover -target -failedOver
    $groupID = $replicationGroup.ExtensionData.groupId
    $groupPartners = @()
    foreach ($pureReplicationGroup in $pureReplicationGroups)
    {
      $partnerGroupID = $pureReplicationGroup.ExtensionData.sourceInfo.sourceGroupId
      if ($partnerGroupID.deviceGroupId.id -eq $groupID.deviceGroupId.id)
      {
        if ($partnerGroupID.faultDomainId.id -eq $groupID.faultDomainId.id)
        {
          if (($null -ne $faultDomain) -and ($pureReplicationGroup.faultDomain.id -eq $faultDomain.Id))
          {
            write-host "fart"
            $groupPartners += $pureReplicationGroup
          }
          if ($null -eq $faultDomain)
          {
            $groupPartners += $pureReplicationGroup
          }
        }
      }
    }
    return $groupPartners
  }
  else{
    $pureReplicationGroups = Get-PfavVolReplicationGroup -source
    $groupID = $replicationGroup.ExtensionData.sourceInfo.sourceGroupId
    foreach ($pureReplicationGroup in $pureReplicationGroups)
    {
      $partnerGroupID = $pureReplicationGroup.ExtensionData.groupId
      if ($partnerGroupID.deviceGroupId.id -eq $groupID.deviceGroupId.id)
      {
        if ($partnerGroupID.faultDomainId.id -eq $groupID.faultDomainId.id)
        {
          if (($null -ne $faultDomain) -and ($pureReplicationGroup.faultDomain.id -ne $faultDomain.Id))
          {
            throw "The source replication group does not exist on the specified Fault Domain: $($faultDomain.name) ($($faultDomain.id)). It resides on a FlashArray with ID of $($pureReplicationGroup.faultDomain.id)"
          }
          return $pureReplicationGroup
        }
      }
    }
  }
}
function Get-PfavVolFaultDomain {
  <#
  .SYNOPSIS
    Returns all or specified FlashArray fault domains
  .DESCRIPTION
    Takes in a name, serial number, connection or nothing and returns the corresponding FlashArray fault domains
  .INPUTS
    Takes in a name, serial number, connection or nothing.
  .OUTPUTS
    Fault domains
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/16/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Get-PfavVolFaultDomain 

    Returns all Pure Storage FlashArray fault domains
  .EXAMPLE
    PS C:\ Get-PfavVolFaultDomain -ArraySerial 7e914d96-c90a-31e0-a495-75e8b3c300cc

    Returns the FlashArray fault domain for the specified array serial number.
  .EXAMPLE
    PS C:\ Get-PfavVolFaultDomain -ArrayName flasharray-m50-1

    Returns the FlashArray fault domain for the specified array name.
  .EXAMPLE
    PS C:\ $fa = new-pfaConnection -endpoint flasharray-m50-1 -ignoreCertificateError -DefaultArray
    PS C:\ Get-PfavVolFaultDomain -FlashArray $fa

    Returns the FlashArray fault domain for the specified FlashArray connection.

    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

  [CmdletBinding(DefaultParameterSetName='Name')]
  Param(
        [Parameter(Position=0,ValueFromPipeline=$True,ParameterSetName='Connection')]
        [PurePowerShell.PureArray]$flasharray,

        [Parameter(Position=1,ParameterSetName='Name')]
        [string]$arrayName,

        [Parameter(Position=2,ParameterSetName='Serial')]
        [string]$arraySerial
  )
    if (![string]::IsNullOrEmpty($arrayName))
    {
      $faultDomain = Get-SpbmFaultDomain -Name $arrayName -ErrorAction Stop
    }
    elseif (![string]::IsNullOrEmpty($arraySerial))
    {
      $faultDomain = Get-SpbmFaultDomain | Where-Object {$_.StorageArray.Id -eq "com.purestorage:$($arraySerial)"} 
      if ($null -eq $faultDomain)
      {
        throw "Could not find a fault domain for specified serial number: $($arraySerial)"
      }
    }
    elseif ($null -ne $flasharray) 
    {
      $arraySerial = (Get-PfaArrayAttributes -array $flasharray).id
      $faultDomain = Get-SpbmFaultDomain -ErrorAction Stop | Where-Object {$_.StorageArray.Id -eq "com.purestorage:$($arraySerial)"} 
      if ($null -eq $faultDomain)
      {
        throw "Could not find a fault domain for specified FlashArray with the serial number: $($arraySerial)"
      }
    }
    else {
      $faultDomain = Get-SpbmFaultDomain | Where-Object {$_.StorageArray.VendorId -eq "PURE"}
    }
    return $faultDomain
}
function Get-PfavVolStoragePolicy {
  <#
  .SYNOPSIS
    Returns all or specified FlashArray storage policies
  .DESCRIPTION
    Returns all or replication-based FlashArray storage policies
  .INPUTS
    Nothing, replication, or a vCenter server
  .OUTPUTS
    Storage policies
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/17/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Get-PfavVolStoragePolicy 

    Returns all Pure Storage FlashArray-based storage policies
  .EXAMPLE
    PS C:\ Get-PfavVolStoragePolicy -replication

    Returns all replication-enabled Pure Storage FlashArray-based storage policies
  .EXAMPLE
    PS C:\ Get-PfavVolStoragePolicy -server $global:DefaultVIServer

    Returns all Pure Storage FlashArray-based storage policies for a specific vCenter

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
        [Parameter(Position=0)]
        [Switch]$replication,

        [Parameter(Position=1)]
        [VMware.VimAutomation.ViCore.Types.V1.VIServer]$server
  )
  try {
    if ($null -ne $server)
    {
      $purePolicies = Get-SpbmStoragePolicy -Namespace "com.purestorage.storage.policy" -Server $server -ErrorAction Stop
    }
    else {
      $purePolicies = Get-SpbmStoragePolicy -Namespace "com.purestorage.storage.policy" -ErrorAction Stop
    }
  }
  catch {
    #sometimes the SPBM service errors on first try. A retry works.
    if ($null -ne $server)
    {
      $purePolicies = Get-SpbmStoragePolicy -Namespace "com.purestorage.storage.policy" -Server $server
    }
    else {
      $purePolicies = Get-SpbmStoragePolicy -Namespace "com.purestorage.storage.policy"
    }
  }
  if ($replication -eq $true)
  {
    $purePolicies = $purePolicies |Where-Object {$_.AnyOfRuleSets.allofrules.capability.name -like "com.purestorage.storage.replication*"}
  }
  return $purePolicies
}
function Get-PfavVolStorageArray {
  <#
  .SYNOPSIS
    Returns all or specified FlashArray storage array VASA objects
  .DESCRIPTION
    Returns all or replication-based FlashArray storage array VASA objects
  .INPUTS
    Nothing, FlashArray connection, FlashArray name, or FlashArray serial number.
  .OUTPUTS
    VASA Storage Array(s)
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/17/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Get-PfavVolStorageArray 

    Returns all Pure Storage FlashArray storage array VASA objects
  .EXAMPLE
    PS C:\ Get-PfavVolStorageArray -ArraySerial 7e914d96-c90a-31e0-a495-75e8b3c300cc

    Returns the FlashArray storage array VASA object for the specified array serial number.
  .EXAMPLE
    PS C:\ Get-PfavVolStorageArray -ArrayName flasharray-m50-1

    Returns the FlashArray storage array VASA object  for the specified array name.
  .EXAMPLE
    PS C:\ $fa = new-pfaConnection -endpoint flasharray-m50-1 -ignoreCertificateError -DefaultArray
    PS C:\ Get-PfavVolStorageArray -FlashArray $fa

    Returns the FlashArray storage array VASA object for the specified FlashArray connection.

    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding(DefaultParameterSetName='Name')]
    Param(
          [Parameter(Position=0,ValueFromPipeline=$True,ParameterSetName='Connection')]
          [PurePowerShell.PureArray]$flasharray,
  
          [Parameter(Position=1,ParameterSetName='Name')]
          [string]$arrayName,
  
          [Parameter(Position=2,ParameterSetName='Serial')]
          [string]$arraySerial
    )
      $pureArray = Get-VasaStorageArray |Where-Object {$_.VendorID -eq "PURE"}
      if (![string]::IsNullOrEmpty($arrayName))
      {
        $pureArray = $pureArray |Where-Object {$_.Name -eq $arrayName}
      }
      elseif (![string]::IsNullOrEmpty($arraySerial))
      {
        $pureArray = $pureArray  | Where-Object {$_.Id -eq "com.purestorage:$($arraySerial)"} 
        if ($null -eq $pureArray)
        {
          throw "Could not find a storage array for specified serial number: $($arraySerial). Make sure its VASA providers are registered on the correct vCenter."
        }
      }
      elseif ($null -ne $flasharray) 
      {
        $arraySerial = (Get-PfaArrayAttributes -array $flasharray).id
        $pureArray = $pureArray  | Where-Object {$_.Id -eq "com.purestorage:$($arraySerial)"} 
        if ($null -eq $pureArray)
        {
          throw "Could not find a storage array for specified FlashArray with serial number: $($arraySerial). Make sure its VASA providers are registered on the correct vCenter."
        }
      }
      return $pureArray
}
function New-PfavVolStoragePolicy {
  <#
  .SYNOPSIS
    Creates a new FlashArray Storage Policy
  .DESCRIPTION
    Creates a new FlashArray Storage Policy with specified capabilities
  .INPUTS
    Capabilities
  .OUTPUTS
    New storage policy
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/17/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Get-PfavVolStoragePolicy 

    Returns all Pure Storage FlashArray-based storage policies

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
        [Parameter(Position=0,ParameterSetName='NewConfig',mandatory=$true)]
        [Switch]$newConfig,

        [Parameter(Position=1,ParameterSetName='Config',mandatory=$true,ValueFromPipeline=$True)]
        [FlashArrayvVolPolicyConfig]$config,

        [Parameter(Position=2,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays,

        [Parameter(Position=3,ParameterSetName='Manual')]
        [Nullable[boolean]]$replicationEnabled,

        [Parameter(Position=4,ParameterSetName='Manual')]
        [System.TimeSpan]$replicationInterval,

        [Parameter(Position=5,ParameterSetName='Manual')]
        [System.TimeSpan]$replicationRetentionShort,

        [Parameter(Position=6,ParameterSetName='Manual')]
        [int]$replicationConcurrency,

        [Parameter(Position=7,ParameterSetName='Manual')]
        [String]$consistencyGroupName,

        [Parameter(Position=8,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays,

        [Parameter(Position=9,ParameterSetName='Manual')]
        [Nullable[boolean]]$localSnapshotEnabled,

        [Parameter(Position=10,ParameterSetName='Manual')]
        [System.TimeSpan]$localSnapshotInterval,

        [Parameter(Position=11,ParameterSetName='Manual')]
        [System.TimeSpan]$localSnapshotRetentionShort,

        [Parameter(Position=12,ParameterSetName='Manual')]
        [Parameter(Position=12,ParameterSetName='Config')]
        [VMware.VimAutomation.ViCore.Types.V1.VIServer]$server
  )
  if ($newConfig -eq $true)
  {
    return ([FlashArrayvVolPolicyConfig]::new($sourceFlashArrays, $replicationEnabled, $replicationInterval, $replicationRetentionShort, $replicationConcurrency, $consistencyGroupName, $targetFlashArrays, $localSnapshotEnabled , $localSnapshotInterval, $localSnapshotRetentionShort))
  }
  if ($null -eq $config)
  {
    config = ([FlashArrayvVolPolicyConfig]::new($sourceFlashArrays, $replicationEnabled, $replicationInterval, $replicationRetentionShort, $replicationConcurrency, $consistencyGroupName, $targetFlashArrays, $localSnapshotEnabled , $localSnapshotInterval, $localSnapshotRetentionShort))
  }
  $rules = @()
  $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.policy.FlashArrayGroup) `
               -Value $sourceFlashArrays.Name
  $rules += New-SpbmRule `
              -Capability (Get-SpbmCapability -Name com.purestorage.storage.policy.PureFlashArray) `
              -Value $true
  $rules += New-SpbmRule `
              -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotPolicyCapable) `
              -Value $localSnapshotEnabled
  $rules += New-SpbmRule `
              -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotInterval) `
              -Value $localSnapshotInterval
  $rules += New-SpbmRule `
              -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotRetention) `
              -Value $localSnapshotRetentionShort 
  $rules += New-SpbmRule `
              -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.ReplicationTarget) `
              -Value $targetFlashArrays.Name
  $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationCapable) `
             -Value $replicationEnabled
  $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationInterval) `
             -Value $replicationInterval
  $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationRetention) `
             -Value $replicationRetentionShort 
  $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.ReplicationConsistencyGroup) `
             -Value $consistencyGroupName
}

#Custom Classes
Class FlashArrayvVolPolicyConfig{
  static [String] $version = "1.1.0"
  static [String] $vendor = "Pure Storage"
  static [String] $name = "vVol Storage Policy Configuration"
  static [String] $model = "FlashArray"
  static [System.Boolean]$flasharray = $true
  [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays = $null
  [Nullable[boolean]]$replicationEnabled = $null
  [System.TimeSpan]$replicationInterval = $null
  [System.TimeSpan]$replicationRetentionShort = $null
  [int]$replicationConcurrency = $null
  [String]$consistencyGroupName = ""
  [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays = $null
  [Nullable[boolean]]$localSnapshotEnabled = $null
  [System.TimeSpan]$localSnapshotInterval = $null
  [System.TimeSpan]$localSnapshotRetentionShort = $null
  FlashArrayvVolPolicyConfig ([VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays, [Nullable[boolean]]$replicationEnabled, [System.TimeSpan]$replicationInterval, [System.TimeSpan]$replicationRetentionShort, [int]$replicationConcurrency, [String]$consistencyGroupName, [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays, [Nullable[boolean]]$localSnapshotEnabled , [System.TimeSpan]$localSnapshotInterval, [System.TimeSpan]$localSnapshotRetentionShort)
  {
    $this.sourceFlashArrays = $sourceFlashArrays
    $this.replicationEnabled = $replicationEnabled
    $this.replicationInterval = $replicationInterval
    $this.replicationRetentionShort = $replicationRetentionShort
    $this.replicationConcurrency = $replicationConcurrency
    $this.consistencyGroupName = $consistencyGroupName
    $this.targetFlashArrays = $targetFlashArrays
    $this.localSnapshotEnabled = $localSnapshotEnabled
    $this.localSnapshotInterval = $localSnapshotInterval
    $this.localSnapshotRetentionShort = $localSnapshotRetentionShort
    if ($replicationEnabled -eq $false)
    {
      if ($null -ne $replicationInterval)
      {
        throw "Do not specify a replication interval if replicationEnabled is set to false."
      }
      if ($null -ne $replicationRetentionShort)
      {
        throw "Do not specify a replication retention if replicationEnabled is set to false."
      }
    }
    if ($localSnapshotEnabled -eq $false)
    {
      if ($null -ne $localSnapshotInterval)
      {
        throw "Do not specify a snapshot interval if localSnapshotEnabled is set to false."
      }
      if ($null -ne $localSnapshotRetentionShort)
      {
        throw "Do not specify a snapshot retention if localSnapshotEnabled is set to false."
      }
    }
  }
}

