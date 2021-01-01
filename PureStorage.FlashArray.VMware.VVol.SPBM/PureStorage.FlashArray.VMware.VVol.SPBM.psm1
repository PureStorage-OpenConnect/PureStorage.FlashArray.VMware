function Build-PfaVvolStoragePolicyConfig {
  <#
  .SYNOPSIS
    Returns a config object for specifed policy or creates a new configuration.
  .DESCRIPTION
    Returns a config object for specifed policy or creates a new configuration. You can then change the properties of the configuration object and create a new policy or update an existing one with the values with New-PfaVvolStoragePolicy or Edit-PfaVvolStoragePolicy
  .INPUTS
    Policy (optional)
  .OUTPUTS
    Storage policy configuration object
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  12/31/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Build-PfaVvolStoragePolicyConfig 

    Returns a new policy config with default settings.
  .EXAMPLE
    PS C:\ $policy = Get-PfaVvolStoragePolicy -PolicyName myvVolreplicationpolicy
    PS C:\ Build-PfavVolStoragePolicyConfig -Policy $policy

    Returns a policy config with the settings of an existing policy.

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
        [Parameter(Position=1,ValueFromPipeline=$True,ParameterSetName='Config')]
        [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$Policy
  )
  Begin {
    $policyConfigs = @()
    $pcliversion = (Get-Module VMware.PowerCLI -ListAvailable).version
    if (($pcliversion.Major -lt 12) -and ($pcliversion.Minor -lt 1))
    {
      throw "This cmdlet required PowerCLI 12.1 or later."
    }
  }
  Process {
    if ($null -eq $policy)
    {
      $policyName = "FlashArray vVol Policy " + (Get-Random -Minimum 1000 -Maximum 9999).ToString()
    }
    if ($null -ne $policy)
    {
      $policyName = $policy.Name
      $policyDescription = $Policy.description
      $localSnapshotEnabled = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.LocalSnapshotCapable"}
      if ($null -ne $localSnapshotEnabled)
      {
        $localSnapshotEnabled = $localSnapshotEnabled.Value
      }
      $SnapshotInterval = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.LocalSnapshotInterval"}
      if ($null -ne $SnapshotInterval)
      {
        $LocalSnapshotInterval = $SnapshotInterval.Value
      }  
      $LocalSnapshotRetention = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.LocalSnapshotRetention"}
      if ($null -ne $LocalSnapshotRetention)
      {
        $LocalSnapshotRetentionShort = $LocalSnapshotRetention.Value
      } 
      $remoteReplicationEnabled = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.remoteReplicationCapable"}
      if ($null -ne $remoteReplicationEnabled)
      {
        $ReplicationEnabled = $remoteReplicationEnabled.Value
      }
      $remoteReplicationRetention = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.ReplicationConcurrency"}
      if ($null -ne $remoteReplicationRetention)
      {
        $ReplicationConcurrency = $remoteReplicationRetention.Value
      }   
      $remoteReplicationInterval = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.remoteReplicationInterval"}
      if ($null -ne $remoteReplicationInterval)
      {
        $ReplicationInterval = $remoteReplicationInterval.Value
      }  
      $remoteReplicationRetention = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.remoteReplicationRetention"}
      if ($null -ne $remoteReplicationRetention)
      {
        $replicationRetentionShort = $remoteReplicationRetention.Value
      } 
      $consistencyGroup = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.ReplicationConsistencyGroup"}
      if ($null -ne $consistencyGroup)
      {
        $consistencyGroupName = $consistencyGroup.Value
      } 
      $sourceFlashArrays = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.policy.FlashArrayGroup"}
      if ($null -ne $sourceFlashArrays)
      {
        $foundArrays = @()
        foreach ($sourceArray in $sourceFlashArrays.Value) 
        {
          $VvolArray = $null
          $VvolArray = Get-PfaVvolStorageArray -ArrayName $sourceArray
          if ($null -ne $VvolArray)
          {
            $foundArrays += $VvolArray
          }
          else 
          {
            throw "Invalid array name found in policy $($sourceArray). Please ensure the array name is correct and/or it has a registered vasa provider in one or more of the connected vCenters."
          }
        }
        $sourceFlashArrays = $foundArrays
      } 
      $targetFlashArrays = $policy.AnyOfRuleSets.AllofRules |where-object {$_.Capability.Name -eq "com.purestorage.storage.replication.ReplicationTarget"}
      if ($null -ne $targetFlashArrays)
      {
        $foundArrays = @()
        foreach ($targetArray in $targetFlashArrays.Value) 
        {
          $VvolArray = $null
          $VvolArray = Get-PfaVvolStorageArray -ArrayName $targetArray
          if ($null -ne $VvolArray)
          {
            $foundArrays += $VvolArray
          }
          else 
          {
            throw "Invalid array name found in policy $($targetArray). Please ensure the array name is correct and/or it has a registered vasa provider in one or more of the connected vCenters."
          }
        }
        $targetFlashArrays = $foundArrays
      } 
    }
    if ($null -eq $ReplicationInterval)
    {
      [System.TimeSpan]$ReplicationInterval = 0
    }
    if ($null -eq $ReplicationRetentionShort)
    {
      [System.TimeSpan]$ReplicationRetentionShort = 0
    }
    if ($null -eq $LocalSnapshotInterval)
    {
      [System.TimeSpan]$LocalSnapshotInterval = 0
    }
    if ($null -eq $localSnapshotRetentionShort)
    {
      [System.TimeSpan]$localSnapshotRetentionShort = 0
    }
    $policyConfigs += ([FlashArrayvVolPolicyConfig]::new($policyName, $policyDescription, $sourceFlashArrays, $replicationEnabled, $replicationInterval, $replicationRetentionShort, $replicationConcurrency, $consistencyGroupName, $targetFlashArrays, $localSnapshotEnabled , $localSnapshotInterval, $localSnapshotRetentionShort, $policy))
  }
  End {
    if ($policyConfigs.count -eq 1)
    {
      return $policyConfigs[0]
    }
    else {
      return $policyConfigs
    }
  }
}
function Get-PfaVvolStoragePolicy {
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
    Creation Date:  12/31/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Get-PfaVvolStoragePolicy 

    Returns all Pure Storage FlashArray-based storage policies
  .EXAMPLE
    PS C:\ Get-PfaVvolStoragePolicy -replication

    Returns all replication-enabled Pure Storage FlashArray-based storage policies
  .EXAMPLE
    PS C:\ Get-PfaVvolStoragePolicy -server $global:DefaultVIServer

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
        [Switch]$Replication,

        [Parameter(Position=1)]
        [String]$PolicyName,

        [Parameter(Position=2)]
        [VMware.VimAutomation.ViCore.Types.V1.VIServer]$Server
  )
  $pcliversion = (Get-Module VMware.PowerCLI -ListAvailable).version
  if (($pcliversion.Major -lt 12) -and ($pcliversion.Minor -lt 1))
  {
    throw "This cmdlet required PowerCLI 12.1 or later."
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
  if (!([string]::IsNullOrWhiteSpace($PolicyName)))
   {
    $purePolicies = $purePolicies |where-object {$_.Name -eq $PolicyName}
    if ($purePolicies.count -eq 0)
    {
      throw "No Pure Storage FlashArray vVol policies found with the name $($PolicyName)"
    }
  }
  return $purePolicies
}
function New-PfaVvolStoragePolicy {
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
    Creation Date:  12/31/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ New-PfaVvolStoragePolicy

    Creates the default SPBM policy that indicates a VM should be on a FlashArray using vVols. Default generated name and description.
  .EXAMPLE
    PS C:\ New-PfaVvolStoragePolicy -PolicyName myGreatPolicy

    Creates a SPBM policy with the specified name that indicates a VM should be on a FlashArray using vVols. Default generated description.
  .EXAMPLE
    PS C:\ New-PfaVvolStoragePolicy -PolicyName myGreatReplicationPolicy -ReplicationInterval (New-TimeSpan -Minutes 5) -ReplicationEnabled $true -ReplicationConcurrency 2

    Creates a replication-type SPBM policy with the specified name that indicates a VM should be on a FlashArray using vVols, replicated every 5 minutes to at least two other FlashArrays. Default generated description.
  .EXAMPLE
    PS C:\ $policy = Get-PfaVvolStoragePolicy -PolicyName myvVolreplicationpolicy
    PS C:\ $policyConfig = Build-PfavVolStoragePolicyConfig -Policy $policy
    PS C:\ $policyConfig.policyName = "MyEvenGreaterReplicationPolicy"
    PS C:\ $policyConfig.replicationInterval = New-TimeSpan -Minutes 10
    PS C:\ Edit-PfaVvolStoragePolicy -PolicyConfig $policyConfig

    Creates a new policy with the identical configuration of a previously created policy but with a different name and replication interval.

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
        [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True,ParameterSetName='Config')]
        [FlashArrayvVolPolicyConfig]$PolicyConfig,

        [Parameter(Position=1)]
        [VMware.VimAutomation.ViCore.Types.V1.VIServer[]]$Server,

        [Parameter(Position=2,ParameterSetName='Manual')]
        [String]$PolicyName,

        [Parameter(Position=3,ParameterSetName='Manual')]
        [String]$PolicyDescription,

        [Parameter(Position=4,ParameterSetName='Manual')]
        [Nullable[boolean]]$ReplicationEnabled,

        [Parameter(Position=5,ParameterSetName='Manual')]
        [System.TimeSpan]$ReplicationInterval = 0,

        [Parameter(Position=6,ParameterSetName='Manual')]
        [System.TimeSpan]$ReplicationRetentionShort = 0,

        [Parameter(Position=7,ParameterSetName='Manual')]
        [int]$ReplicationConcurrency,

        [Parameter(Position=8,ParameterSetName='Manual')]
        [String]$ConsistencyGroupName,

        [Parameter(Position=9,ParameterSetName='Manual')]
        [Nullable[boolean]]$LocalSnapshotEnabled,

        [Parameter(Position=10,ParameterSetName='Manual')]
        [System.TimeSpan]$LocalSnapshotInterval = 0,

        [Parameter(Position=11,ParameterSetName='Manual')]
        [System.TimeSpan]$LocalSnapshotRetentionShort = 0,
        
        [Parameter(Position=12,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$TargetFlashArrays,

        [Parameter(Position=13,ParameterSetName='Manual')]
        [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$SourceFlashArrays
  )
  $pcliversion = (Get-Module VMware.PowerCLI -ListAvailable).version
  if (($pcliversion.Major -lt 12) -and ($pcliversion.Minor -lt 1))
  {
    throw "This cmdlet required PowerCLI 12.1 or later."
  }
  if ($server.count -eq 0)
  {
    $vCenters = $global:DefaultVIServers
  }
  else {
    $vCenters = $server
  }
  if ($null -eq $policyConfig)
  {
    if ([string]::IsNullOrWhiteSpace($policyName))
    {
      $policyName = "FlashArray vVol Policy " + (Get-Random -Minimum 1000 -Maximum 9999).ToString()
    }
    $policyConfig = ([FlashArrayvVolPolicyConfig]::new($policyName, $policyDescription,$sourceFlashArrays, $replicationEnabled, $replicationInterval, $replicationRetentionShort, $replicationConcurrency, $consistencyGroupName, $targetFlashArrays, $localSnapshotEnabled , $localSnapshotInterval, $localSnapshotRetentionShort, $null))
  }
  $vCenterExists = @()
  foreach ($vCenter in $vCenters)
  {
    $checkExisting = $null
    $checkExisting = Get-SpbmStoragePolicy -Name $policyConfig.policyName -Server $vCenter -ErrorAction SilentlyContinue
    if ($null -ne $checkExisting)
    {
      $vCenterExists += $vCenter.name
    }
  }
  if ($vCenterExists.count -gt 0)
  {
    throw "A storage policy with the name of $($policyConfig.policyName) already exists on the following vCenter(s):`n `n$($vCenterExists -join ",")`n `n Please choose a unique name."
  }
  $policy = @()
  foreach ($vCenter in $vCenters)
  {
    if ([string]::IsNullOrWhiteSpace($policyConfig.policyDescription))
    {
      $policyConfig.policyDescription = "Pure Storage FlashArray vVol storage policy default description"
    }
    $checkforPure = $null
    $checkforPure = Get-SpbmCapability -Server $vCenter |where-object {$_.name -like "com.purestorage*"}
    if ($null -eq $checkforPure)
    {
      Write-Error "This vCenter does not have any Pure VASA providers registered and therefore no policy can be created. Skipping vCenter $($vCenter.Name)..."
    }
    else {
      $ruleSet = New-pfaRuleSetfromConfig -policyConfig $policyConfig -Server $vCenter
      Write-Host "Creating policy $($policyConfig.policyName) on vCenter $($vCenter.Name)..."
      $policy += New-SpbmStoragePolicy -Name $policyConfig.policyName -Description $policyConfig.policyDescription -AnyOfRuleSets $ruleSet -Server $vCenter
    }
  }
  if ($policy.count -eq 1)
  {
    return $policy[0]
  }
  else {
    return $policy
  }
}
function Edit-PfaVvolStoragePolicy {
  <#
  .SYNOPSIS
    Updates/adds one or more capabilities to a FlashArray vVol Storage Policy
  .DESCRIPTION
    Updates/adds one or more capabilities to a FlashArray vVol Storage Policy by taking in a changed configuration from Build-PfavVolStoragePolicyConfig
  .INPUTS
    SPBM policy configuration object
  .OUTPUTS
    Updated storage policy
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  12/31/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ $policyConfig = Build-PfavVolStoragePolicyConfig -PolicyName myvVolreplicationpolicy
    PS C:\ $policyConfig.replicationInterval = New-TimeSpan -Hours 2
    PS C:\ Edit-PfaVvolStoragePolicy -PolicyConfig $policyConfig

    Updates the replication interval for the SPBM policy called myvVolreplicationpolicy to 2 hours.

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
        [FlashArrayvVolPolicyConfig]$PolicyConfig
  )
  $pcliversion = (Get-Module VMware.PowerCLI -ListAvailable).version
  if (($pcliversion.Major -lt 12) -and ($pcliversion.Minor -lt 1))
  {
    throw "This cmdlet required PowerCLI 12.1 or later."
  }
  if ($null -eq $policyConfig.policy)
  {
    throw "No existing policy is associated with this policy configuration. Use the New-PfaVvolStoragePolicy instead to create a new policy."
  }
  $vCenter = get-vCenterfromStoragePolicy -policy $policyConfig.policy
  $ruleSet = New-pfaRuleSetfromConfig -policyConfig $policyConfig -Server $vCenter
  return (Set-SpbmStoragePolicy -policy $policyConfig.policy -AnyOfRuleSets $ruleSet -Description $policyConfig.policyDescription -Name $policyConfig.policyName -Confirm:$false)
}
function Set-PfaVvolVmStoragePolicy {
  <#
  .SYNOPSIS
    Sets an SPBM policy on a VM or set of VMs. 
  .DESCRIPTION
    Sets an SPBM policy on a VM or set of VMs. Optionally can assign a replication group
  .INPUTS
    VM(s), an SPBM policy, a replication group option.
  .OUTPUTS
    VM components
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  12/31/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ $policy = Get-PfaVvolStoragePolicy -PolicyName myvVolpolicy
    PS C:\ $vm = get-vm myVM
    PS C:\ Set-PfaVvolVmStoragePolicy -vm $vm -Policy $policy

    Assigns a policy to a VM and all of its disks.
  .EXAMPLE
    PS C:\ $policy = Get-PfaVvolStoragePolicy -PolicyName myvVolpolicy
    PS C:\ $vm = get-vm myVM*
    PS C:\ Set-PfaVvolVmStoragePolicy -vm $vm -Policy $policy

    Assigns a policy to all VMs with the specified prefix and all of their disks.
  .EXAMPLE
    PS C:\ $policy = Get-PfaVvolStoragePolicy -PolicyName myvVolreplicationpolicy
    PS C:\ $group = Get-PfaVvolReplicationGroup -policy $policy
    PS C:\ $vm = get-vm myVM
    PS C:\ Set-PfaVvolVmStoragePolicy -vm $vm -Policy $policy -ReplicationGroup $group[0]

     Assigns a policy to a VM and all of its disks with a compatible replication group.
  .EXAMPLE
    PS C:\ $policy = Get-PfaVvolStoragePolicy -PolicyName myvVolreplicationpolicy
    PS C:\ $vm = get-vm myVM
    PS C:\ Set-PfaVvolVmStoragePolicy -vm $vm -Policy $policy -AutoReplicationGroup

    Assigns a policy to a VM and all of its disks with an automatically created new compatible replication group.

    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

  [CmdletBinding(DefaultParameterSetName="None")]
  Param(
    [Parameter(Position=0,mandatory=$true,ParameterSetName="Manual")]
    [Parameter(Position=0,mandatory=$true,ParameterSetName="Auto")]
    [Parameter(Position=0,mandatory=$true,ParameterSetName="None")]
    [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VM,

    [Parameter(Position=1,ParameterSetName="Manual",mandatory=$true)]
    [VMware.VimAutomation.ViCore.Types.V1.Storage.ReplicationGroup]$ReplicationGroup,

    [Parameter(Position=2,ParameterSetName="Auto",mandatory=$true)]
    [Switch]$AutoReplicationGroup,

    [Parameter(Position=3,mandatory=$true,ParameterSetName="Manual")]
    [Parameter(Position=3,mandatory=$true,ParameterSetName="Auto")]
    [Parameter(Position=3,mandatory=$true,ParameterSetName="None")]
    [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$Policy
  )
  $vCenter = $vm.ExtensionData.client.ServiceUrl |Select-Object -Unique
  if ($vCenter.count -gt 1)
  {
    throw "It is only supported to pass in VMs in the same vCenter at once. Please reduce the list of VMs to VMs in the same vCenter."
  }
  $vc = (get-vCenterfromStoragePolicy -policy $Policy).ServiceUri.AbsoluteUri
  if ($vc -ne $vCenter)
  {
    throw "The entered policy must be from the same vCenter as the VMs."
  }
  $datastores = $vm |Get-Datastore
  $compatibleDatastores = $Policy | Get-SpbmCompatibleStorage
  if ($compatibleDatastores.count -eq 0)
  {
    throw "No compatible datastores found for the specified policy."
  }
  $nonCompatibleDatastores = @()
  foreach ($datastore in $datastores) {
    if (($compatibleDatastores.extensiondata.info.url).contains($datastore.extensiondata.info.url) -ne $true)
    {
      $nonCompatibleDatastores += $datastore
    }
  }
  if ($nonCompatibleDatastores.count -gt 0)
  {
    $nameList = $nonCompatibleDatastores.name -join(", ")
    throw "Some of the specified VM(s) in the list are found using one or more datastores that are not compatible with the specified policy. Please relocate the VMs or choose a different policy. The following datastores were found in-use and not compatible: `r`n $($nameList)"
  }
  if (($null -ne $replicationGroup) -and ($datastores.count -gt 1))
  {
    throw "The VMs are on multiple datastores--they must be on the same vVol datastore when using a replication-type policy."
  }
  $rules = $policy.AnyOfRuleSets.Allofrules.capability |Where-Object {$_.Name -like "*com.purestorage.storage.replication*"}
  if ($null -ne $rules)
  {
    if (($null -eq $replicationGroup) -and ($AutoReplicationGroup -eq $false))
    {
      throw "This is a Pure Storage replication-based policy and you must pass in a valid replication group."
    }
    elseif ($AutoReplicationGroup -eq $false) {
      $replicationGroups = Get-SpbmReplicationGroup -Datastore $datastores -StoragePolicy $policy
      if (($replicationGroups.id -contains $replicationGroup.id) -eq $false)
      {
        throw "Specified replication group is not valid for the policy. Please use Get-PfaVvolReplication group with the policy to find compatible groups."
      }
    }
  }
  else {
    if (($null -ne $replicationGroup) -or ($AutoReplicationGroup -eq $true))
    {
      throw "A replication group was specified which is not needed as the specified policy is not a replication-type policy."
    }
  }
  $VmConfig = ($vm |Get-HardDisk),$vm |Get-SpbmEntityConfiguration
  if ($AutoReplicationGroup -eq $true)
  {
    $FirstVMConfig = ($vm[0] |Get-HardDisk),$vm[0] |Get-SpbmEntityConfiguration
    $FirstVMConfig = Set-SpbmEntityConfiguration -Configuration $FirstVMConfig -StoragePolicy $Policy -AutoReplicationGroup
    if ($VmConfig.count -gt 1)
    {
      $VmConfig =  Set-SpbmEntityConfiguration -Configuration $VmConfig -StoragePolicy $Policy -ReplicationGroup $FirstVMConfig[0].replicationGroup
    }
  }
  elseif ($null -eq $replicationGroup)
  {
    $VmConfig = Set-SpbmEntityConfiguration -Configuration $VmConfig -StoragePolicy $Policy
  }
  else {
    $VmConfig =  Set-SpbmEntityConfiguration -Configuration $VmConfig -StoragePolicy $Policy -ReplicationGroup $replicationGroup
  }
  return $VmConfig
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
  [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$policy
  FlashArrayvVolPolicyConfig ([String]$policyName, [String]$policyDescription, [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$sourceFlashArrays, [Nullable[boolean]]$replicationEnabled, [System.TimeSpan]$replicationInterval, [System.TimeSpan]$replicationRetentionShort, [int]$replicationConcurrency, [String]$consistencyGroupName, [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray[]]$targetFlashArrays, [Nullable[boolean]]$localSnapshotEnabled , [System.TimeSpan]$localSnapshotInterval, [System.TimeSpan]$localSnapshotRetentionShort, [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$policy)
  {
    $this.sourceFlashArrays = $sourceFlashArrays
    $this.policyName = $policyName
    $this.policyDescription = $policyDescription
    $this.replicationEnabled = $replicationEnabled
    $this.replicationInterval = $replicationInterval
    $this.replicationRetentionShort = $replicationRetentionShort
    $this.replicationConcurrency = $replicationConcurrency
    $this.consistencyGroupName = $consistencyGroupName
    $this.targetFlashArrays = $targetFlashArrays
    $this.localSnapshotEnabled = $localSnapshotEnabled
    $this.localSnapshotInterval = $localSnapshotInterval
    $this.localSnapshotRetentionShort = $localSnapshotRetentionShort
    $this.policy = $policy
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
        [FlashArrayvVolPolicyConfig]$policyConfig,

        [VMware.VimAutomation.ViCore.Types.V1.VIServer]$Server
  )   
  if ($null -eq $Server)  
  {
    $Server = $global:DefaultVIServer
  }   
  $rules = @()
  if ($policyConfig.sourceFlashArrays.count -ne 0)
   {
    $rules += New-SpbmRule `
                -Capability (Get-SpbmCapability -Name com.purestorage.storage.policy.FlashArrayGroup -Server $Server) `
                -Value $policyConfig.sourceFlashArrays.Name
   }
   $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.policy.PureFlashArray -Server $Server) `
               -Value $true
   if ($null -ne $policyConfig.localSnapshotEnabled)
   {
     $rules += New-SpbmRule `
                 -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotPolicyCapable -Server $Server) `
                 -Value $policyConfig.localSnapshotEnabled
   }
   if ($policyConfig.localSnapshotInterval -ne 0)
   {
     $rules += New-SpbmRule `
                 -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotInterval -Server $Server) `
                 -Value $policyConfig.localSnapshotInterval
   }
   if ($policyConfig.localSnapshotRetentionShort -ne 0)
   {
     $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.LocalSnapshotRetention -Server $Server) `
               -Value $policyConfig.localSnapshotRetentionShort 
   }
   if ($policyConfig.targetFlashArrays.count -ne 0)
   {
    $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.ReplicationTarget -Server $Server) `
               -Value $policyConfig.targetFlashArrays.Name
   }
   if ($null -ne $policyConfig.replicationEnabled)
   {
     $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationCapable -Server $Server) `
               -Value $policyConfig.replicationEnabled
   }
   if ($policyConfig.replicationInterval -ne 0)
   {
   $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationInterval -Server $Server) `
             -Value $policyConfig.replicationInterval
   }
   if ($policyConfig.replicationRetentionShort -ne 0)
   { 
             $rules += New-SpbmRule `
             -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.RemoteReplicationRetention -Server $Server) `
             -Value $policyConfig.replicationRetentionShort 
   }
   if (!([string]::IsNullOrWhiteSpace($policyConfig.consistencyGroupName)))
   {
     $rules += New-SpbmRule `
               -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.ReplicationConsistencyGroup -Server $Server) `
               -Value $policyConfig.consistencyGroupName
   }
   if (($null -ne $policyConfig.replicationConcurrency) -and ($policyConfig.replicationConcurrency -ne 0))
   {
     $rules += New-SpbmRule `
                 -Capability (Get-SpbmCapability -Name com.purestorage.storage.replication.replicationConcurrency -Server $Server) `
                 -Value $policyConfig.replicationConcurrency
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

