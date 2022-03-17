import-module VMware.VimAutomation.Storage
$ErrorActionPreference = "stop"
function Update-PfaVvolVmVolumeGroup {
    <#
    .SYNOPSIS
      Updates the volume group on a FlashArray for a VVol-based VM.
    .DESCRIPTION
      Takes in a VM and a FlashArray connection. A volume group will be created if it does not exist, if it does, the name will be updated if inaccurate. Any volumes for the given VM will be put into that group.
    .INPUTS
      FlashArray connection, a virtual machine.
    .OUTPUTS
      Returns the FlashArray volume names of the input VM.
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  03/17/2022
      Purpose/Change: 1.19 support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\  Update-PfaVvolVmVolumeGroup -vm (get-vm myVM)
      
      Updated the volume group for a virtual machine on the default FlashArray
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\  Update-PfaVvolVmVolumeGroup -datastore (get-datastore myvVolDS)
      
      Updated all of the volume groups on a given vVol datastore
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\  Update-PfaVvolVmVolumeGroup -vm (get-cluster myCluster | get-vm)
      
      Updated all of the volume groups for the Pure Storage vVol VMs in the specified cluster

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
            [Parameter(ParameterSetName='VM',Position=0,ValueFromPipeline=$True,mandatory=$true)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$Vm,

            [Parameter(ParameterSetName='Datastore',Position=1,ValueFromPipeline=$True,mandatory=$true)]
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

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$Flasharray,

            [Parameter(ParameterSetName='VM',Position=3)]
            [String]$VolumeGroupName
    )
    $volumeFinalNames = @()
    if ($null -ne $datastore)
    {
        if ($null -eq $flasharray)
        {
            $fa = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
        }
        else 
        {
            $fa = get-PfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
        }
        $vms = $datastore |get-vm
    }
    elseif ($null -ne $vm) {
        $vms = $vm
    }
    foreach ($vm in $vms)
    {
        $vmDatastores = $vm |Get-Datastore
        foreach ($vmDatastore in $vmDatastores)
        {
            if ($vmDatastore.Type -ne "VVOL")
            {
                continue 
            }
            else 
            {
                if ($null -eq $flasharray)
                {
                    $fa = get-PfaConnectionOfDatastore -datastore $vmDatastore -ErrorAction Stop
                }
                else 
                {
                    $fa = get-PfaConnectionOfDatastore -datastore $vmDatastore -flasharrays $flasharray -ErrorAction Stop
                }
                $vmId = $vm.ExtensionData.Config.InstanceUuid   
                $customVgroupName = $false
                if ([string]::IsNullOrEmpty($volumeGroupName))
                {
                  $volumeGroupName = $vm.Name
                }
                else {
                  $customVgroupName = $true
                }
                if ($volumeGroupName -notmatch "^[a-zA-Z0-9\-]+$")
                {
                    $volumeGroupName = $volumeGroupName -replace "[^\w\-]", ""
                    $volumeGroupName = $volumeGroupName -replace "[_]", ""
                    $volumeGroupName = $volumeGroupName -replace " ", ""
                }
                if ($customVgroupName -eq $false)
                {
                  $vGroupRand = '{0:X}' -f (get-random -Minimum 286331153 -max 4294967295)
                  $volumeGroupName = "vvol-$($volumeGroupName)-$($vGroupRand)-vg"
                }
                $vVolInfos = $null
                $vVolInfos = Get-PfaVvolVol -vm $vm[0] -flasharray $fa
                if (($vVolInfos.VolumeGroup |Select-Object -Unique).count -gt 1)
                {
                    $vgroupsUnique = $vvolInfos.VolumeGroup |Select-Object -Unique
                    Write-Warning -Message "Skipping the VM $($VM.name) as it is spread across more than one volume group: `r`n $($vgroupsUnique) "
                    continue
                }
                elseif (($vVolInfos.VolumeGroup |Select-Object -Unique).count -eq 0) 
                {
                  New-PfaRestOperation -resourceType "vgroup/$($volumeGroupName)" -restOperationType POST -flasharray $fa -SkipCertificateCheck -ErrorAction stop |Out-Null
                }
                elseif (($vVolInfos.VolumeGroup |Select-Object -Unique).count -eq 1) 
                {
                  if ($volumeGroupName -ne ($vVolInfos.VolumeGroup |Select-Object -Unique))
                  {
                    $vGroup = $vVolInfos.VolumeGroup |Select-Object -Unique
                    New-PfaRestOperation -resourceType "vgroup/$($vGroup)" -restOperationType PUT -jsonBody "{`"name`":`"$($volumeGroupName)`"}" -flasharray $fa -SkipCertificateCheck |Out-Null
                  }
                }
                $vVolInfos = $null
                $vVolInfos = Get-PfaVvolVol -vm $vm[0]  -flasharray $fa
                foreach ($vVolInfo in $vVolInfos) 
                {
                  if (($vVolInfo.VolumeGroup -ne $volumeGroupName) -and ($null -ne $vVolInfo.VolumeGroup))
                  {
                    New-PfaRestOperation -resourceType "volume/$($vVolInfo.VolumeGroup)/$($vVolInfo.Volume)" -restOperationType PUT -flasharray $fa -SkipCertificateCheck -jsonBody "{`"container`":`"$($volumeGroupName)`"}" |Out-Null
                  }
                  elseif ($null -eq $vVolInfo.VolumeGroup) 
                  {
                    New-PfaRestOperation -resourceType "volume/$($vVolInfo.Volume)" -restOperationType PUT -flasharray $fa -SkipCertificateCheck -jsonBody "{`"container`":`"$($volumeGroupName)`"}" |Out-Null
                  }
                }
                if ($flasharray.apiversion.split(".")[1] -gt 18)
                {
                  $volumesAfterMove = (New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&namespace=vasa-integration.purestorage.com&filter=value=`'$($vmId)`'" -flasharray $fa -SkipCertificateCheck).Name |Select-Object -Unique
                }
                else
                {
                  $volumesAfterMove = (New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&filter=value=`'$($vmId)`'" -flasharray $fa -SkipCertificateCheck).Name |Select-Object -Unique
                }
                foreach ($volumeAfterMove in $volumesAfterMove) {
                  $volumeFinalNames += $volumeAfterMove
                }
            }
        }
    }
    return $volumeFinalNames
}
function Get-PfaVvolVol{
      <#
    .SYNOPSIS
      Gets the vVol volumes of entered VM
    .DESCRIPTION
      Takes in a virtual machine
    .INPUTS
      Virtual machine (get-vm)
    .OUTPUTS
      Returns the FA volume and volume group name(s)
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  03/15/2022
      Purpose/Change: Updated for new connection mgmt
    .EXAMPLE
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ Get-PfaVvolVol -vm (get-vm myVM) -flasharray $fa

      Returns the relevant vVol volumes on the array and their corresponding volume group
      
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$Vm,

        [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
        [PurePowerShell.PureArray]$Flasharray
    )
    $arraySerial = (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
    $datastore = $vm |Get-Datastore |Where-Object {$_.Type -eq 'VVOL'} |Where-Object {$_.ExtensionData.Info.VvolDS.StorageArray[0].uuid.Substring(16) -eq $arraySerial}
    if ($null -eq $datastore)
    {
      throw "There are no volumes on this FlashArray $($flasharray.EndPoint) for entered VM $($vm.name)"
    }
    else 
    {
      $vmId = $vm.ExtensionData.Config.InstanceUuid   
      if ($flasharray.apiversion.split(".")[1] -gt 18)
      {
        $vVolVolumes = (New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&namespace=vasa-integration.purestorage.com&filter=value=`'$($vmId)`'" -flasharray $flasharray -SkipCertificateCheck).Name |Select-Object -Unique
      }
      else
      {
        $vVolVolumes = (New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&filter=value=`'$($vmId)`'" -flasharray $flasharray -SkipCertificateCheck).Name |Select-Object -Unique
      }
      $vVolInfos = @() 
      foreach ($vVolVolume in $vVolVolumes) 
      {
        $vVolInfo = New-Object -TypeName psobject 
        if (($vVolVolume.split("/")).count -gt 1)
        {
          $vVolInfo | Add-Member -MemberType NoteProperty -Name VolumeGroup -Value ($vVolVolume.split("/"))[0]
          $vVolInfo | Add-Member -MemberType NoteProperty -Name Volume -Value ($vVolVolume.split("/"))[1]
        }
        else {
          $vVolInfo | Add-Member -MemberType NoteProperty -Name VolumeGroup -Value $null
          $vVolInfo | Add-Member -MemberType NoteProperty -Name Volume -Value $vVolVolume
        }
        $vVolInfos += $vVolInfo
      }
    }
    return $vVolInfos
}
function Get-VvolUuidFromVmdk {
    <#
    .SYNOPSIS
      Gets the vVol UUID of a virtual disk
    .DESCRIPTION
      Takes in a virtual disk object
    .INPUTS
      Virtual disk object (get-harddisk).
    .OUTPUTS
      Returns the vVol UUID.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ get-vm myVM | get-harddisk | Get-VvolUuidFromVmdk

      Pass in one or more vVol hard disks and return the corresponding vVol UUIDs
      
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
            [Parameter(Position=0,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk[]]$Vmdk
    )
    Begin {
        $allUuids = @()
    }
    Process {
        foreach ($vmdkDisk in $vmdk)
        {
          if ($vmdkDisk.ExtensionData.Backing.backingObjectId -eq "")
          {
              throw "This is not a vVol-based hard disk."
          }
          if ((($vmdkDisk |Get-Datastore).ExtensionData.Info.vvolDS.storageArray.vendorId) -ne "PURE") {
              throw "This is not a Pure Storage FlashArray vVol disk"
          }
          $allUuids += $vmdkDisk.ExtensionData.Backing.backingObjectId
        }
    }
    End {
        return $allUuids
    }

}
function Get-PfaVolumeNameFromVvolUuid{
  <#
  .SYNOPSIS
    Connects to vCenter and FlashArray to return the FA volume that is a vVol virtual disk.
  .DESCRIPTION
    Takes in a vVol UUID to identify what volume it is on the FlashArray. If a vVol UUID is not specified it will ask you for a VM and then a VMDK and will find the UUID for you.
  .INPUTS
    FlashArray connection(s) and vVol UUID.
  .OUTPUTS
    Returns volume name.
  .NOTES
    Version:        2.1
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  12/24/2019
    Purpose/Change: Updated for new connection mgmt
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
    PS C:\ Get-PfaVolumeNameFromVvolUuid -vvolUUID (get-vm myVM | get-harddisk | Get-VvolUuidFromVmdk)

    Pass in one vVol UUID and return the corresponding FlashArray volume name
      
  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  #Import PowerCLI. Requires PowerCLI version 6.3 or later. Will fail here if PowerCLI cannot be installed
  #Will try to install PowerCLI with PowerShellGet if PowerCLI is not present.

  [CmdletBinding()]
  Param(
          [Parameter(Position=0,mandatory=$true)]
          [string]$VvolUUID,

          [Parameter(Position=1,ValueFromPipeline=$True)]
          [PurePowerShell.PureArray[]]$Flasharray
  )
  Begin {
      $ErrorActionPreference = "stop"
  }
  Process 
  {
      if ($null -eq $flasharray)
      {
        $flasharray = getAllFlashArrays 
      }
      foreach ($fa in $flasharray)
      {
          if ($flasharray.apiversion.split(".")[1] -gt 18)
          {
            $volumeTags = New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&namespace=vasa-integration.purestorage.com&filter=value=`'$($vvolUUID)`'" -flasharray $fa -SkipCertificateCheck
          }
          else
          {
            $volumeTags = New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&filter=value=`'$($vvolUUID)`'" -flasharray $fa -SkipCertificateCheck
          }
          $volumeName = $volumeTags |where-object {$_.key -eq "PURE_VVOL_ID"}
          if ($null -eq $volumeName)
          {
            $Global:CurrentFlashArray = $null
          }
          else {
            $Global:CurrentFlashArray = $fa
            break
          }
      }
  }
  End 
  {
      if ($null -ne $volumeName)
      {
          return $volumeName.name
      }
      else {
          throw "VVol not found on entered FlashArrays."
      }
  }
}
function Get-PfaSnapshotFromVvolVmdk {
    <#
    .SYNOPSIS
      Returns all of the FlashArray snapshot names of a given hard disk
    .DESCRIPTION
      Takes in a virtual disk object
    .INPUTS
      Virtual disk object (get-harddisk).
    .OUTPUTS
      Returns all specified snapshot names.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ get-vm myVM | get-harddisk | Get-PfaSnapshotFromVvolVmdk 

      Pass in one vVol hard disk and return the corresponding FlashArray snapshot name(s)
   
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
            [Parameter(Position=0,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$Vmdk,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$Flasharray
    )
    $datastore = $vmdk |get-datastore
    if ($null -eq $flasharray)
    {
        $fa = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-PfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $vvolUuid = Get-VvolUuidFromVmdk -vmdk $vmdk
    $faVolume = get-PfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid
    $volumeSnaps = New-PfaRestOperation -resourceType "volume/$($faVolume)" -restOperationType GET -queryFilter "?snap=true" -flasharray $fa -SkipCertificateCheck
    return $volumeSnaps.Name
}
function Copy-PfaVvolVmdkToNewVvolVmdk {
    <#
    .SYNOPSIS
      Takes an existing VVol-based virtual disk and creates a new VVol virtual disk from it.
    .DESCRIPTION
      Takes in a hard disk and creates a copy of it to a certain VM.
    .INPUTS
      FlashArray connection information, a virtual machine, and a virtual disk.
    .OUTPUTS
      Returns the new hard disk.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ get-vm myVM | Copy-PfaVvolVmdkToNewVvolVmdk -vmdk (get-vm sourceVM |get-harddisk)

      Copy a vVol hard disk and present it as a new vVol hard disk a different VM
   
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
            [Parameter(Position=0,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$TargetVm,

            [Parameter(Position=1,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$Vmdk,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$Flasharray
    )
    $datastore = $vmdk |get-datastore
    if ($null -eq $flasharray)
    {
        $fa = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-PfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $vvolUuid = Get-VvolUuidFromVmdk -vmdk $vmdk 
    $faVolume = get-PfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid 
    $WarningPreference = "silentlyContinue"
    $newHardDisk = New-HardDisk -Datastore $datastore -CapacityGB $vmdk.CapacityGB -VM $targetVm -ErrorAction Stop
    $WarningPreference = "Continue"
    $newVvolUuid = get-vvolUuidFromVmdk -vmdk $newHardDisk -ErrorAction Stop
    $newFaVolume = get-PfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $newVvolUuid -ErrorAction Stop
    New-PfaRestOperation -resourceType "volume/$($newFaVolume)" -restOperationType POST -flasharray $fa -jsonBody "{`"overwrite`":true,`"source`":`"$($faVolume)`"}" -SkipCertificateCheck -ErrorAction Stop |Out-Null
    return $newHardDisk
}
function Copy-PfaSnapshotToExistingVvolVmdk {
    <#
    .SYNOPSIS
      Takes an snapshot and creates a new VVol virtual disk from it.
    .DESCRIPTION
      Takes in a hard disk and creates a copy of it to a certain VM.
    .INPUTS
      FlashArray connection information, a virtual machine, and a virtual disk.
    .OUTPUTS
      Returns the new hard disk.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ $vm = get-vm testvm01
      PS C:\ Copy-PfaSnapshotToExistingVvolVmdk -vmdk ($vm |Get-HardDisk) -snapshotName "vvol-testvm01-F90FC8A6-vg/Data-1fe45e4a.1"

      Takes a snapshot and overwrites a vVol VMDK on the same array
   
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
            [string]$SnapshotName,

            [Parameter(Position=1,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$Vmdk,

            [Parameter(Position=4,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$Flasharray
    )
    $datastore = $vmdk |get-datastore
    if ($null -eq $flasharray)
    {
        $fa = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-PfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $vvolUuid = get-vvolUuidFromHardDisk -vmdk $vmdk 
    $faVolume = get-PfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid
    $snapshotSize = New-PfaRestOperation -resourceType "volume/$($snapshotName)" -restOperationType GET -queryFilter "?snap=true&space=true" -flasharray $fa -SkipCertificateCheck
    if ($vmdk.ExtensionData.capacityinBytes -ne $snapshotSize.size)
    {
      if ($vmdk.ExtensionData.capacityinBytes -lt $snapshotSize.size) 
      {
        $vmdk = Set-HardDisk -HardDisk $vmdk -CapacityKB ($snapshotSize.size / 1024) -Confirm:$false 
      }
      else 
      {
          throw "The target vVol hard disk is larger than the snapshot size and VMware does not allow hard disk shrinking."
      } 
    }
    New-PfaRestOperation -resourceType "volume/$($faVolume)" -restOperationType POST -flasharray $fa -jsonBody "{`"overwrite`":true,`"source`":`"$($snapshotName)`"}" -SkipCertificateCheck -ErrorAction Stop |Out-Null
    return ($datastore |Get-HardDisk |Where-Object {$_.FileName -eq $vmdk.Filename})
}
function Copy-PfaSnapshotToNewVvolVmdk {
    <#
    .SYNOPSIS
      Takes a snapshot and creates a new vVol virtual disk from it.
    .DESCRIPTION
      Takes a snapshot and creates a new vVol virtual disk from it.
    .INPUTS
      FlashArray connection information, a datastore, target VM, and a source snapshot
    .OUTPUTS
      Returns the hard disk.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ $vm = get-vm testvm01
      PS C:\ Copy-PfaSnapshotToNewVvolVmdk -targetVM $vm -snapshotName "vvol-testvm01-F90FC8A6-vg/Data-1fe45e4a.1"

      Takes a snapshot and overwrites a vVol VMDK on the same array
   
    *******Disclaimer:******************************************************
    This scripts are offered "as is" with no warranty.  While this 
    scripts is tested and working in my environment, it is recommended that you test 
    this script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding(DefaultParametersetname="FlashArray")]
    Param(
            [Parameter(Position=0,mandatory=$true)]
            [string]$SnapshotName,

            [Parameter(Position=1,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$TargetVm,

            [Parameter(ParameterSetName='FlashArray',Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$Flasharray,

            [Parameter(ParameterSetName='Datastore',Position=3,ValueFromPipeline=$True,mandatory=$true)]
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
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$Datastore
    )
    if (($null -eq $flasharray) -and ($null -ne $datastore))
    {
        $flasharray = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    elseif (($null -eq $flasharray) -and ($null -eq $datastore))
    {
        try {
          $flasharray = checkDefaultFlashArray
        }
        catch {
          throw "You must either pass in a FlashArray, a vVol datastore, or configure a default FlashArray connection."
        }
        $arrayID = (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
        $datastore = $targetVm| Get-VMHost | Get-Datastore |where-object {$_.Type -eq "VVOL"} |Where-Object {$_.ExtensionData.info.vvolDS.storageArray[0].uuid.substring(16) -eq $arrayID} |Select-Object -First 1
    }
    elseif (($null -ne $flasharray) -and ($null -eq $datastore))
    {
      $arrayID = (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
      $datastore = $targetVm| Get-VMHost | Get-Datastore |where-object {$_.Type -eq "VVOL"} |Where-Object {$_.ExtensionData.info.vvolDS.storageArray[0].uuid.substring(16) -eq $arrayID} |Select-Object -First 1
    }
    $snapshotSize = New-PfaRestOperation -resourceType "volume/$($snapshotName)" -restOperationType GET -queryFilter "?snap=true&space=true" -flasharray $flasharray -SkipCertificateCheck
    $WarningPreference = "silentlyContinue"
    $newHardDisk = New-HardDisk -Datastore $datastore -CapacityKB ($snapshotSize.size / 1024 ) -VM $targetVm 
    $WarningPreference = "Continue"
    $newVvolUuid = get-vvolUuidFromHardDisk -vmdk $newHardDisk 
    $newFaVolume = get-PfaVolumeNameFromVvolUuid -flasharray $flasharray -vvolUUID $newVvolUuid 
    New-PfaRestOperation -resourceType "volume/$($newFaVolume)" -restOperationType POST -flasharray $flasharray -jsonBody "{`"overwrite`":true,`"source`":`"$($snapshotName)`"}" -SkipCertificateCheck -ErrorAction Stop |Out-Null
    return $newHardDisk      
}
function Copy-PfaVvolVmdkToExistingVvolVmdk {
    <#
    .SYNOPSIS
      Takes an virtual disk and refreshes an existing VVol virtual disk from it.
    .DESCRIPTION
      Takes an virtual disk and refreshes an existing VVol virtual disk from it.
    .INPUTS
      FlashArray connection information, a source and target virtual disk.
    .OUTPUTS
      Returns the new hard disk.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ $disks = get-vm myVM | get-harddisk  
      PS C:\ Copy-PfaVvolVmdkToExistingVvolVmdk -sourceVmdk $disks[0] -targetVmdk $disks[1]

      Refreshes one disk of a VM to another disk of that VM.
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ $disksProd = get-vm prodVM | get-harddisk  
      PS C:\ $disksDev = get-vm devVM | get-harddisk  
      PS C:\ Copy-PfaVvolVmdkToExistingVvolVmdk -sourceVmdk $disksProd[1] -targetVmdk $disksDev[1]

      Refreshes the 2nd hard disk of a VM with the 2nd harddisk of a source VM

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
            [Parameter(Position=0,mandatory=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$SourceVmdk,

            [Parameter(Position=1,mandatory=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$TargetVmdk,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$Flasharray
    )
    $sourceDatastore = $sourceVmdk | Get-Datastore 
    $targetDatastore = $targetVmdk | Get-Datastore
    if ($targetDatastore.type -ne "VVOL")
    {
        throw "The target VMDK is not a VVol-based virtual disk."
    }
    if ($sourceDatastore.type -ne "VVOL")
    {
       throw "The source VMDK is not a VVol-based virtual disk."
    }
    if ($targetDatastore.ExtensionData.Info.VvolDS.StorageArray[0].VendorId -ne "PURE") {
      throw "The target VMDK is not on a Pure Storage VVol datastore"
    }
    if ($sourceDatastore.ExtensionData.Info.VvolDS.StorageArray[0].VendorId -ne "PURE") {
      throw "The source VMDK is not on a Pure Storage VVol datastore"
    }
    if ($null -eq $flasharray)
    {
        $targetFlasharray = get-PfaConnectionOfDatastore -datastore $targetDatastore -ErrorAction Stop
    }
    else 
    {
        $targetFlasharray = get-PfaConnectionOfDatastore -datastore $targetDatastore -flasharrays $flasharray -ErrorAction Stop
    } 
    if ($sourceDatastore.ExtensionData.info.vvolDS.storageArray[0].uuid -eq $targetDatastore.ExtensionData.info.vvolDS.storageArray[0].uuid)
    {
        $vvolUuid = get-vvolUuidFromHardDisk -vmdk $sourceVmdk 
        $sourceFaVolume = get-PfaVolumeNameFromVvolUuid -flasharray $targetFlasharray -vvolUUID $vvolUuid 
        $vvolUuid = get-vvolUuidFromHardDisk -vmdk $targetVmdk 
        $targetFaVolume = get-PfaVolumeNameFromVvolUuid -flasharray $targetFlasharray -vvolUUID $vvolUuid
        if ($targetVmdk.CapacityKB -ne $sourceVmdk.CapacityKB)
        {
          if ($targetVmdk.CapacityKB -lt $sourceVmdk.CapacityKB) 
          {
            $targetVmdk = Set-HardDisk -HardDisk $targetVmdk -CapacityKB $sourceVmdk.CapacityKB -Confirm:$false 
          }
          else {
            throw "The target VVol hard disk is larger than the snapshot size and VMware does not allow hard disk shrinking."
          }
        }
        New-PfaRestOperation -resourceType "volume/$($targetFaVolume)" -restOperationType POST -flasharray $targetFlasharray -jsonBody "{`"overwrite`":true,`"source`":`"$($sourceFaVolume)`"}" -SkipCertificateCheck -ErrorAction Stop |Out-Null
    }
    else {
        throw "The source VVol VMDK and target VVol VMDK are not on the same array."
    }
    return $targetVmdk
}
function New-PfaSnapshotOfVvolVmdk {
    <#
    .SYNOPSIS
      Takes a vVol virtual disk and creates a FlashArray snapshot.
    .DESCRIPTION
      Takes a vVol virtual disk and creates a snapshot of it.
    .INPUTS
      FlashArray connection information and a virtual disk.
    .OUTPUTS
      Returns the snapshot name.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ $disks = get-vm prodVM | get-harddisk  
      PS C:\ New-PfaSnapshotOfVvolVmdk -vmdk $disks[0]

      Create a new FlashArray snapshot of a vVol virtual disk.
    .EXAMPLE
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials (get-credential) -defaultArray 
      PS C:\ $disks = get-vm prodVM | get-harddisk  
      PS C:\ New-PfaSnapshotOfVvolVmdk -vmdk $disks[0] -suffix newSnap

      Create a new FlashArray snapshot of a vVol virtual disk with a specified suffix.

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
            [Parameter(Position=0,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk[]]$Vmdk,

            [Parameter(Position=1)]
            [PurePowerShell.PureArray[]]$Flasharray,

            [ValidateScript({
              if (($_ -match "^[A-Za-z][a-zA-Z0-9\-]+[a-zA-Z0-9]$") -and ($_.length -lt 64))
              {
                $true
              }
              else {
                throw "Snapshot name must be between 1 and 63 characters (alphanumeric, _ and -) in length and begin and end with a letter or number. The name must include at least one letter, _, or -"
              }
            })]
            [Parameter(Position=2)]
            [string]$Suffix
    )
    Begin {
        $allSnaps = @()
    }
    Process {
      foreach ($vmdkDisk in $vmdk)
      {
          $datastore = $vmdkDisk |get-datastore
          if ($null -eq $flasharray)
          {
              $fa = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
          }
          else 
          {
              $fa = get-PfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
          }
          $vvolUuid = get-vvolUuidFromHardDisk -vmdk $vmdkDisk -ErrorAction Stop
          $faVolume = get-PfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid -ErrorAction Stop
          if (![string]::IsNullOrEmpty($suffix))
          {
            $snapshot = New-PfaRestOperation -resourceType "volume" -restOperationType POST -flasharray $fa -jsonBody "{`"snap`":true,`"source`":[`"$($faVolume)`"],`"suffix`":`"$($suffix)`"}" -SkipCertificateCheck -ErrorAction Stop
          }
          else {
            $snapshot = New-PfaRestOperation -resourceType "volume" -restOperationType POST -flasharray $fa -jsonBody "{`"snap`":true,`"source`":[`"$($faVolume)`"]}" -SkipCertificateCheck -ErrorAction Stop
          }
          $allSnaps += $snapshot
          $Global:CurrentFlashArray = $fa
      } 
    }
    End {
        return $allSnaps.name
    } 
}
function Get-VmdkFromWindowsDisk {
    <#
    .SYNOPSIS
      Returns the VM disk object that corresponds to a given Windows file system
    .DESCRIPTION
      Takes in a drive letter and a VM object and returns a matching VMDK object. Requires Windows 2012 R2 and later and VMware tools.
    .INPUTS
      VM, Drive Letter
    .OUTPUTS
      Returns VMDK object 
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/26/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $vm = get-vm myVM 
      PS C:\ Get-VmdkFromWindowsDisk -vm $vm -driveLetter E
      
      Returns the virtual disk object that hosts the specified Windows drive

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
            [Parameter(Position=0,mandatory=$false,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$Vm,

            [Parameter(Position=1,mandatory=$false)]
            [string]$DriveLetter
    )
    if ($null -eq $vm)
    {
      $vmName = Read-Host "Please enter in the name of your VM" 
      $vm = get-vm -name $vmName -ErrorAction Stop 
    }
    $guest = $vm |Get-VMGuest
    if ($guest.State -ne "running")
    {
        throw "This VM does not have VM tools running"
    }
    if ($guest.GuestFamily -ne "windowsGuest")
    {
        throw "This is not a Windows VM--it is $($guest.OSFullName)"
    }
    $advSetting = Get-AdvancedSetting -Entity $vm -Name Disk.EnableUUID -ErrorAction Stop
    if ($advSetting.value -eq "FALSE")
    {
        throw "The VM $($vm.name) has the advanced setting Disk.EnableUUID set to FALSE. This must be set to TRUE for this cmdlet to work."    
    }
    if (($null -eq $driveLetter) -or ($driveLetter -eq ""))
    {
      $driveLetter = Read-Host "Please enter in a drive letter" 
      if (($null -eq $driveLetter) -or ($driveLetter -eq ""))
      {
          throw "No drive letter entered"
      }
    }
    $VMdiskSerialNumber = $vm |Invoke-VMScript -ScriptText "get-partition -driveletter $($driveLetter) | get-disk | ConvertTo-CSV -NoTypeInformation"  -WarningAction silentlyContinue -ErrorAction Stop |ConvertFrom-Csv
    if (![bool]($VMDiskSerialNumber.PSobject.Properties.name -match "serialnumber"))
    {
        throw ($VMdiskSerialNumber |Out-String) 
    }
    $vmDisk = $vm | Get-HardDisk |Where-Object {$_.ExtensionData.backing.uuid.replace("-","") -eq $VMdiskSerialNumber.SerialNumber}
  if ($null -ne $vmDisk)
  {
      return $vmDisk
  }
  else {
      throw "Could not match the VM disk to a VMware virtual disk"
  }
}
function New-PfaVasaProvider {
  <#
  .SYNOPSIS
    Registers FlashArray VASA Providers with a vCenter.
  .DESCRIPTION
    Registers VASA Providers of one or more FlashArrays with a vCenter.
  .INPUTS
    FlashArray connection(s) and credentials.
  .OUTPUTS
    Returns the VASA Providers
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-420-1.purecloud.com -credentials (get-credential) -nonDefaultArray
    PS C:\ new-PfaVasaProvider -flasharray $Global:AllFlashArrays[0] -credentials (get-credential)

    Connects to a FlashArray and then registers both of its VASA providers with a vCenter while passing in VASA credentials non-interactively.
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-420-1.purecloud.com -credentials (get-credential) -nonDefaultArray
    PS C:\ New-PfaConnection -endpoint flasharray-x70-2.purecloud.com -credentials (get-credential) -nonDefaultArray
    PS C:\ New-PfaVasaProvider -flasharray $Global:AllFlashArrays -credentials (get-credential)

    Connects to two FlashArrays and then registers both VASA providers for each FlashArray with a vCenter while passing in VASA credentials non-interactively.
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-420-1.purecloud.com -credentials (get-credential) -nonDefaultArray
    PS C:\ New-PfaVasaProvider -flasharray $Global:AllFlashArrays[0]

    Connects to a FlashArray and then registers both of its VASA providers with a vCenter. VASA credentials will be asked for interactively.
  .NOTES
    Version:        1.1
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  12/23/2019
    Purpose/Change: Parameter sets

  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  [CmdletBinding(DefaultParameterSetName="FlashArrays")]
  Param(
          [Parameter(ParameterSetName='FlashArrays',Position=0,ValueFromPipeline=$True)]
          [PurePowerShell.PureArray[]]$Flasharray,

          [Parameter(ParameterSetName='AllFlashArrays',Position=1,ValueFromPipeline=$True,mandatory=$true)]
          [Parameter(ParameterSetName='FlashArrays',Position=1,ValueFromPipeline=$True,mandatory=$true)]
          [System.Management.Automation.PSCredential]$Credentials,

          [Parameter(ParameterSetName='AllFlashArrays',Position=2,mandatory=$true)]
          [switch]$AllFlashArrays
  )
  if ($null -eq $flasharray)
  {
      if ($allFlashArrays -ne $True)
      {
          $fa = $Global:DefaultFlashArray
      }
      elseif ($allFlashArrays -eq $True) 
      {
          $fa = getAllFlashArrays
      }  
  }
  else {
      $fa = $flasharray
  }
  if ($null -eq $fa)
  {
      throw "No FlashArray connections found. Please authenticate one or more FlashArrays."
  }
  $vasaProviders = @()
  foreach ($faConnection in $fa) 
  {
      $mgmtIPs = New-PfaRestOperation -resourceType network -restOperationType GET -flasharray $faConnection -SkipCertificateCheck |Where-Object {$_.name -like "*eth0"} 
      $arrayname = New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $faConnection -SkipCertificateCheck
      $ctnum = 0
      foreach ($mgmtIP in $mgmtIPs)
      {
          $vasaRegistered = $false
          do 
          {
            try 
            {
                $vasaProviders += New-VasaProvider -Name ("$($arrayname.array_name)-CT$($ctnum)") -Credential $credentials -Url ("https://$($mgmtIP.address):8084") -force -ErrorAction Stop
                $vasaRegistered = $True
            }
            catch 
            {
                if ($_.Exception -like "*credentials for the VASA*are incorrect*")
                {
                  Write-Error -Message "The provided credentials for the VASA providers on $($arrayname.array_name) are incorrect. Please provide correct ones."
                  $credentials = $Host.ui.PromptForCredential("Error: Incorrect FlashArray VASA Credentials", "Please enter your $($arrayname.array_name) VASA username and password.", "","")
                  if ($null -eq $credentials)
                  {
                      throw "Array registration canceled."
                  }
                }
                elseif ($_.Exception -like "*The VASA provider at URL*is already registered*") 
                {
                  Write-Warning -Message "The VASA provider for $($arrayname.array_name) controller $($ctnum) is already registered on this vCenter."
                  $vasaRegistered = $True
                }
                else 
                {
                  throw $_.Exception
                }
            }
          }
          while ($vasaRegistered -ne $true)
          $ctnum++
      }
  }
  return $vasaProviders
}
function Get-PfaVasaProvider {
  <#
  .SYNOPSIS
    Returns the active VASA Provider for a given FlashArray from a vCenter or all Pure Storage active VASA Providers.
  .DESCRIPTION
    Returns the active VASA Provider for a given FlashArray from a vCenter or all Pure Storage active VASA Providers.
  .INPUTS
    FlashArray connection
  .OUTPUTS
    Returns the Pure Storage VASA Provider(s)
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-420-1.purecloud.com -credentials (get-credential) -DefaultArray
    PS C:\ Get-PfaVasaProvider -flasharray $Global:DefaultFlashArray

    Connect to a FlashArray and return the current active VASA Provider for that FlashArray.
  .EXAMPLE
    PS C:\ Get-PfaVasaProvider 

    Returns all active VASA Providers.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/26/2020
    Purpose/Change: Core support

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
          [PurePowerShell.PureArray]$Flasharray
      )
      if ($null -eq $flasharray)
      {
        return (Get-VasaProvider |Where-Object {$_.Namespace -eq "com.purestorage"})
      }
      $faID = "com.purestorage:" + (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
      try {
        $vp = (Get-VasaStorageArray -Id $faid -ErrorAction Stop).provider
        return $vp
      }
      catch {
        throw "No registered VASA provider found for this array."
      }
}
function Remove-PfaVasaProvider {
  <#
  .SYNOPSIS
    Removes a FlashArrays VASA Providers from a vCenter.
  .DESCRIPTION
    Removes both VASA Providers from a vCenter for a specified FlashArray.
  .INPUTS
    FlashArray connection(s) and credentials.
  .OUTPUTS
    Returns the VASA Providers
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-420-1.purecloud.com -credentials (get-credential) -nonDefaultArray
    PS C:\ Remove-PfaVasaProvider -flasharray $Global:AllFlashArrays[0]

    Connect to FlashArray and then remove all VASA providers for that FlashArray from vCenter and interactively confirm their removal.
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-420-1.purecloud.com -credentials (get-credential) -nonDefaultArray
    PS C:\ Remove-PfaVasaProvider -flasharray $Global:AllFlashArrays[0] -Confirm:$false

    Connect to FlashArray and then remove all VASA providers for a given FlashArray without additional confirmation prompts.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/26/2020
    Purpose/Change: Core support

  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
  Param(
          [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
          [PurePowerShell.PureArray]$Flasharray
      )
      $moreProviders = $true
      $vasaProvider = $null
      while ($moreProviders -eq $true)
      {
          if ($null -eq $vasaProvider)
          {
            $vasaProvider = $flasharray | get-PfaVasaProvider -ErrorAction Stop
          }
          if ($PSCmdlet.ShouldProcess($($vasaProvider).name,"Unregister FlashArray VASA Provider")) 
          {
            Remove-VasaProvider -Provider $vasaProvider -Confirm:$false
          }
          $vasaProvider = $null
          $vasaProvider = $flasharray | get-PfaVasaProvider -ErrorAction SilentlyContinue
          if ($null -eq $vasaProvider)
          {
            $moreProviders = $false
          }
      }
}
function Mount-PfaVvolDatastore {
  <#
  .SYNOPSIS
    Mounts a FlashArray VVol Datastore to a host or cluster
  .DESCRIPTION
    Mounts a FlashArray VVol Datastore to a host or cluster, connects a PE to the cluster if not present.
  .INPUTS
    FlashArray connection, name, a VVol datastore, a VASA array, and/or a cluster.
  .OUTPUTS
    Returns the datastore
  .EXAMPLE
    PS C:\ $datastore = get-datastore m50-VVolDs
    PS C:\ $flasharray = new-pfaConnection -endpoint flasharray-m50-1 -credentials $creds -ignoreCertificateError -nonDefaultArray
    PS C:\ Mount-PfaVvolDatastore -datastore $datastore -flasharray $flasharray -cluster (get-cluster MyCluster)

    Connects a protocol endpoint to a cluster and then mounts the specified existing VVol datastore to that cluster.
  .EXAMPLE
    PS C:\ $flasharray = new-pfaConnection -endpoint flasharray-m50-1 -credentials $creds -ignoreCertificateError -nonDefaultArray
    PS C:\ Mount-PfaVvolDatastore -datastore $datastore -flasharray $flasharray -cluster (get-cluster MyCluster) -datastoreName m50-VVolDs

    Mounts the default VVol datastore of the specifed FlashArray to the cluster.
  .EXAMPLE
    PS C:\ $vasaArray = get-vasaStorageArray m50-1-pure
    PS C:\ Mount-PfaVvolDatastore -vasaArray $vasaArray -cluster (get-cluster MyCluster) 

    Mounts the default VVol datastore of the specifed FlashArray to the cluster.
  .NOTES
    Version:        1.1
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  12/23/2019
    Purpose/Change: Parameter sets

  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  [CmdletBinding(DefaultParameterSetName="FlashArray")]
  Param(
          [Parameter(ParameterSetName='FlashArray',Position=0,ValueFromPipeline=$True)]
          [PurePowerShell.PureArray]$Flasharray,

          [Parameter(ParameterSetName='FlashArray',Position=1)]
          [Parameter(ParameterSetName='VASA',Position=1)]
          [string]$DatastoreName,

          [Parameter(ParameterSetName='Datastore',Position=2,ValueFromPipeline=$True)]
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

          [Parameter(Position=3,mandatory=$true,ValueFromPipeline=$True)]
          [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,

          [Parameter(Position=4)]
          [string]$ProtocolEndpoint,

          [Parameter(ParameterSetName='VASA',Position=5,ValueFromPipeline=$True)]
          [ValidateScript({
            if ($_.VendorId -ne "PURE")
            {
                throw "The passed in VASA array is not a Pure Storage array."
            }
            else {
              $true
            }
          })]
          [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray]$VasaArray
      )
      if ($null -ne $datastore) 
      {
        $arrayID = $datastore.ExtensionData.Info.VvolDS.StorageArray[0].Uuid
        $scId = $datastore.ExtensionData.Info.VvolDS.ScId
        $needToCalculateScID = $false
        $datastoreName = $datastore.Name
      }
      elseif ($null -ne $flasharray) 
      {
        $arrayID = "com.purestorage:" + (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
        $needToCalculateScID = $True
      }
      elseif ($null -ne $vasaArray) 
      {
        $needToCalculateScID = $True
        $arrayID = $vasaArray.id
        $fas = getAllFlashArrays
        foreach ($faTest in $fas) {
          $pfaID = "com.purestorage:" + (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $faTest -SkipCertificateCheck).id
          if ($arrayID -eq $pfaID)
          {
            $flasharray = $faTest
            break
          }
        }
      }
      if ([string]::IsNullOrWhiteSpace($arrayID))
      {
        $flasharray = checkDefaultFlashArray
        $arrayID = "com.purestorage:" + (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
        $needToCalculateScID = $True
      }
      $esxiHosts = $cluster |Get-VMHost
      #find array OUI
      $arrayOui = $arrayID.substring(16,36)
      $arrayOui = $arrayOui.replace("-","")
      $arrayOui = $arrayOui.Substring(0,16)
      if ($needToCalculateScID -eq $True)
        {
          #generateSCid
          $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
          $utf8 = new-object -TypeName System.Text.UTF8Encoding
          $hash = $md5.ComputeHash($utf8.GetBytes($arrayID.substring(16,36)))
          $hash2 = $md5.ComputeHash(($hash))
          $hash2[6] = $hash2[6] -band 0x0f
          $hash2[6] = $hash2[6] -bor 0x30
          $hash2[8] = $hash2[8] -band 0x3f
          $hash2[8] = $hash2[8] -bor 0x80
          $newGUID = (new-object -TypeName System.Guid -ArgumentList (,$hash2)).Guid
          $fixedGUID = $newGUID.Substring(18)
          $scId = $newGUID.Substring(6,2) + $newGUID.Substring(4,2) + $newGUID.Substring(2,2) + $newGUID.Substring(0,2) + "-" + $newGUID.Substring(11,2) + $newGUID.Substring(9,2) + "-" + $newGUID.Substring(16,2) + $newGUID.Substring(14,2) + $fixedGUID
          $scId = $scId.Replace("-","")
          $scId = "vvol:" + $scId.Insert(16,"-")
        }
        Write-Debug $scId
      if ("" -eq $datastoreName)
      {
        $datastoreExists = get-datastore |Where-Object {$_.Type -eq "VVol"} |Where-Object {$_.ExtensionData.Info.VVolds.Scid -eq $scId}
        if ($null -eq $datastoreExists)
        {
          $datastoreName = (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).array_name + "-vvol-DS"
        }
        else {
          $datastoreName = $datastoreExists.Name
          if ($null -eq $datastore)
          {
              $datastore = $datastoreExists
          }
        }
      }
      foreach ($esxi in $esxiHosts)
      {
        $foundPE = $false
        $esxcli = $esxi |Get-EsxCli -v2
        $hostProtocolEndpoint = $esxcli.storage.core.device.list.invoke() |where-object {$_.IsVVOLPE -eq $true}
        Write-Debug $hostProtocolEndpoint
        foreach ($hostPE in $hostProtocolEndpoint)
        {
          $peID = $hostPE.Device.Substring(12,24)
          $peID = $peID.Substring(0,16)
          if ($peID -eq $arrayOui)
          {
            $foundPE = $True
            break
          }
        }
        if ($foundPE -eq $false)
        {
          if ($null -eq $fa)
          {
            if ($null -ne $flasharray)
            { 
                $fa = $flasharray
            }
            else 
            { 
                try {
                  if ($null -ne $datastore)
                  {
                    $fa = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
                  }
                }
                Catch 
                {
                  if ($_.Exception -like "*Please either pass in one or more FlashArray connections*")
                  {
                      throw "No protocol endpoints found on the host $($esxi.name) for this array. Attempt to provision a PE failed as no valid PowerShell connections found for the array. Please either provision the protocol endpoint or connect the array with new-pfaconnection."
                  }
                }
                if ($null -ne $vasaArray)
                {
                  throw "No PE found, so it needs to be created and connected. This required an authenticated FlashArray and none was found for passed in VASA array. Use new-pfaconnection to connect the appropriate FlashArray."
                }
            }
          }
          $hGroup = get-pfaHostGroupfromVcCluster -cluster $cluster -flasharray $fa -ErrorAction Stop
          $allPEs = New-PfaRestOperation -resourceType volume?protocol_endpoint=true -restOperationType GET -flasharray $fa -SkipCertificateCheck -ErrorAction Stop
          if (($null -eq $protocolEndpoint) -or ($protocolEndpoint -eq ""))
          {
            $protocolEndpoint = "vVol-Protocol-Endpoint"
          }
          $pe = $allPEs |Where-Object {$_.name -eq $protocolEndpoint}
          if ($null -eq $pe)
          {
            $pe =  New-PfaRestOperation -resourceType volume/$($protocolEndpoint)?protocol_endpoint=true -restOperationType POST -flasharray $fa -SkipCertificateCheck
          }
          try
          {
            New-PfaRestOperation -resourceType "hgroup/$($hGroup.name)/volume/$($pe.name)" -restOperationType POST -flasharray $fa -SkipCertificateCheck -ErrorAction Stop |Out-Null
          }
          catch
          {
            if ($_.Exception -notlike "*Connection already exists.*")
            {
                throw $_.Exception
            }
          }
          foreach ($esxiRescan in $esxiHosts)
          {
              $hbas = $esxiRescan |get-pfaHostFromVmHost -flasharray $fa
              if ($hbas.iqn.count -ge 1)
              {
                $hbaType = "iSCSI"
              }
              elseif ($hbas.wwn.count -ge 1) 
              {
                $hbaType = "FibreChannel"
              }
              $esxiHost = $esxiRescan.ExtensionData
              $storageSystem = Get-View -Id $esxiHost.ConfigManager.StorageSystem
              $hbas = ($esxiRescan |Get-VMHostHba |where-object {$_.Type -eq $hbaType}).device
              foreach ($hba in $hbas) 
              {
                  $storageSystem.rescanHba($hba)
              }
          }
          $hostProtocolEndpoint = $esxcli.storage.core.device.list.invoke() |where-object {$_.IsVVOLPE -eq $true}
          $foundPE = $false
          foreach ($hostPE in $hostProtocolEndpoint)
          {
            $peID = $hostPE.Device.Substring(12,24)
            $peID = $peID.Substring(0,16)
            if ($peID -eq $arrayOui)
            {
              $foundPE = $True
              break
            }
          }
          if ($foundPE -eq $false)
          {
              throw "The protocol endpoint is not visible to the host. Please ensure SAN access to the array."
          }
        }
        $datastoreSystem = Get-View -Id $esxi.ExtensionData.ConfigManager.DatastoreSystem
        $spec = New-Object VMware.Vim.HostDatastoreSystemVvolDatastoreSpec
        $spec.Name = $datastoreName
        $spec.ScId = $scId
        $foundDatastore = $esxi |get-datastore |Where-Object {$_.Type -eq "VVol"} |Where-Object {$_.ExtensionData.Info.VVolds.Scid -eq $scId}
        if ($null -eq $foundDatastore)
        {
          $datastore = Get-Datastore -Id ($datastoreSystem.CreateVvolDatastore($spec))
        }
        else {
          $datastore = $foundDatastore
        }
        $foundDatastore = $null
      }
      return $datastore
}
function Get-PfaVvolStorageArray {
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
    Creation Date:  12/31/2020
    Purpose/Change: Function creation
  .EXAMPLE
    PS C:\ Get-PfaVvolStorageArray 

    Returns all Pure Storage FlashArray storage array VASA objects
  .EXAMPLE
    PS C:\ Get-PfaVvolStorageArray -ArraySerial 7e914d96-c90a-31e0-a495-75e8b3c300cc

    Returns the FlashArray storage array VASA object for the specified array serial number.
  .EXAMPLE
    PS C:\ Get-PfaVvolStorageArray -ArrayName flasharray-m50-1

    Returns the FlashArray storage array VASA object  for the specified array name.
  .EXAMPLE
    PS C:\ $fa = new-pfaConnection -endpoint flasharray-m50-1 -ignoreCertificateError -DefaultArray
    PS C:\ Get-PfaVvolStorageArray -FlashArray $fa

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
          [PurePowerShell.PureArray]$Flasharray,
  
          [Parameter(Position=1,ParameterSetName='Name')]
          [string]$ArrayName,
  
          [Parameter(Position=2,ParameterSetName='Serial')]
          [string]$ArraySerial
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
function checkDefaultFlashArray{
    if ($null -eq $Global:DefaultFlashArray)
    {
        throw "You must pass in a FlashArray connection or create a default FlashArray connection with new-Pfaconnection"
    }
    else 
    {
        return $Global:DefaultFlashArray
    }
}
function getAllFlashArrays {
  if ($null -ne $Global:AllFlashArrays)
  {
      return $Global:AllFlashArrays
  }
  else
  {
      throw "Please either pass in one or more FlashArray connections or create connections via the new-PfaConnection cmdlet."
  }
}
New-Alias -Name update-faVvolVmVolumeGroup -Value Update-PfaVvolVmVolumeGroup
New-Alias -Name get-faSnapshotsFromVvolHardDisk -Value Get-PfaSnapshotFromVvolVmdk
New-Alias -Name Get-PfaSnapshotsFromVvolHardDisk -Value Get-PfaSnapshotFromVvolVmdk
New-Alias -Name copy-faVvolVmdkToNewVvolVmdk -Value Copy-PfaVvolVmdkToNewVvolVmdk
New-Alias -Name copy-faSnapshotToExistingVvolVmdk -Value Copy-PfaSnapshotToExistingVvolVmdk
New-Alias -Name copy-faSnapshotToNewVvolVmdk -Value Copy-PfaSnapshotToNewVvolVmdk
New-Alias -Name copy-faVvolVmdkToExistingVvolVmdk -Value Copy-PfaVvolVmdkToExistingVvolVmdk
New-Alias -Name new-faSnapshotOfVvolVmdk -Value New-PfaSnapshotOfVvolVmdk
New-Alias -Name get-faVolumeNameFromVvolUuid -Value Get-PfaVolumeNameFromVvolUuid
New-Alias -Name Get-VvolUuidFromHardDisk -Value Get-VvolUuidFromVmdk