function update-pfaVvolVmVolumeGroup {
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
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  06/03/2019
      Purpose/Change: Updated for new connection mgmt
  
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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$vm,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
    )
    $volumeFinalNames = @()
    if ($null -ne $datastore)
    {
        if ($null -eq $flasharray)
        {
            $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
        }
        else 
        {
            $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
        }
        if ($datastore.Type -ne "VVOL")
        {
            throw "This is not a VVol datastore"
        }
        if ($datastore.ExtensionData.Info.VvolDS.StorageArray[0].VendorId -ne "PURE") {
            throw "This is not a Pure Storage VVol datastore"
        }
        $vms = $datastore |get-vm
    }
    elseif ($null -ne $vm) {
        $vms = $vm
    }
    else{
        throw "You must enter in either a VM object or a VVol datastore"
    }
    foreach ($vm in $vms)
    {
        $configUUID = $vm.ExtensionData.Config.VmStorageObjectId
        if ($null -eq $configUUID)
        {
            write-warning -message  "The input VM $($vm.name) is not a VVol-based virtual machine. Skipping"
            continue
        }
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
                    $fa = get-pfaConnectionOfDatastore -datastore $vmDatastore -ErrorAction Stop
                }
                else 
                {
                    $fa = get-pfaConnectionOfDatastore -datastore $vmDatastore -flasharrays $flasharray -ErrorAction Stop
                }
                $faSession = new-pfaRestSession -flasharray $fa
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
                $volumeConfig =  Invoke-RestMethod -Method Get -Uri "https://$($fa.Endpoint)/api/$($fa.apiversion)/volume?tags=true&filter=value='${configUUID}'" -WebSession $faSession -ErrorAction Stop
                $configVVolName = ($volumeConfig |where-object {$_.key -eq "PURE_VVOL_ID"}).name
                if ($null -eq $configVVolName)
                {
                    write-warning -message "The VM $($vm.name) was not found on this FlashArray. Skipping."
                    continue
                }
                if ($vm.Name -match "^[a-zA-Z0-9\-]+$")
                {
                    $vmName = $vm.Name
                }
                else
                {
                    $vmName = $vm.Name -replace "[^\w\-]", ""
                    $vmName = $vmName -replace "[_]", ""
                    $vmName = $vmName -replace " ", ""
                }
                $vGroupRand = '{0:X}' -f (get-random -Minimum 286331153 -max 4294967295)
                $newName = "vvol-$($vmName)-$($vGroupRand)-vg"
                if ([Regex]::Matches($configVVolName, "/").Count -eq 0)
                {
                    $vGroup = New-PfaVolumeGroup -Array $fa -Name $newName
                }
                else {
                    $vGroup = $configVVolName.split('/')[0]
                    $vGroup = Invoke-RestMethod -Method Put -Uri "https://$($fa.Endpoint)/api/$($fa.apiversion)/vgroup/${vGroup}?name=${newName}" -WebSession $faSession -ErrorAction Stop
                }
                $vmId = $vm.ExtensionData.Config.InstanceUuid
                $volumesVmId = Invoke-RestMethod -Method Get -Uri "https://$($fa.Endpoint)/api/$($fa.apiversion)/volume?tags=true&filter=value='${vmId}'" -WebSession $faSession -ErrorAction Stop
                $volumeNames = $volumesVmId |where-object {$_.key -eq "VMW_VmID"}
                foreach ($volumeName in $volumeNames)
                {
                    if ([Regex]::Matches($volumeName.name, "/").Count -eq 1)
                    {
                        if ($newName -ne $volumeName.name.split('/')[0])
                        {
                            $volName= $volumeName.name.split('/')[1]
                            Add-PfaVolumeToContainer -Array $fa -Container $newName -Name $volName |Out-Null
                        }
                    }
                    else {
                        $volName= $volumeName.name
                        Add-PfaVolumeToContainer -Array $fa -Container $newName -Name $volName |Out-Null
                    }
                }
                $volumesVmId = Invoke-RestMethod -Method Get -Uri "https://$($fa.Endpoint)/api/$($fa.apiversion)/volume?tags=true&filter=value='${vmId}'" -WebSession $faSession -ErrorAction Stop
                $volumeFinalNames += $volumesVmId |where-object {$_.key -eq "VMW_VmID"}
                remove-pfaRestSession -flasharray $fa -faSession $faSession |Out-Null
            }
        }
    }
    return $volumeFinalNames.name
}
function get-vvolUuidFromHardDisk {
    <#
    .SYNOPSIS
      Gets the VVol UUID of a virtual disk
    .DESCRIPTION
      Takes in a virtual disk object
    .INPUTS
      Virtual disk object (get-harddisk).
    .OUTPUTS
      Returns the VVol UUID.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  05/26/2019
      Purpose/Change: Updated for new connection mgmt
  
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
              throw "This is not a VVol-based hard disk."
          }
          if ((($vmdkDisk |Get-Datastore).ExtensionData.Info.vvolDS.storageArray.vendorId) -ne "PURE") {
              throw "This is not a Pure Storage FlashArray VVol disk"
          }
          $allUuids += $vmdkDisk.ExtensionData.Backing.backingObjectId
        }
    }
    End {
        return $allUuids
    }

}
function get-pfaVolumeNameFromVvolUuid{
  <#
  .SYNOPSIS
    Connects to vCenter and FlashArray to return the FA volume that is a VVol virtual disk.
  .DESCRIPTION
    Takes in a VVol UUID to identify what volume it is on the FlashArray. If a VVol UUID is not specified it will ask you for a VM and then a VMDK and will find the UUID for you.
  .INPUTS
    FlashArray connection(s) and VVol UUID.
  .OUTPUTS
    Returns volume name.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  06/03/2019
    Purpose/Change: Updated for new connection mgmt

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
      if ($vvolUUID -eq "")
      {
          throw "You must enter a VVol UUID"
      }
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
          $faSession = new-pfaRestSession -flasharray $fa 
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
          remove-pfaRestSession -faSession $faSession -flasharray $fa
          if ($null -ne $volumeName)
          {
            $Global:CurrentFlashArray = $null
          }
          else {
            $Global:CurrentFlashArray = $fa
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
function get-pfaSnapshotsFromVvolHardDisk {
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
      Creation Date:  05/29/2019
      Purpose/Change: Updated for new connection mgmt
  
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
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $faSession = new-pfaRestSession -flasharray $fa 
    $purevip = $fa.EndPoint
    $vvolUuid = get-vvolUuidFromHardDisk -vmdk $vmdk
    $faVolume = get-pfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid 
    $volumeSnaps = Invoke-RestMethod -Method Get -Uri "https://${purevip}/api/$($fa.apiversion)/volume/${faVolume}?snap=true" -WebSession $faSession -ErrorAction Stop
    $snapNames = @()
    foreach ($volumeSnap in $volumeSnaps)
    {
        $snapNames += $volumeSnap.name 
    }
    return $snapNames
}
function copy-pfaVvolVmdkToNewVvolVmdk {
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
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $vvolUuid = get-vvolUuidFromHardDisk -vmdk $vmdk 
    $faVolume = get-pfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid 
    $newHardDisk = New-HardDisk -Datastore $datastore -CapacityGB $vmdk.CapacityGB -VM $targetVm 
    $newVvolUuid = get-vvolUuidFromHardDisk -vmdk $newHardDisk 
    $newFaVolume = get-pfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $newVvolUuid 
    New-PfaVolume -Array $fa -Source $faVolume -Overwrite -VolumeName $newFaVolume  |Out-Null
    return $newHardDisk
}
function copy-pfaSnapshotToExistingVvolVmdk {
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
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $vvolUuid = get-vvolUuidFromHardDisk -vmdk $vmdk 
    $faVolume = get-pfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid
    $foundSnap = Get-PfaVolumeSnapshot -Array $fa -SnapshotName $snapshotName
    if ($null -eq $foundSnap)
    {
        throw "The snapshot either does not exist, or is not on the same array as the target VVol."
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
        throw "The target VVol hard disk is larger than the snapshot size and VMware does not allow hard disk shrinking."
    } 
    return $vmdk    
}
function copy-pfaSnapshotToNewVvolVmdk {
    <#
    .SYNOPSIS
      Takes an snapshot and overwrites an existing VVol virtual disk from it.
    .DESCRIPTION
      Takes an snapshot and overwrites an existing VVol virtual disk from it.
    .INPUTS
      FlashArray connection information, a datastore, target VM, and a source snapshot
    .OUTPUTS
      Returns the hard disk.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  06/04/2019
      Purpose/Change: Updated for new connection mgmt
  
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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$targetVm,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray,

            [Parameter(Position=3,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
    )
    if (($null -eq $flasharray) -and ($null -ne $datastore))
    {
        if ($datastore.type -ne "VVOL")
        {
            throw "This is not a VVol datastore."
        }
        $flasharray = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    elseif (($null -eq $flasharray) -and ($null -eq $datastore))
    {
        try {
          $flasharray = checkDefaultFlashArray
        }
        catch {
          throw "You must either pass in a FlashArray, a VVol datastore, or configure a default FlashArray connection."
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
    $newFaVolume = get-pfaVolumeNameFromVvolUuid -flasharray $flasharray -vvolUUID $newVvolUuid 
    New-PfaVolume -Array $flasharray -Source $snapshotName -Overwrite -VolumeName $newFaVolume  |Out-Null
    return $newHardDisk      
}
function copy-pfaVvolVmdkToExistingVvolVmdk {
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
      Creation Date:  06/04/2019
      Purpose/Change: Updated for new connection mgmt
  
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
        $targetFlasharray = get-pfaConnectionOfDatastore -datastore $targetDatastore -ErrorAction Stop
    }
    else 
    {
        $targetFlasharray = get-pfaConnectionOfDatastore -datastore $targetDatastore -flasharrays $flasharray -ErrorAction Stop
    } 
    if ($sourceDatastore.ExtensionData.info.vvolDS.storageArray[0].uuid -eq $targetDatastore.ExtensionData.info.vvolDS.storageArray[0].uuid)
    {
        $vvolUuid = get-vvolUuidFromHardDisk -vmdk $sourceVmdk 
        $sourceFaVolume = get-pfaVolumeNameFromVvolUuid -flasharray $targetFlasharray -vvolUUID $vvolUuid 
        $vvolUuid = get-vvolUuidFromHardDisk -vmdk $targetVmdk 
        $targetFaVolume = get-pfaVolumeNameFromVvolUuid -flasharray $targetFlasharray -vvolUUID $vvolUuid
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
function new-pfaSnapshotOfVvolVmdk {
    <#
    .SYNOPSIS
      Takes a VVol virtual disk and creates a FlashArray snapshot.
    .DESCRIPTION
      Takes a VVol virtual disk and creates a snapshot of it.
    .INPUTS
      FlashArray connection information and a virtual disk.
    .OUTPUTS
      Returns the snapshot name.
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  05/28/2019
      Purpose/Change: Updated for new connection mgmt
  
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
              $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
          }
          else 
          {
              $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
          }
          $vvolUuid = get-vvolUuidFromHardDisk -vmdk $vmdkDisk -ErrorAction Stop
          $faVolume = get-pfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid -ErrorAction Stop
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

function get-vmdkFromWindowsDisk {
    <#
    .SYNOPSIS
      Returns the VM disk object that corresponds to a given Windows file system
    .DESCRIPTION
      Takes in a drive letter and a VM object and returns a matching VMDK object
    .INPUTS
      VM, Drive Letter
    .OUTPUTS
      Returns VMDK object 
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  08/24/2018
      Purpose/Change: Updated for new connection mgmt
  
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
    Begin 
    {
      if ($null -eq $global:defaultviserver)
      {
        throw "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
      }
    }
    Process 
    {
      if ($null -eq $vm)
      {
          try {
              $vmName = Read-Host "Please enter in the name of your VM" 
              $vm = get-vm -name $vmName -ErrorAction Stop 
          }
          catch {
              throw $Global:Error[0]
          }
      }
      try {
          $guest = $vm |Get-VMGuest
      }
      catch {
          throw $Error[0]
      }
      if ($guest.State -ne "running")
      {
          throw "This VM does not have VM tools running"
      }
      if ($guest.GuestFamily -ne "windowsGuest")
      {
          throw "This is not a Windows VM--it is $($guest.OSFullName)"
      }
      try {
          $advSetting = Get-AdvancedSetting -Entity $vm -Name Disk.EnableUUID -ErrorAction Stop
      }
      catch {
          throw $Error[0]
      }
      if ($advSetting.value -eq "FALSE")
      {
          throw "The VM $($vm.name) has the advanced setting Disk.EnableUUID set to FALSE. This must be set to TRUE for this cmdlet to work."    
      }
      if (($null -eq $driveLetter) -or ($driveLetter -eq ""))
      {
          try {
              $driveLetter = Read-Host "Please enter in a drive letter" 
              if (($null -eq $driveLetter) -or ($driveLetter -eq ""))
              {
                  throw "No drive letter entered"
              }
          }
          catch {
              throw $Global:Error[0]
          }
      }
      try {
          $VMdiskSerialNumber = $vm |Invoke-VMScript -ScriptText "get-partition -driveletter $($driveLetter) | get-disk | ConvertTo-CSV -NoTypeInformation"  -WarningAction silentlyContinue -ErrorAction Stop |ConvertFrom-Csv
      }
      catch {
              throw $Error[0]
          }
      if (![bool]($VMDiskSerialNumber.PSobject.Properties.name -match "serialnumber"))
      {
          throw ($VMdiskSerialNumber |Out-String) 
      }
      try {
          $vmDisk = $vm | Get-HardDisk |Where-Object {$_.ExtensionData.backing.uuid.replace("-","") -eq $VMdiskSerialNumber.SerialNumber}
      }
      catch {
          throw $Global:Error[0]
      }
    }
  End 
  {
    if ($null -ne $vmDisk)
    {
        return $vmDisk
    }
    else {
        throw "Could not match the VM disk to a VMware virtual disk"
    }
  }  
}

function checkDefaultFlashArray{
    if ($null -eq $Global:DefaultFlashArray)
    {
        throw "You must pass in a FlashArray connection or create a default FlashArray connection with new-pfaconnection"
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
      throw "Please either pass in one or more FlashArray connections or create connections via the new-pfaConnection cmdlet."
  }
}
New-Alias -Name update-faVvolVmVolumeGroup -Value update-pfaVvolVmVolumeGroup
New-Alias -Name get-faSnapshotsFromVvolHardDisk -Value get-pfaSnapshotsFromVvolHardDisk
New-Alias -Name copy-faVvolVmdkToNewVvolVmdk -Value copy-pfaVvolVmdkToNewVvolVmdk
New-Alias -Name copy-faSnapshotToExistingVvolVmdk -Value copy-pfaSnapshotToExistingVvolVmdk
New-Alias -Name copy-faSnapshotToNewVvolVmdk -Value copy-pfaSnapshotToNewVvolVmdk
New-Alias -Name copy-faVvolVmdkToExistingVvolVmdk -Value copy-pfaVvolVmdkToExistingVvolVmdk
New-Alias -Name new-faSnapshotOfVvolVmdk -Value new-pfaSnapshotOfVvolVmdk
New-Alias -Name get-faVolumeNameFromVvolUuid -Value get-pfaVolumeNameFromVvolUuid