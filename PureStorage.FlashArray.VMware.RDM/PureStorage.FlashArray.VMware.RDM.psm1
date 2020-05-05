$ErrorActionPreference = 'Stop'
function New-PfaRDM {
    <#
    .SYNOPSIS
      Creates a new Raw Device Mapping for a VM
    .DESCRIPTION
      Creates a new volume on a FlashArray and presents it to a VM as a RDM. Optionally can also be created from a snapshot
    .INPUTS
      FlashArray connection, volume name, capacity, virtual machine, SCSI adapter.
    .OUTPUTS
      FlashArray volume name
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/09/2019
      Purpose/Change: Added examples parameter sets/validation
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $vm = get-vm myVM
      PS C:\ New-PfaRDM -vm $vm -sizeInTb 1
      
      Creates a new 1 TB RDM and presents it to a VM on the default FlashArray.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
      PS C:\ $vm = get-vm myVM
      PS C:\ New-PfaRDM -vm $vm -sizeInTb 1 -flasharray $fa
      
      Creates a new 1 TB RDM and presents it to a VM on the specified FlashArray.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
      PS C:\ $vm = get-vm myVM
      PS C:\ New-PfaRDM -vm $vm -sizeInTb 1 -flasharray $fa -snapshot vol1.mySnapshot
      
      Creates a RDM from the volume snapshot vol1.mySnapshot and presents it to a VM on the specified FlashArray.

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
            [PurePowerShell.PureArray]$flasharray,
            
            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,

            [Parameter(Position=2)]
            [string]$volName,

            [ValidateRange(1,63488)]
            [Parameter(ParameterSetName='GB',Position=3)]
            [int]$sizeInGB =0,

            [ValidateRange(1,62)]
            [Parameter(ParameterSetName='TB',Position=4)]
            [int]$sizeInTB = 0,

            [ValidateScript({
              if ($_.Type -ne 'VMFS')
              {
                  throw "The entered datastore is not a VMFS datastore. It is type $($_.Type). Please only enter a VMFS datastore"
              }
              else {
                $true
              }
            })]
            [Parameter(Position=5,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=6,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.ScsiController]$scsiController,

            [Parameter(ParameterSetName='Snapshot',Position=7)]
            [string]$snapshotName
    )
    if ($null -eq $flasharray)
    {
      $flasharray = checkDefaultFlashArray
    }
    if ($sizeInGB -ne 0) 
    {
      $volSize = $sizeInGB * 1024 *1024 *1024   
    }
    else 
    {
      $volSize = $sizeInTB * 1024 *1024 *1024 * 1024
    }
    $ErrorActionPreference = "stop"
    if ($volName -eq "")
    {
        $rand = get-random -Maximum 9999 -Minimum 1000
        $volName = "$($vm.Name)-rdm$($rand)"
        if ($volName -notmatch "^[a-zA-Z0-9\-]+$")
        {
            $volName = $volName -replace "[^\w\-_]", ""
            $volName = $volName -replace " ", ""
        }
    }
    if ($null -eq $datastore)
    {
        $vmDatastore = Get-Datastore -vm $vm
        if ($vmDatastore.count -gt 1)
        {
            $ds = get-datastore (($vm.ExtensionData.Layoutex.file |where-object {$_.name -like "*.vmx*"}).name.split("]")[0].substring(1))
            if ($ds.Type -ne 'VMFS')
            {
                throw "The home datastore for this VM (a datastore named $($ds.name)) is not a VMFS datastore. It is type $($ds.Type). Please pass in a target VMFS datastore for the RDM pointer file."
            }
            else {
              $datastore = $ds
            }
        }
        else {
            $datastore = $vmDatastore[0]
        }
    }
    $cluster = $vm | get-cluster
    if ($null -eq $cluster)
    {
        throw "This VM is not on a host in a cluster. Non-clustered hosts are not supported by this script."     
    }
    $hostGroup = $cluster | get-pfaHostGroupfromVcCluster -flasharray $flasharray -ErrorAction Stop
    if ($snapshotName -ne "")
    {
        $newVol = New-PfaVolume -Array $flasharray -VolumeName $volName -Source $snapshotName -ErrorAction Stop
    }
    else {
        $newVol = New-PfaVolume -Array $flasharray -Size $volSize -VolumeName $volName -ErrorAction Stop
    }
    New-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $newVol.name -HostGroupName $hostGroup.name |Out-Null
    $esxiHosts = $cluster| Get-VMHost 
    foreach ($esxiHost in $esxiHosts)
    {
        $esxi = $esxiHost.ExtensionData
        $storageSystem = Get-View -Id $esxi.ConfigManager.StorageSystem
        $hbas = ($esxihost |Get-VMHostHba |where-object {$_.Type -eq "FibreChannel" -or $_.Type -eq "iSCSI"}).device
        foreach ($hba in $hbas) {
            $storageSystem.rescanHba($hba)
        }
    }
    $newNAA =  "naa.624a9370" + $newVol.serial.toLower()
    if($null -eq $scsiController)
    {
        $controller = $vm |Get-ScsiController 
        if ($controller.count -gt 1)
        {
            $pvSCSIs = $vm |Get-ScsiController |Where-Object {$_.Type -eq "ParaVirtual"}
            if ($pvSCSIs.count -gt 1)
            {
                $pvDisksHigh = 1000
                foreach ($pvSCSI in $pvSCSIs)
                {
                    $pvDisks = ($vm | Get-HardDisk | Where-Object {$_.ExtensionData.ControllerKey -eq $pvSCSI.key}).count
                    if ($pvDisksHigh -ge $pvDisks)
                    {
                        $pvDisksHigh = $pvDisks
                        $controller = $pvSCSI
                    }
                }
            }
            elseif ($pvSCSIs.count -eq 1)
            {
                $controller = $pvSCSIs
            }
            else 
            {
                $lsiSCSIs = $vm |Get-ScsiController 
                if ($lsiSCSIs.count -gt 1)
                {
                    $lsiDisksHigh = 1000
                    foreach ($lsiSCSI in $lsiSCSIs)
                    {
                        $lsiDisks = ($vm | Get-HardDisk | Where-Object {$_.ExtensionData.ControllerKey -eq $lsiSCSI.key}).count
                        if ($lsiDisksHigh -ge $lsiDisks)
                        {
                            $lsiDisksHigh = $lsiDisks
                            $controller = $lsiSCSI
                        }
                    }
                }
                else
                {
                    $controller = $lsiSCSIs
                }
            }
        }   
    } 
    else {
        $controller = $scsiController
    }
    try {
        $newRDM = $vm | new-harddisk -DeviceName "/vmfs/devices/disks/$($newNAA)" -DiskType RawPhysical -Controller $controller -Datastore $datastore -ErrorAction stop
        $rdmDisk = $vm |Get-harddisk |where-object {$_.DiskType -eq "RawPhysical"}|  where-object {$null -ne $_.extensiondata.backing.lunuuid} |Where-Object {("naa." + $_.ExtensionData.Backing.LunUuid.substring(10).substring(0,32)) -eq $newNAA}
        return $rdmDisk
    }
    catch {
        Remove-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $newvol.name -HostGroupName $hostGroup.name|Out-Null
        Remove-PfaVolumeOrSnapshot -Array $flasharray -Name $newvol.name |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $flasharray -Eradicate:$true -Name $newvol.name |Out-Null
        throw $PSItem
    }       
}
function Get-PfaRDMVol {
    <#
    .SYNOPSIS
      Retrieves the FlashArray volume that hosts a RDM disk.
    .DESCRIPTION
      Takes in a RDM virtual disk and a FlashArray and returns the volume if found.
    .INPUTS
      FlashArray connection and a virtual disk.
    .OUTPUTS
      Returns FlashArray volume or error if not found.
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/09/2019
      Purpose/Change: Added examples, validation to parameters.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
      PS C:\ $rdm = get-harddisk myVM |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Get-PfaRDMVol -rdm $rdm

      Returns the FlashArray volume hosting the RDM if it is on one of the connected FlashArrays.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
      PS C:\ $rdm = get-vm myVM | get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Get-PfaRDMVol -rdm $rdm -flasharray $fa
      
      Returns the FlashArray volume hosting the RDM if it is on the specified FlashArray.
    
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
            [ValidateScript({
              if ($_.DiskType -ne 'RawPhysical')
              {
                  throw "The entered virtual disk is not a Physical Mode RDM. It is type $($_.DiskType). Please only enter a physical mode RDM"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$rdm,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
    )
      $lun = ("naa." + $rdm.ExtensionData.Backing.LunUuid.substring(10).substring(0,32))
      if ($null -eq $flasharray)
      {
        $flasharray = getAllFlashArrays 
      }
      if ($lun -like 'naa.624a9370*')
      {
          $volSerial = ($lun.ToUpper()).substring(12)
          foreach ($fa in $flasharray)
          {
              $purevol =  Get-PfaVolumes -Array  $fa -Filter "serial='$volSerial'"
              if ($null -ne $purevol)
              {
                $Global:CurrentFlashArray = $fa
                return $purevol
              }
          }
      }
      else {
          throw "Specified RDM is not hosted on FlashArray storage."
      }
      throw "Specified RDM was not found on the passed in FlashArrays."
}
function Get-PfaConnectionFromRDM {
  <#
  .SYNOPSIS
    Retrieves the FlashArray connection of a volume that hosts a RDM disk.
  .DESCRIPTION
    Takes in a RDM virtual disk and optionally a set of FlashArray connections and returns the connection if found.
  .INPUTS
    FlashArray connection(s) and a virtual disk.
  .OUTPUTS
    Returns FlashArray connection or error if not found.
  .NOTES
     Version:        2.1
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  12/09/2019
    Purpose/Change: Added examples, validation to parameters.
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
    PS C:\ $rdm = get-vm myVM |get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
    PS C:\ Get-pfaConnectionfromRDM -rdm $rdm

    Returns the FlashArray connection hosting the RDM if it is on one of the connected FlashArrays.
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
    PS C:\ $rdm = get-vm myVM | get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
    PS C:\ Get-pfaConnectionfromRDM -rdm $rdm -flasharray $fa
    
     Returns the FlashArray connection hosting the RDM if it is on the specified FlashArray.
    
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
          [ValidateScript({
            if ($_.DiskType -ne 'RawPhysical')
            {
                throw "The entered virtual disk is not a Physical Mode RDM. It is type $($_.DiskType). Please only enter a physical mode RDM"
            }
            else {
              $true
            }
          })]
          [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$rdm,

          [Parameter(Position=1,ValueFromPipeline=$True)]
          [PurePowerShell.PureArray[]]$flasharray
  )
    $lun = ("naa." + $rdm.ExtensionData.Backing.LunUuid.substring(10).substring(0,32))
    if ($null -eq $flasharray)
    {
      $flasharray = getAllFlashArrays 
    }
    if ($lun -like 'naa.624a9370*')
    {
        $volSerial = ($lun.ToUpper()).substring(12)
        foreach ($fa in $flasharray)
        {
            $purevol =  Get-PfaVolumes -Array  $fa -Filter "serial='$volSerial'"
            if ($null -ne $purevol)
            {
              $Global:CurrentFlashArray = $fa
              return $fa
            }
        }
    }
    else {
        throw "Specified RDM is not hosted on FlashArray storage."
    }
    throw "Specified RDM was not found on the passed in FlashArrays."
}
function New-PfaRDMSnapshot {
    <#
    .SYNOPSIS
      Creates a new FlashArray snapshot of one or more given RDMs
    .DESCRIPTION
      Takes in a RDM disk and the corresponding FlashArray and creates a snapshot.
    .INPUTS
      FlashArray connection and a RDM disk
    .OUTPUTS
      Returns created snapshot.
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/09/2019
      Purpose/Change: Added examples, validation to parameters.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $rdm = get-vm myVM |get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ new-PfaRDMSnapshot -rdm $rdm

      Creates a snapshot of the FlashArray volume hosting the RDM.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $rdm = get-vm myVM |get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ new-PfaRDMSnapshot -rdm $rdm -suffix newSnap

      Creates a snapshot called newSnap of the FlashArray volume hosting the RDM.

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
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=1,mandatory=$True,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk[]]$rdm,

            [Parameter(Position=2)]
            [string]$suffix
    )
    Begin {
        $allSnaps = @()
    }
    Process {
        foreach ($rdmDisk in $rdm)
        {
            $fa = get-pfaConnectionfromRDM -rdm $rdmDisk -flasharray $flasharray -ErrorAction Stop
            $pureVol = $rdmDisk | get-faVolfromRDM -flasharray $fa -ErrorAction Stop
            $Global:CurrentFlashArray = $fa
            if ($suffix -eq "")
            {
                $newSnapshot = New-PfaVolumeSnapshots -Array $fa -Sources $pureVol.name  
            }
            else {
                $newSnapshot = New-PfaVolumeSnapshots -Array $fa -Sources $pureVol.name -Suffix $suffix
            }
            $allSnaps += $newSnapshot
        }
        
    }
    End {
        return $allSnaps
    }  
}
function Get-PfaRDMSnapshot {
    <#
    .SYNOPSIS
      Retrieves snapshots of a FlashArray-based RDM
    .DESCRIPTION
      Pass in a RDM disk and this will returns all of the FlashArray snapshots
    .INPUTS
      FlashArray connection and a RDM-based disk.
    .OUTPUTS
      Returns FlashArray snapshot(s).
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/10/2019
      Purpose/Change: Added RDM Validation
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $rdm = get-vm myVM |get-harddisk  |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Get-PfaRDMSnapshot -rdm $rdm

      REturns all FlashArray snapshots of the volume hosting the RDM.
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
            [ValidateScript({
              if ($_.DiskType -ne 'RawPhysical')
              {
                  throw "The entered virtual disk is not a Physical Mode RDM. It is type $($_.DiskType). Please only enter a physical mode RDM"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$rdm,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
    )
      if ($null -eq $flasharray)
      {
        $flasharray = getAllFlashArrays 
      }
      $fa = get-pfaConnectionlfromRDM -rdm $rdm -flasharray $flasharray -ErrorAction Stop
      $pureVol = $rdm | get-faVolfromRDM -flasharray $fa 
      $snapshots = Get-PfaVolumeSnapshots -Array $fa -VolumeName $pureVol.name 
      return $snapshots
}
function Copy-PfaSnapshotToRDM {
    <#
    .SYNOPSIS
      Input a FlashArray RDM and a snapshot to refresh the RDM
    .DESCRIPTION
      Pass in a RDM disk and a snapshot and it will copy the snapshot to the RDM FlashArray volume
    .INPUTS
      FlashArray connection, a snapshot, and a RDM-based disk.
    .OUTPUTS
      Returns the RDM disk
    .NOTES
      Version:        2.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  05/28/2019
      Purpose/Change: Updated for new connection mgmt
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $rdm = get-vm myVM | get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Copy-PfaSnapshotToRDM -rdm $rdm -suffix mySnapshot -offlineConfirm
      
      Removes the RDM, refreshes it from a snapshot and adds it back to the VM.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
      PS C:\ $rdm = get-vm myVM | get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Copy-PfaSnapshotToRDM -rdm $rdm -flasharray $fa -suffix mySnapshot -offlineConfirm
      
      Removes the RDM, refreshes it from a snapshot and adds it back to the VM.

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
            [ValidateScript({
              if ($_.DiskType -ne 'RawPhysical')
              {
                  throw "The entered virtual disk is not a Physical Mode RDM. It is type $($_.DiskType). Please only enter a physical mode RDM"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$rdm,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=2)]
            [string]$snapshot,

            [Parameter(Position=3,mandatory=$True)]
            [switch]$offlineConfirm
    )
        if ($offlineConfirm -ne $true)
        {
            throw "FlashArray volumes can be resized online, but VMware does not permit it with RDMs. Please confirm you will allow the RDM to go offline temporarily for the resize operation with the -offlineConfirm parameter."
        }
        if ($snapshot -eq "")
        {
            throw "You must enter a snapshot source"
        }
        if ($null -eq $flasharray)
        {
          $flasharray = getAllFlashArrays 
        }
        $fa = get-pfaConnectionlfromRDM -rdm $rdm -flasharray $flasharray -ErrorAction Stop
        $sourceVol = $rdm | get-faVolfromRDM -flasharray $fa 
        $vm = $rdm.Parent
        $controller = $rdm |Get-ScsiController
        $datastore = $rdm |Get-Datastore
        Remove-HardDisk $rdm -DeletePermanently -Confirm:$false
        $refreshedVol = New-PfaVolume -Array $fa -VolumeName $sourceVol.name -Source $snapshot -Overwrite -ErrorAction Stop
        $esxiHosts = $rdm.Parent | Get-VMHost 
        foreach ($esxiHost in $esxiHosts)
        {
            $esxi = $esxiHost.ExtensionData
            $storageSystem = Get-View -Id $esxi.ConfigManager.StorageSystem
            $hbas = ($esxihost |Get-VMHostHba |where-object {$_.Type -eq "FibreChannel" -or $_.Type -eq "iSCSI"}).device
            foreach ($hba in $hbas) {
                $storageSystem.rescanHba($hba)
            }
            $storageSystem.RefreshStorageSystem()
        }
        $newNAA =  "naa.624a9370" + $refreshedVol.serial.toLower()
        $updatedRDM = $vm | new-harddisk -DeviceName "/vmfs/devices/disks/$($newNAA)" -DiskType RawPhysical -Controller $controller -Datastore $datastore -ErrorAction stop
        $rdmDisk = $vm |Get-harddisk |where-object {$_.DiskType -eq "RawPhysical"}|  where-object {$null -ne $_.extensiondata.backing.lunuuid} |Where-Object {("naa." + $_.ExtensionData.Backing.LunUuid.substring(10).substring(0,32)) -eq $newNAA}
        return $rdmDisk
}
function Set-PfaRDMCapacity {
    <#
    .SYNOPSIS
      Resizes the RDM volume
    .DESCRIPTION
      Takes in a new size and resizes the underlying volume and rescans the VMware environment
    .INPUTS
      Takes in a RDM virtual disk, a FlashArray, and a new size.
    .OUTPUTS
      Returns RDM disk.
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/10/2019
      Purpose/Change: Added validation and parameter sets
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $rdm = get-vm myVM |get-harddisk  |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Set-PfaRDMCapacity -rdm $rdm -sizeInTb 1 -offlineConfirm
      
      Resizes the RDM to a larger capacity
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nondefaultArray
      PS C:\ $rdm = get-vm myVM |get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Set-PfaRDMCapacity -rdm $rdm -sizeInTb 1 -offlineConfirm -truncate
      
      Resizes the RDM to a smaller capacity

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
            [ValidateScript({
              if ($_.DiskType -ne 'RawPhysical')
              {
                  throw "The entered virtual disk is not a Physical Mode RDM. It is type $($_.DiskType). Please only enter a physical mode RDM"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$rdm,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(ParameterSetName='GB',Position=2)]
            [ValidateRange(1,63488)]
            [int]$sizeInGB = 0,

            [Parameter(ParameterSetName='TB',Position=3)]
            [ValidateRange(1,62)]
            [int]$sizeInTB = 0,

            [Parameter(Position=4)]
            [switch]$truncate,

            [Parameter(Position=5,mandatory=$True)]
            [switch]$offlineConfirm
    )
    if ($offlineConfirm -ne $true)
    {
        throw "FlashArray volumes can be resized online, but VMware does not permit it with RDMs. Please confirm you will allow the RDM to go offline temporarily for the resize operation with the -offlineConfirm parameter."
    }
    if (($sizeInGB -eq 0) -and ($sizeInTB -eq 0))
    {
        throw "Please enter a size in GB or TB"
    }
   if ($sizeInGB -ne 0) {
        $volSize = $sizeInGB * 1024 *1024 *1024   
    }
    else {
        $volSize = $sizeInTB * 1024 *1024 *1024 * 1024
    }
    if ($null -eq $flasharray)
    {
      $flasharray = getAllFlashArrays 
    }
    $fa = get-pfaConnectionlfromRDM -rdm $rdm -flasharray $flasharray -ErrorAction Stop
    $pureVol = $rdm | get-faVolfromRDM -flasharray $fa 
    if (($truncate -ne $true) -and ($pureVol.size -gt $volSize))
    {
        throw "This operation will shrink the target RDM--please ensure this is expected and if so, please rerun the operation with the -truncate parameter."
    }
    $vm = $rdm.Parent
    $controller = $rdm |Get-ScsiController
    $datastore = $rdm |Get-Datastore
    Remove-HardDisk $rdm -DeletePermanently -Confirm:$false
    if ($truncate -eq $true)
    {
        $expandedVol = Resize-PfaVolume -Array $fa -VolumeName $pureVol.name -NewSize $volSize -Truncate
    }
    else {
        $expandedVol = Resize-PfaVolume -Array $fa -VolumeName $pureVol.name -NewSize $volSize 
    }
    $esxiHosts = $rdm.Parent| Get-VMHost 
    foreach ($esxiHost in $esxiHosts)
    {
        $esxi = $esxiHost.ExtensionData
        $storageSystem = Get-View -Id $esxi.ConfigManager.StorageSystem
        $hbas = ($esxihost |Get-VMHostHba |where-object {$_.Type -eq "FibreChannel" -or $_.Type -eq "iSCSI"}).device
        foreach ($hba in $hbas) {
            $storageSystem.rescanHba($hba)
        }
        $storageSystem.RefreshStorageSystem()
    }
    $expandedVol = Get-PfaVolume -Name $expandedVol.name -Array $flasharray
    $newNAA =  "naa.624a9370" + $expandedVol.serial.toLower()
    $vm | new-harddisk -DeviceName "/vmfs/devices/disks/$($newNAA)" -DiskType RawPhysical -Controller $controller -Datastore $datastore -ErrorAction stop |Out-Null
    $rdmDisk = $vm |Get-harddisk |where-object {$_.DiskType -eq "RawPhysical"}|  where-object {$null -ne $_.extensiondata.backing.lunuuid} |Where-Object {("naa." + $_.ExtensionData.Backing.LunUuid.substring(10).substring(0,32)) -eq $newNAA}
    return $rdmDisk
}
function Remove-PfaRDM {
    <#
    .SYNOPSIS
      Removes one or more RDM volumes
    .DESCRIPTION
      Deletes the virtual disk pointer to the RDM and deletes the volume on the FlashArray. Volume will be deleted permanently in 24 hours
    .INPUTS
      Takes in one or more RDM virtual disks and optionally one or more FlashArray connections.
    .OUTPUTS
      Returns destroyed FA volume(s).
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/10/2019
      Purpose/Change: Added RDM type handling
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $rdm = get-vm myVM |get-harddisk  |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Remove-PfaRDM -rdm $rdm
      
      Removes the RDM and destroys the volume on the FlashArray

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
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk[]]$rdm,

            [Parameter(Position=1)]
            [PurePowerShell.PureArray[]]$flasharray
    )
    Begin {
        $destroyedVols = @()
        $esxiHosts = @()
    }
    Process {
        foreach ($rdmDisk in $rdm)
        {
            if ($rdmDisk.DiskType -ne 'RawPhysical')
            {
              throw "The input disk $($rdmDisk.Name) is not an RDM."
            }
            if ($null -eq $flasharray)
            {
              $flasharray = getAllFlashArrays 
            }
            $fa = get-pfaConnectionfromRDM -rdm $rdmDisk -flasharray $flasharray
            $pureVol = $rdmDisk | get-faVolfromRDM -flasharray $fa 
            $esxiHosts += $rdmDisk.Parent|get-cluster| Get-VMHost 
            Remove-HardDisk $rdmDisk -DeletePermanently -Confirm:$false
            $hostConnections = Get-PfaVolumeHostConnections -Array $fa -VolumeName $pureVol.name
            if ($hostConnections.count -gt 0)
            {
                foreach ($hostConnection in $hostConnections)
                {
                    Remove-PfaHostVolumeConnection -Array $fa -VolumeName $pureVol.name -HostName $hostConnection.host |Out-Null
                } 
            }
            $hostGroupConnections = Get-PfaVolumeHostGroupConnections -Array $fa -VolumeName $pureVol.name
            if ($hostGroupConnections.count -gt 0)
            {
                $hostGroupConnections = $hostGroupConnections.hgroup |Select-Object -unique
                foreach ($hostGroupConnection in $hostGroupConnections)
                {
                    Remove-PfaHostGroupVolumeConnection -Array $fa -VolumeName $pureVol.name -HostGroupName $hostGroupConnection |Out-Null
                } 
            }
          $destroyedVol =  Remove-PfaVolumeOrSnapshot -Array $fa -Name $pureVol.name 
          $destroyedVols += $destroyedVol
        }
    }
    End {
        $esxiHostsUnique = $esxiHosts |Select-Object -Unique
        foreach ($esxiHost in $esxiHostsUnique)
        {
            $esxi = $esxiHost.ExtensionData
            $storageSystem = Get-View -Id $esxi.ConfigManager.StorageSystem
            $hbas = ($esxihost |Get-VMHostHba |where-object {$_.Type -eq "FibreChannel" -or $_.Type -eq "iSCSI"}).device
            foreach ($hba in $hbas) {
                $storageSystem.rescanHba($hba)
            }
        }
        return $destroyedVols
    }  
}
function Convert-PfaRDMToVvol {
    <#
    .SYNOPSIS
      Converts a RDM to a VVol
    .DESCRIPTION
      Removes the RDM from the virtual machine and copies it to a new VVol and destroys the old RDM.
    .INPUTS
      Takes in a RDM virtual disk, a FlashArray connection, and optionally a VVol datastore.
    .OUTPUTS
      Returns the new VVol virtual disk.
    .NOTES
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/16/2019
      Purpose/Change: Updated for examples, validation sets
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $rdm = get-vm myVM |get-harddisk |where-object {$_.DiskType -eq 'RawPhysical'}
      PS C:\ Convert-PfaRDMToVvol -rdm $rdm -offlineConfirm
      
      Removes the RDM and destroys the volume on the FlashArray

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
            [ValidateScript({
              if ($_.DiskType -ne 'RawPhysical')
              {
                  throw "The entered virtual disk is not a Physical Mode RDM. It is type $($_.DiskType). Please only enter a physical mode RDM"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.HardDisk]$rdm,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [ValidateScript({
              if ($_.Type -ne 'VVOL')
              {
                  throw "The entered datastore is not a vVol datastore. It is type $($_.Type). Please only enter a vVol datastore only."
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=3)]
            [switch]$offlineConfirm
    )
    $vm = $rdm.Parent
    if (($vm.PowerState -ne "PoweredOff") -and ($offlineConfirm -ne $true))
    {
        throw "The RDM to VVol migration is an offline process--please either shut down the VM or confirm this downtime with the -offlineConfirm parameter"
    }   
    if ($null -eq $flasharray)
    {
      $flasharray = getAllFlashArrays 
    }
    $fa = get-pfaConnectionlfromRDM -flasharray $flasharray -rdm $rdm -ErrorAction Stop
    $sourceVol = $rdm|get-faVolfromRDM -flasharray $fa -ErrorAction Stop
    $arraySerial = (Get-PfaArrayAttributes -array $fa).id
    if ($null -eq $datastore)
    {
        $datastores = $vm |get-vmhost |Get-Datastore |Where-Object {$_.Type -eq "VVOL"}
        foreach ($checkDatastore in $datastores)
        {
            if ($arraySerial -eq $checkDatastore.ExtensionData.Info.VvolDS.StorageArray[0].uuid.Substring(16))
            {
                #finding first VVol datastore on host running VM on same FlashArray
                $datastore = $checkDatastore
                break
            }
        }
        if ($null -eq $datastore)
        {
            throw "No vVol datastore found on ESXi host for input array. Please ensure one is mounted."
        }
    }
    else {
        if ($arraySerial -ne $datastore.ExtensionData.Info.VvolDS.StorageArray[0].uuid.Substring(16))
        {
            throw "The input datastore is not on the same array as the input FlashArray connection."
        }
    }
    $controller = $rdm |Get-ScsiController
    $volSize = $rdm.CapacityGB
    remove-faVolRDM -rdm $rdm -flasharray $fa -ErrorAction Stop |Out-Null
    $vvolVmdk = $vm | new-harddisk -CapacityGB $volSize -Controller $controller -Datastore $datastore -ErrorAction stop
    $vvolUuid = $vvolVmdk |get-vvolUuidFromHardDisk
    $targetVol = get-pfaVolumeNameFromVvolUuid -flasharray $fa -vvolUUID $vvolUuid
    Restore-PfaDestroyedVolume -Array $fa -Name $sourceVol.name |Out-Null
    New-PfaVolume -Array $fa -VolumeName $targetVol -Source $sourceVol.name -Overwrite -ErrorAction Stop |Out-Null
    Remove-PfaVolumeOrSnapshot -Array $fa -Name $sourceVol.name |Out-Null
    return $vvolVmdk
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
New-Alias -Name new-faVolRdm -Value New-PfaRdm
New-Alias -Name set-faVolRDMCapacity -Value Set-PfaRDMCapacity
New-Alias -Name copy-faSnapshotToRDM -Value copy-pfaSnapshotToRDM
New-Alias -Name get-faVolRDMSnapshots -Value get-pfaVolRDMSnapshot
New-Alias -Name new-faVolRdmSnapshot -Value Get-PfaRDMSnapshot
New-Alias -Name get-faVolfromRDM -Value Get-PfaRDMVol
New-Alias -Name remove-faVolRDM -Value Remove-PfaRDM 
New-Alias -Name convert-faVolRDMtoVvol -Value Convert-PfaRDMToVvol
New-Alias -Name new-pfaVolRdm -Value New-PfaRdm
New-Alias -Name set-pfaVolRDMCapacity -Value Set-PfaRDMCapacity
New-Alias -Name get-pfaVolRDMSnapshot -Value Get-PfaRDMSnapshot
New-Alias -Name new-pfaVolRdmSnapshot -Value New-PfaRDMSnapshot
New-Alias -Name get-pfaVolfromRDM -Value Get-PfaRDMVol
New-Alias -Name remove-pfaVolRDM -Value Remove-PfaRDM 
New-Alias -Name convert-pfaVolRDMtoVvol -Value Convert-PfaRDMToVvol
