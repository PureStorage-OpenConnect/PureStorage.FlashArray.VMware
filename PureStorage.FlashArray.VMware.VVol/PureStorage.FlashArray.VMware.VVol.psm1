import-module VMware.VimAutomation.Storage
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
      Creation Date:  12/23/2019
      Purpose/Change: Parameter sets and validation
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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$vm,

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
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(ParameterSetName='VM',Position=3)]
            [String]$volumeGroupName
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
                $volumesAfterMove = (New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&filter=value=`'$($vmId)`'" -flasharray $fa -SkipCertificateCheck).Name |Select-Object -Unique
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
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  05/26/2019
      Purpose/Change: Updated for new connection mgmt
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
        [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,

        [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
        [PurePowerShell.PureArray]$flasharray
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
      $vVolVolumes = (New-PfaRestOperation -resourceType "volume" -restOperationType GET -queryFilter "?tags=true&filter=value=`'$($vmId)`'" -flasharray $flasharray -SkipCertificateCheck).Name |Select-Object -Unique
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
      Creation Date:  05/26/2019
      Purpose/Change: Updated for new connection mgmt
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
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk[]]$vmdk
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
          [string]$vvolUUID,

          [Parameter(Position=1,ValueFromPipeline=$True)]
          [PurePowerShell.PureArray[]]$flasharray
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
          $faSession = new-PfaRestSession -flasharray $fa 
          $purevip = $fa.EndPoint
          #Pull tags that match the volume with that UUID
          try {
              add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
  public bool CheckValidationResult(
      ServicePoint srvPoint, X509Certificate certificate,
      WebRequest request, int certificateProblem) {
      return true;
  }
}
"@
          }
          Catch {}
          [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
          [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
          $volumeTags = Invoke-RestMethod -Method Get -Uri "https://$($purevip)/api/$($fa.apiversion)/volume?tags=true&filter=value='${vvolUUID}'" -WebSession $faSession -ErrorAction Stop
          $volumeName = $volumeTags |where-object {$_.key -eq "PURE_VVOL_ID"}
          remove-PfaRestSession -faSession $faSession -flasharray $fa
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
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/24/2019
      Purpose/Change: Updated for new connection mgmt
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
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$vmdk,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
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
    $faSession = new-PfaRestSession -flasharray $fa 
    $purevip = $fa.EndPoint
    $vvolUuid = Get-VvolUuidFromVmdk -vmdk $vmdk
    $faVolume = get-PfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid 
    $volumeSnaps = Invoke-RestMethod -Method Get -Uri "https://${purevip}/api/$($fa.apiversion)/volume/${faVolume}?snap=true" -WebSession $faSession -ErrorAction Stop
    $snapNames = @()
    foreach ($volumeSnap in $volumeSnaps)
    {
        $snapNames += $volumeSnap.name 
    }
    return $snapNames
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
      Creation Date:  05/26/2019
      Purpose/Change: Updated for new connection mgmt
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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$targetVm,

            [Parameter(Position=1,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$vmdk,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
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
    $newHardDisk = New-HardDisk -Datastore $datastore -CapacityGB $vmdk.CapacityGB -VM $targetVm 
    $newVvolUuid = get-vvolUuidFromVmdk -vmdk $newHardDisk 
    $newFaVolume = get-PfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $newVvolUuid 
    New-PfaVolume -Array $fa -Source $faVolume -Overwrite -VolumeName $newFaVolume  |Out-Null
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
      Creation Date:  05/26/2019
      Purpose/Change: Updated for new connection mgmt
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
            [string]$snapshotName,

            [Parameter(Position=1,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$vmdk,

            [Parameter(Position=4,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
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
    $foundSnap = Get-PfaVolumeSnapshot -Array $fa -SnapshotName $snapshotName
    if ($null -eq $foundSnap)
    {
        throw "The snapshot either does not exist, or is not on the same array as the target vVol."
    }
    $snapshotSize = Get-PfaSnapshotSpaceMetrics -Array $fa -Name $snapshotName
    if ($vmdk.ExtensionData.capacityinBytes -eq $snapshotSize.size)
    {
        New-PfaVolume -Array $fa -Source $snapshotName -Overwrite -VolumeName $faVolume  |Out-Null
    }
    elseif ($vmdk.ExtensionData.capacityinBytes -lt $snapshotSize.size) {
        $vmdk = Set-HardDisk -HardDisk $vmdk -CapacityKB ($snapshotSize.size / 1024) -Confirm:$false 
        $vmdk = New-PfaVolume -Array $fa -Source $snapshotName -Overwrite -VolumeName $faVolume 
        
    }
    else {
        throw "The target vVol hard disk is larger than the snapshot size and VMware does not allow hard disk shrinking."
    } 
    return $vmdk    
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
      Creation Date:  06/04/2019
      Purpose/Change: Updated for new connection mgmt
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
            [string]$snapshotName,

            [Parameter(Position=1,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$targetVm,

            [Parameter(ParameterSetName='FlashArray',Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray,

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
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
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
        $arrayID = (Get-PfaArrayAttributes -Array $flasharray).id
        $datastore = $targetVm| Get-VMHost | Get-Datastore |where-object {$_.Type -eq "VVOL"} |Where-Object {$_.ExtensionData.info.vvolDS.storageArray[0].uuid.substring(16) -eq $arrayID} |Select-Object -First 1
    }
    elseif (($null -ne $flasharray) -and ($null -eq $datastore))
    {
      $arrayID = (Get-PfaArrayAttributes -Array $flasharray).id
      $datastore = $targetVm| Get-VMHost | Get-Datastore |where-object {$_.Type -eq "VVOL"} |Where-Object {$_.ExtensionData.info.vvolDS.storageArray[0].uuid.substring(16) -eq $arrayID} |Select-Object -First 1
    }
    $snapshotSize = Get-PfaSnapshotSpaceMetrics -Array $flasharray -Name $snapshotName -ErrorAction Stop
    $newHardDisk = New-HardDisk -Datastore $datastore -CapacityKB ($snapshotSize.size / 1024 ) -VM $targetVm 
    $newVvolUuid = get-vvolUuidFromHardDisk -vmdk $newHardDisk 
    $newFaVolume = get-PfaVolumeNameFromVvolUuid -flasharray $flasharray -vvolUUID $newVvolUuid 
    New-PfaVolume -Array $flasharray -Source $snapshotName -Overwrite -VolumeName $newFaVolume  |Out-Null
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
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/02/2020
      Purpose/Change: Updated for new connection mgmt
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
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$sourceVmdk,

            [Parameter(Position=1,mandatory=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$targetVmdk,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
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
        if ($targetVmdk.CapacityKB -eq $sourceVmdk.CapacityKB)
        {
            New-PfaVolume -Array $targetFlasharray -Source $sourceFaVolume -Overwrite -VolumeName $targetFaVolume |Out-Null
        }
        elseif ($targetVmdk.CapacityKB -lt $sourceVmdk.CapacityKB) {
            $targetVmdk = Set-HardDisk -HardDisk $targetVmdk -CapacityKB $sourceVmdk.CapacityKB -Confirm:$false 
            New-PfaVolume -Array $targetFlasharray -Source $sourceFaVolume -Overwrite -VolumeName $targetFaVolume  |Out-Null     
        }
        else {
            throw "The target VVol hard disk is larger than the snapshot size and VMware does not allow hard disk shrinking."
        }
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
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/02/2020
      Purpose/Change: Updated for new connection mgmt
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
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk[]]$vmdk,

            [Parameter(Position=1)]
            [PurePowerShell.PureArray[]]$flasharray,

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
            [string]$suffix
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
          if (($null -eq $suffix) -or ($suffix -eq ""))
          {
              $snapshot = New-PfaVolumeSnapshots -Array $fa -Sources $faVolume -ErrorAction Stop
          }
          else {
              $snapshot = New-PfaVolumeSnapshots -Array $fa -Sources $faVolume -Suffix $suffix -ErrorAction Stop
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
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/24/2018
      Purpose/Change: Updated for new connection mgmt
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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,

            [Parameter(Position=1,mandatory=$false)]
            [string]$driveLetter
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
          [PurePowerShell.PureArray[]]$flasharray,

          [Parameter(ParameterSetName='AllFlashArrays',Position=1,ValueFromPipeline=$True,mandatory=$true)]
          [Parameter(ParameterSetName='FlashArrays',Position=1,ValueFromPipeline=$True,mandatory=$true)]
          [System.Management.Automation.PSCredential]$credentials,

          [Parameter(ParameterSetName='AllFlashArrays',Position=2,mandatory=$true)]
          [switch]$allFlashArrays
  )
  $powerCLIVersionCheck = (Get-Module -name VMware.PowerCLI -ListAvailable).Version |Where-Object {($_.Major -ge 11) -and ($_.Minor -ge 3)}
  if ($null -eq $powerCLIVersionCheck)
  {
      throw "You must be running PowerCLI 11.3.0 or later for this cmdlet to work. Please run update-module VMware.PowerCLI or update manually."
  }
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
      $mgmtIPs = Get-PfaNetworkInterfaces -Array $faConnection | where-object {$_.name -like "*eth0"}
      $arrayname = Get-PfaArrayAttributes -array $faConnection
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
    Returns the active VASA Provider for a given FlashArray from a vCenter.
  .DESCRIPTION
    Returns the active VASA Provider for a given FlashArray from a vCenter.
  .INPUTS
    FlashArray connection
  .OUTPUTS
    Returns the VASA Provider
  .EXAMPLE
    PS C:\ New-PfaConnection -endpoint flasharray-420-1.purecloud.com -credentials (get-credential) -DefaultArray
    PS C:\ Get-PfaVasaProvider -flasharray $Global:DefaultFlashArray

    Connect to a FlashArray and return the current active VASA Provider for that FlashArray.
  .NOTES
    Version:        1.1
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  01/23/2020
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
          [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
          [PurePowerShell.PureArray]$flasharray
      )
      $faID = "com.purestorage:" + (Get-PfaArrayAttributes -Array $flasharray).id
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
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  07/08/2019
    Purpose/Change: First release

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
          [PurePowerShell.PureArray]$flasharray
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
          [PurePowerShell.PureArray]$flasharray,

          [Parameter(ParameterSetName='FlashArray',Position=1)]
          [Parameter(ParameterSetName='VASA',Position=1)]
          [string]$datastoreName,

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
          [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

          [Parameter(Position=3,mandatory=$true,ValueFromPipeline=$True)]
          [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

          [Parameter(Position=4)]
          [string]$protocolEndpoint,

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
          [VMware.VimAutomation.Storage.Types.V1.Sms.VasaStorageArray]$vasaArray
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
        $arrayID = "com.purestorage:" + (Get-PfaArrayAttributes -array $flasharray).id
        $needToCalculateScID = $True
      }
      elseif ($null -ne $vasaArray) 
      {
        $needToCalculateScID = $True
        $arrayID = $vasaArray.id
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
      if ("" -eq $datastoreName)
      {
        $datastoreExists = get-datastore |Where-Object {$_.Type -eq "VVol"} |Where-Object {$_.ExtensionData.Info.VVolds.Scid -eq $scId}
        if ($null -eq $datastoreExists)
        {
          throw "This storage container ID ($($scId)) has not yet been mounted in this vCenter as a vVol datastore, so no existing name was found. Please enter a name for the vVol datastore"
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
                  $fa = get-PfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
                }
                Catch 
                {
                  if ($_.Exception -like "*Please either pass in one or more FlashArray connections*")
                  {
                      throw "No protocol endpoints found on the host $($esxi.name) for this array. Attempt to provision a PE failed as no valid PowerShell connections found for the array. Please either provision the protocol endpoint or connect the array with new-pfaconnection."
                  }
                }
            }
          }
          $hGroup = get-pfaHostGroupfromVcCluster -cluster $cluster -flasharray $fa -ErrorAction Stop
          $allPEs = Get-PfaProtocolEndpointVolumes -Array $fa -ErrorAction Stop
          if (($null -ne $protocolEndpoint) -and ($protocolEndpoint -ne ""))
          {
              $pe = $allPEs |Where-Object {$_.name -eq $protocolEndpoint}
              if ($null -eq $pe)
              {
                  throw "The Protocol Endpoint named $($protocolEndpoint) was not found."
              }
          }
          else 
          {
            $pe = $allPEs |Where-Object {$_.name -eq "pure-protocol-endpoint"}
          }
          if ($null -eq $pe)
          {
            $pe = New-PfaProtocolEndpointVolume -Array $fa -VolumeName "pure-protocol-endpoint"
          }
          try
          {
            New-PfaHostGroupVolumeConnection -Array $fa -VolumeName $pe.name -HostGroupName $hGroup.name -ErrorAction Stop|Out-Null
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
function Initialize-PfaVVols {
  <#
  .SYNOPSIS
    Configures a VMware environment from scratch for Pure Storage FlashArray VVols.
  .DESCRIPTION
    Configures iSCSI, host groups, registers VASA, installs the vSphere Plugin, mounts VVol datastore to specified cluster
  .INPUTS
    FlashArray FQDN/IP and credentials, a vCenter cluster or clusters
  .OUTPUTS
    Returns the VVol datastore
  .EXAMPLE
    PS C:\ Connect-ViServer -Server myvCenter.purestorage.com
    PS C:\ Initialize-PfaVVols -flasharray myFlashArray.purestorage.com -allClusters 

    Description. Configures VVols for a FlashArray for all clusters in a vCenter.
  .EXAMPLE
    PS C:\ Connect-ViServer -Server myvCenter.purestorage.com
    PS C:\ $cluster = get-cluster myCluster
    PS C:\ Initialize-PfaVVols -flasharray myFlashArray.purestorage.com -cluster $cluster

    Description. Configures VVols for a FlashArray for the cluster called myCluster in a vCenter.
  .EXAMPLE
    PS C:\ Connect-ViServer -Server myvCenter.purestorage.com
    PS C:\ Initialize-PfaVVols -flasharray myFlashArray.purestorage.com -allClusters -iscsi

    Description. Configures VVols for a FlashArray for all clusters in a vCenter and specifies iSCSI as the connection protocol.
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  07/25/2019
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
          [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
          [string]$flasharray,

          [Parameter(Position=1,ValueFromPipeline=$True)]
          [System.Management.Automation.PSCredential]$credentials,

          [Parameter(Position=2,ValueFromPipeline=$True)]
          [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster[]]$cluster,

          [Parameter(Position=3,ValueFromPipeline=$True)]
          [switch]$allClusters,

          [Parameter(Position=4)]
          [switch]$iscsi,
  
          [Parameter(Position=5)]
          [switch]$fc,

          [Parameter(Position=6)]
          [string]$datastoreName
  )
  if ($null -eq $global:defaultviserver)
  {
    $vcenter = Read-Host "Please enter in a vCenter server address"
    Connect-VIServer -Server $vcenter
  }
  if (($iscsi -eq $true) -and ($fc -eq $true))
  {
      throw "Please only specify iSCSI or FC or neither. If neither is specified the cmdlet will query the array for protocol support."
  }
  if (($null -ne $cluster) -and ($allClusters -eq $true))
  {
      throw "Please either only pass in specific clusters OR use the -allClusters parameter. Not both."
  }
  if (($null -eq $cluster) -and ($allClusters -eq $false))
  {
    $clusterName = Read-Host "Please enter a cluster name to mount the VVol datastore"
    $cluster = Get-Cluster $clusterName -ErrorAction Stop
  }
  if ($allClusters -eq $True)
  {
    $cluster = Get-Cluster
  }
  if ($null -eq $credentials)
  {
    $credentials = Get-Credential -Message "Please enter in FlashArray administrative credentials"
  }
  Write-Progress -Activity "Connecting to FlashArray" -status "Connecting..." -percentComplete 0
  $fa = New-PfaArray -EndPoint $flasharray -Credentials $credentials -IgnoreCertificateError -ErrorAction Stop
  if (($iscsi -eq $false) -and ($fc -eq $false))
  {
      $foundFC = $null
      $foundFC = Get-PfaAllHardwareAttributes -Array $fa |Where-Object {$_.name -like "*FC*"}
      if ($null -eq $foundFC)
      {
          $iscsi = $True
      }
      else 
      {
          $fc = $True
      }
  }
  Write-Progress -Activity "Connecting to FlashArray" -status "Connected." -percentComplete 20
  if ($fc -eq $true)
  {
    write-warning "Fibre Channel is the selected protocol. This script does not configure zoning, so ensure that this is completed."
  }
  $percentComplete = (21 - (20/$cluster.count))
  foreach ($workingCluster in $cluster)
  {
      Write-Progress -Activity "Creating host group(s)" -status $workingCluster.name -percentComplete ($percentComplete + (20/$cluster.count))
      new-pfaHostGroupfromVcCluster -cluster $workingCluster -iscsi:$iscsi -fc:$fc -flasharray $fa -ErrorAction Stop |Out-Null
      $percentComplete = $percentComplete + (20/$cluster.count)
  }
  Write-Progress -Activity "Creating host group(s)" -status "Created." -percentComplete 40
  #vSphere Plugin installation
  Write-Progress -Activity "Installing vSphere Plugin" -status "Installing..." -percentComplete 41
  try 
  {
    $pureplugins = get-pfavsphereplugin -source Pure1 -html
    if ($null -eq $pureplugins)
    {
      install-pfavSpherePlugin -flasharray $fa -ErrorAction stop -Confirm:$false|Out-Null
    }
    else 
    {
      install-pfavSpherePlugin -source "Pure1" -html -ErrorAction stop -Confirm:$false|Out-Null
    }
    Write-Progress -Activity "Installing vSphere Plugin" -status "Installed." -percentComplete 60
  }
  catch 
  {
      Write-Warning $_
  }

  #Register VASA
  Write-Progress -Activity "Registering VASA Providers" -status "Registering..." -percentComplete 61
  New-PfaVasaProvider -flasharray $fa -credentials $credentials |Out-Null
  Write-Progress -Activity "Registering VASA Providers" -status "Registered." -percentComplete 80
  Write-Progress -Activity "Mounting VVol Datastore" -status "Mounting..." -percentComplete 81
  if ($datastoreName -eq "")
  {
      $datastoreName = ((Get-PfaArrayAttributes -Array $fa).array_name + "-VVolDS" )
  }
  $percentComplete = (81 - (20/$cluster.count))
  foreach ($workingCluster in $cluster)
  {
    Write-Progress -Activity "Mounting VVol Datastore" -status "Mounting on cluster $($workingCluster.Name)..." -percentComplete ($percentComplete + (20/$cluster.count))
    $datastore = Mount-PfaVvolDatastore -flasharray $fa -cluster $workingCluster -datastoreName $datastoreName 
    $percentComplete = $percentComplete + (20/$cluster.count)
    if (($percentComplete + (20/$cluster.count)) -ge 100)
    {
      $percentComplete = 99 - (20/$cluster.count)
    }
  }
  Write-Progress -Activity "Mounting VVol Datastore" -status "Mounted on cluster(s)." -percentComplete 100
  return $datastore
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