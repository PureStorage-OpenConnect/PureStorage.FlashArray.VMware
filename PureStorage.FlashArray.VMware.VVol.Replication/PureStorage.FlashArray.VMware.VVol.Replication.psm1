function Get-PfaVvolReplicationGroup {
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
      Creation Date:  12/31/2020
      Purpose/Change: Function creation
    .EXAMPLE
      PS C:\ Get-PfaVvolReplicationGroup

      Returns all FlashArray vVol Replication Groups from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1    
      PS C:\ Get-PfaVvolReplicationGroup -faultDomain $fd

      Returns all FlashArray vVol Replication Groups from the specified fault domain (FlashArray) which has a vVol datastore that is mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfaVvolReplicationGroup -source

      Returns all source FlashArray vVol Replication Groups from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1    
      PS C:\ Get-PfaVvolReplicationGroup -faultDomain $fd -source

      Returns all FlashArray vVol source Replication Groups from the specified fault domain (FlashArray) which has a vVol datastore that is mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfaVvolReplicationGroup -target

      Returns all target FlashArray vVol Replication Groups from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfaVvolReplicationGroup -testFailover

      Returns all FlashArray vVol Replication Groups that are in the middle of a test failover from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfaVvolReplicationGroup -failedOver

      Returns all FlashArray vVol Replication Groups that have been failed over from all FlashArrays which have vVol datastores that are mounted in the connected vCenters 
    .EXAMPLE
      PS C:\ Get-PfaVvolReplicationGroup -VM (get-vm vVolVM-01)

      Returns the FlashArray vVol replication group for the virtual machine named vVolVM-01 
    .EXAMPLE
      PS C:\ Get-PfaVvolReplicationGroup -policy (Get-SpbmStoragePolicy vVolStoragePolicy)

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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,

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
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$Datastore,

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
            [VMware.VimAutomation.ViCore.Types.V1.Storage.StoragePolicy]$Policy,

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
            [VMware.VimAutomation.Storage.Types.V1.Spbm.Replication.SpbmFaultDomain]$FaultDomain
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
        $pureReplicationGroups = Get-SpbmReplicationGroup -VasaProvider $vp -ErrorAction SilentlyContinue
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
function Get-PfaVvolReplicationGroupPartner {
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
    PS C:\ $group = $vm |Get-PfaVvolReplicationGroup
    PS C:\ Get-PfaVvolReplicationGroupPartner -replicationGroup $group
    
    Finds the replication group a VM's storage is assigned to and returns the target replication group(s). 
  .EXAMPLE
    PS C:\ $vm = get-vm srmvm
    PS C:\ $group = $vm |Get-PfaVvolReplicationGroup
    PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1
    PS C:\ Get-PfaVvolReplicationGroupPartner -replicationGroup $group -faultDomain $fd
    
    Finds the replication group a VM's storage is assigned to and returns the target replication group for the specified fault domain (FlashArray). 
  .EXAMPLE
    PS C:\ $fd = Get-SpbmFaultDomain -Name flasharray-m50-1  
    PS C:\ $targetGroup = Get-PfaVvolReplicationGroup -target -faultDomain $fd
    PS C:\ Get-PfaVvolReplicationGroupPartner -replicationGroup $targetGroup
    
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
          [VMware.VimAutomation.Storage.Types.V1.Spbm.Replication.SpbmFaultDomain]$FaultDomain
  )
  if ($replicationGroup.state.ToString() -eq "Source")
  {
    $pureReplicationGroups = Get-PfaVvolReplicationGroup -testFailover -target -failedOver
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
    $pureReplicationGroups = Get-PfaVvolReplicationGroup -source
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
function Get-PfaVvolFaultDomain {
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
    Creation Date:  12/31/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Get-PfaVvolFaultDomain 

    Returns all Pure Storage FlashArray fault domains
  .EXAMPLE
    PS C:\ Get-PfaVvolFaultDomain -ArraySerial 7e914d96-c90a-31e0-a495-75e8b3c300cc

    Returns the FlashArray fault domain for the specified array serial number.
  .EXAMPLE
    PS C:\ Get-PfaVvolFaultDomain -ArrayName flasharray-m50-1

    Returns the FlashArray fault domain for the specified array name.
  .EXAMPLE
    PS C:\ $fa = new-pfaConnection -endpoint flasharray-m50-1 -ignoreCertificateError -DefaultArray
    PS C:\ Get-PfaVvolFaultDomain -FlashArray $fa

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
        [PurePowerShell.PureArray]$Flasharray,

        [Parameter(Position=1,ParameterSetName='Name')]
        [string]$ArrayName,

        [Parameter(Position=2,ParameterSetName='Serial')]
        [string]$ArraySerial
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
