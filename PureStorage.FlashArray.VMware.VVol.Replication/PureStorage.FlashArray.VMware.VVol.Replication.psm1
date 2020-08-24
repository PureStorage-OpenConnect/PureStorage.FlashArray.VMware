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

  [CmdletBinding(DefaultParameterSetName='All')]
  Param(
        [Parameter(Position=0,ParameterSetName='All')]
        [Switch]$replication,

        [Parameter(Position=1,ParameterSetName='Name')]
        [Parameter(Position=1,ParameterSetName='Config',mandatory=$true)]
        [string]$name,

        [Parameter(Position=2,ParameterSetName='Config',mandatory=$true)]
        [Switch]$returnPolicyConfig,

        [Parameter(Position=3)]
        [VMware.VimAutomation.ViCore.Types.V1.VIServer]$server
  )
  if ($returnPolicyConfig -eq $true)
  {
    if (($null -eq $server) -and ($global:DefaultVIServers.count -gt 1))
    {
        throw "When specifying this cmdlet to return the policy config AND there is more than one PowerCLI vCenter connection, you must specify the vCenter to query in the -server parameter."
    }
  }
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
  if (!([string]::IsNullOrWhiteSpace($name)))
   {
    $purePolicies = $purePolicies |where-object {$_.Name -eq $name}
    if ($purePolicies.count -eq 0)
    {
      throw "No Pure Storage FlashArray vVol policies found with the name $($name)"
    }
  }
  if ($returnPolicyConfig -eq $true)
  {
    $policyConfigChange = New-PfavVolStoragePolicy -generateDefaultPolicyConfig -policyName $name -policyDescription $purePolicies.Description
    $localSnapshotEnabled = $purePolicies.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.LocalSnapshotPolicyCapable"}
    if ($null -ne $localSnapshotEnabled)
    {
      $policyConfigChange.localSnapshotEnabled = $localSnapshotEnabled.Value
    }  
    $LocalSnapshotInterval = $purePolicies.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.LocalSnapshotInterval"}
    if ($null -ne $LocalSnapshotInterval)
    {
      $policyConfigChange.localSnapshotInterval = $LocalSnapshotInterval.Value
    }  
    $LocalSnapshotRetention = $purePolicies.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.LocalSnapshotRetention"}
    if ($null -ne $LocalSnapshotRetention)
    {
      $policyConfigChange.localSnapshotRetentionShort = $LocalSnapshotRetention.Value
    } 
    $remoteReplicationEnabled = $purePolicies.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.remoteReplicationPolicyCapable"}
    if ($null -ne $remoteReplicationEnabled)
    {
      $policyConfigChange.replicationEnabled = $remoteReplicationEnabled.Value
    }  
    $remoteReplicationInterval = $purePolicies.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.remoteReplicationInterval"}
    if ($null -ne $remoteReplicationInterval)
    {
      $policyConfigChange.replicationInterval = $remoteReplicationInterval.Value
    }  
    $remoteReplicationRetention = $purePolicies.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.remoteReplicationRetention"}
    if ($null -ne $remoteReplicationRetention)
    {
      $policyConfigChange.replicationRetentionShort = $remoteReplicationRetention.Value
    } 
    $consistencyGroup = $purePolicies.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.ReplicationConsistencyGroup"}
    if ($null -ne $consistencyGroup)
    {
      $policyConfigChange.consistencyGroupName = $consistencyGroup.Value
    } 
    return $policyConfigChange
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
    Creates a new FlashArray vVol Storage Policy
  .DESCRIPTION
    Creates a new FlashArray vVol Storage Policy with specified capabilities
  .INPUTS
    Capabilities
  .OUTPUTS
    New storage policy
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/22/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ New-PfavVolStoragePolicy -policyName

    Creates a new vVol policy with the specified name and default description. The only capability is ensuring it is a FlashArray policy.
  .EXAMPLE
    PS C:\ $policyConfig = New-PfavVolStoragePolicy -generateDefaultPolicyConfig

    Generates a new FlashArray vVol policy configuration object. You can then populate the properties.
  .EXAMPLE
    PS C:\ New-PfavVolStoragePolicy -policyConfig $policyConfig

    Passes in a FlashArray vVol storage policy configuration object (FlashArrayvVolPolicyConfig) and creates a new vVol storage policy with specified capabilities
  .EXAMPLE
    PS C:\ New-PfavVolStoragePolicy -policyName pure-vvolRep -policyDescription "Replication policy for FlashArray vVol VMs" -replicationEnabled $true -replicationInterval (New-TimeSpan -Hours 1) -replicationRetentionShort (New-TimeSpan -Hours 24) -replicationConcurrency 2 -consistencyGroupName purePG

    Creates a replication type vVol storage policy. Ensures VMs are replicated once an hour, and each point in time is kept for 1 day. It also ensures that the VM is replicated to at least 2 target arrays in a consistency group called purePG.

    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

  [CmdletBinding(DefaultParameterSetName='Manual')]
  Param(
        [Parameter(Position=0,ParameterSetName='NewConfig',mandatory=$true)]
        [Switch]$generateDefaultPolicyConfig,

        [Parameter(Position=1,ParameterSetName='Config',mandatory=$true,ValueFromPipeline=$True)]
        [FlashArrayvVolPolicyConfig]$policyConfig,

        [Parameter(Position=2,mandatory=$true,ParameterSetName='Manual')]
        [Parameter(Position=2,ParameterSetName='NewConfig',mandatory=$true)]
        [String]$policyName,

        [Parameter(Position=3,ParameterSetName='Manual')]
        [Parameter(Position=3,ParameterSetName='NewConfig')]
        [String]$policyDescription,

        [Parameter(Position=4,ParameterSetName='Manual')]
        [Nullable[boolean]]$replicationEnabled,

        [Parameter(Position=5,ParameterSetName='Manual')]
        [System.TimeSpan]$replicationInterval = 0,

        [Parameter(Position=6,ParameterSetName='Manual')]
        [System.TimeSpan]$replicationRetentionShort = 0,

        [Parameter(Position=7,ParameterSetName='Manual')]
        [int]$replicationConcurrency,

        [Parameter(Position=8,ParameterSetName='Manual')]
        [String]$consistencyGroupName,

        [Parameter(Position=9,ParameterSetName='Manual')]
        [Nullable[boolean]]$localSnapshotEnabled,

        [Parameter(Position=10,ParameterSetName='Manual')]
        [System.TimeSpan]$localSnapshotInterval = 0,

        [Parameter(Position=11,ParameterSetName='Manual')]
        [System.TimeSpan]$localSnapshotRetentionShort = 0,

        [Parameter(Position=12,ParameterSetName='Manual')]
        [Parameter(Position=12,ParameterSetName='Config')]
        [VMware.VimAutomation.ViCore.Types.V1.VIServer]$server
        
        [Parameter(Position=8,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays, 
        
        [Parameter(Position=2,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays
  )
  if ($generateDefaultPolicyConfig -eq $true)
  {
    return ([FlashArrayvVolPolicyConfig]::new($policyName, $policyDescription,<#$sourceFlashArrays,#> $replicationEnabled, $replicationInterval, $replicationRetentionShort, $replicationConcurrency, $consistencyGroupName, <#$targetFlashArrays,#> $localSnapshotEnabled , $localSnapshotInterval, $localSnapshotRetentionShort))
  }
  if ([string]::IsNullOrWhiteSpace($policyName))
    {
      $policyName = $policyConfig.policyName
    }
  if ($null -ne $server)
  {
    $checkExisting = Get-SpbmStoragePolicy -Name $policyName -Server $server -ErrorAction SilentlyContinue
    if ($null -ne $checkExisting)
    {
      throw "A storage policy with the name of $($policyName) already exists on vCenter $($server.Name). Please choose a unique name."
    }
  }
  else {
    $vCenterExists = @()
    foreach ($vCenter in $global:DefaultVIServers)
    {
      $checkExisting = $null
      $checkExisting = Get-SpbmStoragePolicy -Name $policyName -Server $vCenter -ErrorAction SilentlyContinue
      if ($null -ne $checkExisting)
      {
        $vCenterExists += $vCenter.name
      }
    }
    if ($vCenterExists.count -gt 0)
    {
      throw "A storage policy with the name of $($policyName) already exists on the following vCenter(s):`n `n$($vCenterExists -join ",")`n `n Please choose a unique name."
    }
  }
  if ($null -eq $policyConfig)
  {
    $policyConfig = ([FlashArrayvVolPolicyConfig]::new($policyName, $policyDescription, $sourceFlashArrays,  $replicationEnabled, $replicationInterval, $replicationRetentionShort, $replicationConcurrency, $consistencyGroupName, $targetFlashArrays, $localSnapshotEnabled , $localSnapshotInterval, $localSnapshotRetentionShort))
  }
  $ruleSet = New-pfaRuleSetfromConfig -policyConfig $policyConfig
  if ([string]::IsNullOrWhiteSpace($policyConfig.policyDescription))
  {
    $policyConfig.policyDescription = "Pure Storage vVol Storage Policy created from PowerCLI"
  }
  if ($null -eq $server)
  {
    $policy = @()
    foreach ($vCenter in $global:DefaultVIServers)
    {
      $policy += New-SpbmStoragePolicy -Name $policyConfig.policyName -Description $policyConfig.policyDescription -AnyOfRuleSets $ruleSet -Server $vCenter
    }
  }
  else {
    $policy = New-SpbmStoragePolicy -Name $policyConfig.policyName -Description $policyConfig.policyDescription -AnyOfRuleSets $ruleSet -Server $server
    }
    return $policy
}
function Set-PfavVolStoragePolicy {
  <#
  .SYNOPSIS
    Creates a new FlashArray vVol Storage Policy
  .DESCRIPTION
    Creates a new FlashArray vVol Storage Policy with specified capabilities
  .INPUTS
    Capabilities
  .OUTPUTS
    New storage policy
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/22/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ New-PfavVolStoragePolicy -policyName

    Creates a new vVol policy with the specified name and default description. The only capability is ensuring it is a FlashArray policy.
  .EXAMPLE
    PS C:\ $policyConfig = New-PfavVolStoragePolicy -generateDefaultPolicyConfig

    Generates a new FlashArray vVol policy configuration object. You can then populate the properties.
  .EXAMPLE
    PS C:\ New-PfavVolStoragePolicy -policyConfig $policyConfig

    Passes in a FlashArray vVol storage policy configuration object (FlashArrayvVolPolicyConfig) and creates a new vVol storage policy with specified capabilities
  .EXAMPLE
    PS C:\ New-PfavVolStoragePolicy -policyName pure-vvolRep -policyDescription "Replication policy for FlashArray vVol VMs" -replicationEnabled $true -replicationInterval (New-TimeSpan -Hours 1) -replicationRetentionShort (New-TimeSpan -Hours 24) -replicationConcurrency 2 -consistencyGroupName purePG

    Creates a replication type vVol storage policy. Ensures VMs are replicated once an hour, and each point in time is kept for 1 day. It also ensures that the VM is replicated to at least 2 target arrays in a consistency group called purePG.

    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

  [CmdletBinding(DefaultParameterSetName='Manual')]
  Param(

        [Parameter(Position=0,ParameterSetName='Config',mandatory=$true,ValueFromPipeline=$True)]
        [FlashArrayvVolPolicyConfig]$policyConfig,

        [ValidateScript({
          $policies = Get-PfavVolStoragePolicy
          if ($policies.id.Contains($_.id))
          {
            $true
          }
          else {
            throw "This is not a Pure Storage FlashArray vVol policy"
          }
        })]
        [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
        [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$policy,

        [Parameter(Position=2,ParameterSetName='Manual')]
        [String]$policyName,

        [Parameter(Position=3,ParameterSetName='Manual')]
        [String]$policyDescription,

        [Parameter(Position=4,ParameterSetName='Manual')]
        [Nullable[boolean]]$replicationEnabled,

        [Parameter(Position=5,ParameterSetName='Manual')]
        [System.TimeSpan]$replicationInterval = 0,

        [Parameter(Position=6,ParameterSetName='Manual')]
        [System.TimeSpan]$replicationRetentionShort = 0,

        [Parameter(Position=7,ParameterSetName='Manual')]
        [int]$replicationConcurrency,

        [Parameter(Position=8,ParameterSetName='Manual')]
        [String]$consistencyGroupName,

        [Parameter(Position=9,ParameterSetName='Manual')]
        [Nullable[boolean]]$localSnapshotEnabled,

        [Parameter(Position=10,ParameterSetName='Manual')]
        [System.TimeSpan]$localSnapshotInterval = 0,

        [Parameter(Position=11,ParameterSetName='Manual')]
        [System.TimeSpan]$localSnapshotRetentionShort = 0
        
         <# Seems to be a bug in PowerCLI where array objects dont work in policies. Looking into this with VMware. Will hide for now (PowerCLI 12.0). 

        [Parameter(Position=8,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays, #>

        
         <# Seems to be a bug in PowerCLI where array objects dont work in policies. Looking into this with VMware. Will hide for now (PowerCLI 12.0). 

        [Parameter(Position=2,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays, #>
  )
  if ($null -eq $policyConfig)
  {
    $policyConfig = ([FlashArrayvVolPolicyConfig]::new($policyName, $policyDescription,<#$sourceFlashArrays,#>  $replicationEnabled, $replicationInterval, $replicationRetentionShort, $replicationConcurrency, $consistencyGroupName, <#$targetFlashArrays,#> $localSnapshotEnabled , $localSnapshotInterval, $localSnapshotRetentionShort))
  }
  $ruleSet = New-pfaRuleSetfromConfig -policyConfig $policyConfig
  return (Set-SpbmStoragePolicy -policy $policy -AnyOfRuleSets $ruleSet -Description $policyConfig.policyDescription -Name $policyConfig.policyName -Confirm:$false)
}


#Custom Classes
Class FlashArrayvVolPolicyConfig{
  static [String] $version = "1.1.0"
  static [String] $vendor = "Pure Storage"
  static [String] $objectName = "vVol Storage Policy Configuration"
  static [String] $model = "FlashArray"
  static [System.Boolean]$flasharray = $true
  [String]$policyName = ""
  [String]$policyDescription = ""
  [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays = $null 
  [Nullable[boolean]]$replicationEnabled = $null
  [System.TimeSpan]$replicationInterval = 0
  [System.TimeSpan]$replicationRetentionShort = 0
  [int]$replicationConcurrency = $null
  [ValidatePattern('(?# MUST BE 3+ digits, alphanumeric, also dashes or underscores can be in the middle)^[A-Za-z][a-zA-Z0-9\-_]+[a-zA-Z0-9]$|^$')]
  [String]$consistencyGroupName = ""
  [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays = $null 
  [Nullable[boolean]]$localSnapshotEnabled = $null
  [System.TimeSpan]$localSnapshotInterval = 0
  [System.TimeSpan]$localSnapshotRetentionShort = 0
  FlashArrayvVolPolicyConfig ([String]$policyName, [String]$policyDescription, [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays, [Nullable[boolean]]$replicationEnabled, [System.TimeSpan]$replicationInterval, [System.TimeSpan]$replicationRetentionShort, [int]$replicationConcurrency, [String]$consistencyGroupName, [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays, [Nullable[boolean]]$localSnapshotEnabled , [System.TimeSpan]$localSnapshotInterval, [System.TimeSpan]$localSnapshotRetentionShort)
  {
    #$this.sourceFlashArrays = $sourceFlashArrays
    $this.policyName = $policyName
    $this.policyDescription = $policyDescription
    $this.replicationEnabled = $replicationEnabled
    $this.replicationInterval = $replicationInterval
    $this.replicationRetentionShort = $replicationRetentionShort
    $this.replicationConcurrency = $replicationConcurrency
    $this.consistencyGroupName = $consistencyGroupName
    #$this.targetFlashArrays = $targetFlashArrays
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

#internal functions
function New-pfaRuleSetfromConfig {
   [CmdletBinding()]
  Param(
        [FlashArrayvVolPolicyConfig]$policyConfig
  )        
  $rules = @()
  $rules += New-SpbmRule `
                -Capability (Get-SpbmCapability -Name com.purestorage.storage.policy.FlashArrayGroup -Server $global:DefaultVIServer) `
                -Value $sourceFlashArrays.Name
   $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.policy.PureFlashArray -Server $global:DefaultVIServer) `
               -Value $true
   if ($null -ne $policyConfig.localSnapshotEnabled)
   {
     $rules += New-SpbmRule `
                 -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotPolicyCapable -Server $global:DefaultVIServer) `
                 -Value $policyConfig.localSnapshotEnabled
   }
   if ($policyConfig.localSnapshotInterval -ne 0)
   {
     $rules += New-SpbmRule `
                 -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotInterval -Server $global:DefaultVIServer) `
                 -Value $policyConfig.localSnapshotInterval
   }
   if ($policyConfig.localSnapshotRetentionShort -ne 0)
   {
     $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotRetention -Server $global:DefaultVIServer) `
               -Value $policyConfig.localSnapshotRetentionShort 
   }
    $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.ReplicationTarget -Server $global:DefaultVIServer) `
               -Value $targetFlashArrays.Name

   if ($null -ne $policyConfig.replicationEnabled)
   {
     $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationCapable -Server $global:DefaultVIServer) `
               -Value $policyConfig.replicationEnabled
   }
   if ($policyConfig.replicationInterval -ne 0)
   {
   $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationInterval -Server $global:DefaultVIServer) `
             -Value $policyConfig.replicationInterval
   }
   if ($policyConfig.replicationRetentionShort -ne 0)
   { 
             $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationRetention -Server $global:DefaultVIServer) `
             -Value $policyConfig.replicationRetentionShort 
   }
   if (!([string]::IsNullOrWhiteSpace($policyConfig.consistencyGroupName)))
   {
     $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.ReplicationConsistencyGroup -Server $global:DefaultVIServer) `
               -Value $policyConfig.consistencyGroupName
   }
   #create policy
   return New-SpbmRuleSet -AllOfRules $rules 
}
function get-vCenterfromStoragePolicy {
  [CmdletBinding()]
 Param(
  [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$policy
 )
 foreach ($vcenter in $global:DefaultVIServers)
 {
   $foundPolicy = Get-SpbmStoragePolicy -id $policy.id -Server $vcenter -ErrorAction SilentlyContinue
   if ($null -ne $foundPolicy)
   {
     return $vcenter
   }
 }
}

