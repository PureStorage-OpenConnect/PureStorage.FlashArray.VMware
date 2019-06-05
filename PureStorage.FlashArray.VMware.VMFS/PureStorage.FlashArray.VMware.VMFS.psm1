function get-pfaVolfromVMFS {
    <#
    .SYNOPSIS
      Retrieves the FlashArray volume that hosts a VMFS datastore.
    .DESCRIPTION
      Takes in a VMFS datastore and one or more FlashArrays and returns the volume if found.
    .INPUTS
      FlashArray connection(s) and a VMFS datastore.
    .OUTPUTS
      Returns FlashArray volume or null if not found.
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
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
    )
    if ($datastore.Type -ne 'VMFS')
    {
        throw "This is not a VMFS datastore."
    }
    if ($null -eq $flasharray)
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore
    }
    else {
      $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray
    }
    $pureVolumes = Get-PfaVolumes -Array  $fa
    $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
    $volserial = ($lun.ToUpper()).substring(12)
    $purevol = $purevolumes | where-object { $_.serial -eq $volserial }
    if ($null -ne $purevol.name)
    {
        return $purevol
    }
    else {
        throw "The volume was not found."
    }
}
function new-pfaVolVmfs {
    <#
    .SYNOPSIS
      Create a new VMFS on a new FlashArray volume 
    .DESCRIPTION
      Creates a new FlashArray-based VMFS and presents it to a cluster.
    .INPUTS
      FlashArray connection, a vCenter cluster, a volume size, and name.
    .OUTPUTS
      Returns a VMFS object.
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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=2,mandatory=$true)]
            [string]$volName,

            [Parameter(Position=3)]
            [int]$sizeInGB,

            [Parameter(Position=4)]
            [int]$sizeInTB
    )
    Begin {
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
        $newDatastores = @()
        $allFAs = @()
        $newNAAs = @()
        $volNames = @()
        $hostGroupNames = @()
        $oneVolume = 0
    }
    Process 
    {
        if ($null -eq $flasharray)
        {
          $flasharray = checkDefaultFlashArray
        }
        foreach ($fa in $flasharray)
        {
          try {
            $hostGroup = $cluster | get-pfaHostGroupfromVcCluster -flasharray $fa
          }  
          catch {
              for ($h =0; $h -lt $volNames.Count; $h++)
              {
                Remove-PfaHostGroupVolumeConnection -Array $allFAs[$h] -VolumeName $volNames[$h] -HostGroupName $hostGroupNames[$h] |Out-Null
                Remove-PfaVolumeOrSnapshot -Array $allFAs[$h] -Name $volNames[$h] |Out-Null
                Remove-PfaVolumeOrSnapshot -Array $allFAs[$h] -Name $volNames[$h] -Eradicate |Out-Null
              }
              $cluster | get-pfaHostGroupfromVcCluster -flasharray $fa -ErrorAction Stop
          }
            if ($oneVolume -gt 0)
            {
              if ($oneVolume -eq 1)
              {
                $nameSuffix = ("-" + (get-random -Maximum 9999 -Minimum 1000))
                Rename-PfaVolumeOrSnapshot -Array $lastFA -Name $volName -NewName ($volName + $nameSuffix) |Out-Null
                $volNames[0] = ($volName + "-" + $nameSuffix)
                $newName = ($volName + "-" + (get-random -Maximum 9999 -Minimum 1000))
              }
              else {
                $newName = ($volName + "-" + (get-random -Maximum 9999 -Minimum 1000))
              }
            }
            else {
              $newName = $volName
            }
            $newVol = New-PfaVolume -Array $fa -Size $volSize -VolumeName $newName -ErrorAction Stop
            $Global:CurrentFlashArray = $fa
            $lastFA = $fa
            New-PfaHostGroupVolumeConnection -Array $fa -VolumeName $newVol.name -HostGroupName $hostGroup.name |Out-Null
            $newNAAs +=  "naa.624a9370" + $newVol.serial.toLower()
            $allFAs += $fa
            $volNames += $newVol.name
            $hostGroupNames += $hostGroup.name 
            $oneVolume++
        }
    }
    End 
    {
        $esxi = $cluster | get-vmhost | where-object {($_.version -like '5.5.*') -or ($_.version -like '6.*')}| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1
        $cluster| Get-VMHost | Get-VMHostStorage -RescanAllHba |Out-Null
        $ESXiApiVersion = $esxi.ExtensionData.Summary.Config.Product.ApiVersion
        $varCount = 0
        foreach ($newNAA in $newNAAs)
        {  
          Write-Debug -Message $newNAA
            try 
            {
                if (($ESXiApiVersion -eq "5.5") -or ($ESXiApiVersion -eq "6.0") -or ($ESXiApiVersion -eq "5.1"))
                {
                    $newVMFS = $esxi |new-datastore -name $volNames[$varCount] -vmfs -Path $newNAAs[$varCount] -FileSystemVersion 5 -ErrorAction Stop
                }
                else
                {
                    $newVMFS = $esxi |new-datastore -name $volNames[$varCount] -vmfs -Path $newNAAs[$varCount] -FileSystemVersion 6 -ErrorAction Stop
                }
                $newDatastores += $newVMFS
            }
            catch {
                Write-Error $Global:Error[0]
                Remove-PfaHostGroupVolumeConnection -Array $allFAs[$varCount] -VolumeName $volNames[$varCount] -HostGroupName $hostGroupNames[$varCount] |Out-Null
                Remove-PfaVolumeOrSnapshot -Array $allFAs[$varCount] -Name $volNames[$varCount] |Out-Null
                Remove-PfaVolumeOrSnapshot -Array $allFAs[$varCount] -Name $volNames[$varCount] -Eradicate |Out-Null
            }
            $varCount++
        }
        
      return $newDatastores
    }
}
function add-pfaVolVmfsToCluster {
    <#
    .SYNOPSIS
      Add an existing FlashArray-based VMFS to another VMware cluster.
    .DESCRIPTION
      Takes in a vCenter Cluster and a datastore and the corresponding FlashArray
    .INPUTS
      FlashArray connection, a vCenter cluster, and a datastore
    .OUTPUTS
      Returns the FlashArray host group connection.
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
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster[]]$cluster,

            [Parameter(Position=1)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=2,mandatory=$true)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
    )
    Begin {
        $faConnections = @()
        if ($null -eq $flasharray)
        {
          $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
        }
        else 
        {
          $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
        }
    }
    Process 
    {
        foreach ($cs in $cluster)
        {
            $pureVol = $datastore | get-pfaVolfromVMFS -flasharray $fa -ErrorAction Stop
            $hostGroup = get-pfaHostGroupfromVcCluster -flasharray $fa -ErrorAction Stop -cluster $cs
            if ($hostGroup.count -gt 1)
            {
              throw "This cluster spans more than one host group, please ensure this is a 1:1 relationship."
            }
            else 
            {
              try {
                $faConnection = New-PfaHostGroupVolumeConnection -Array $fa -VolumeName $pureVol.name -HostGroupName $hostGroup.name -ErrorAction Stop
              }
              catch {
                Write-Error $Global:Error[0]
                continue 
              }
              $cs| Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs -ErrorAction Stop |Out-Null
              $faConnections += $faConnection
              $Global:CurrentFlashArray = $fa
            } 
        }
    }
    End 
    {
        return $faConnections
    }
}
function set-pfaVolVmfsCapacity {
    <#
    .SYNOPSIS
      Increase the size of a FlashArray-based VMFS datastore.
    .DESCRIPTION
      Takes in a datastore, the corresponding FlashArray, and a new size. Both the volume and the VMFS will be grown.
    .INPUTS
      FlashArray connection, a size, and a datastore
    .OUTPUTS
      Returns the datastore.
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
            [Parameter(Position=0,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=2)]
            [int]$sizeInGB,

            [Parameter(Position=3)]
            [int]$sizeInTB
    )
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
    if ($null -eq $flasharray)
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $pureVol = $datastore | get-pfaVolfromVMFS -flasharray $fa -ErrorAction Stop
    if ($volSize -le $pureVol.size)
    {
        throw "The new size cannot be smaller than the existing size. VMFS volumes cannot be shrunk."
    }
    Resize-PfaVolume -Array $fa -VolumeName $pureVol.name -NewSize $volSize -ErrorAction Stop |Out-Null
    $Global:CurrentFlashArray = $fa
    $datastore| Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs -ErrorAction Stop  -WarningAction SilentlyContinue |Out-Null
    $esxiView = Get-View -Id ($Datastore.ExtensionData.Host |Select-Object -last 1 | Select-Object -ExpandProperty Key)
    $datastoreSystem = Get-View -Id $esxiView.ConfigManager.DatastoreSystem
    $expandOptions = $datastoreSystem.QueryVmfsDatastoreExpandOptions($datastore.ExtensionData.MoRef)
    $expandedDS = $datastoreSystem.ExpandVmfsDatastore($datastore.ExtensionData.MoRef,$expandOptions[0].spec)
    $ds = get-datastore -Id $expandedDS
    return $ds
}
function get-pfaVolVmfsSnapshot {
    <#
    .SYNOPSIS
      Retrieve all of the FlashArray snapshots of a given VMFS volume
    .DESCRIPTION
      Takes in a datastore and the corresponding FlashArray and returns any available snapshots.
    .INPUTS
      FlashArray connection and a datastore
    .OUTPUTS
      Returns any snapshots.
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
            [Parameter(Position=0,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
    )
    if ($null -eq $flasharray)
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -ErrorAction Stop
    }
    else 
    {
        $fa = get-pfaConnectionOfDatastore -datastore $datastore -flasharrays $flasharray -ErrorAction Stop
    }
    $pureVol = $datastore | get-pfaVolfromVMFS -flasharray $fa -ErrorAction Stop
    $volSnapshots = Get-PfaVolumeSnapshots -Array $fa -VolumeName $pureVol.name 
    $Global:CurrentFlashArray = $fa
    return $volSnapshots
}
function new-pfaVolVmfsSnapshot {
    <#
    .SYNOPSIS
      Creates a new FlashArray snapshot of a given VMFS volume
    .DESCRIPTION
      Takes in a datastore and the corresponding FlashArray and creates a snapshot.
    .INPUTS
      FlashArray connection and a datastore
    .OUTPUTS
      Returns created snapshot.
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
            [Parameter(Position=0)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore[]]$datastore,

            [Parameter(Position=2)]
            [string]$SnapName,

            [Parameter(Position=3)]
            [string]$suffix
    )
    Begin 
    {
        if (("" -ne $SnapName) -and ("" -ne $suffix))
        {
            throw "Please only enter in the suffix, the snapName parameter is being deprecated."
        }
        elseif ("" -ne $Snapname) {
          Write-Warning -Message "The snapName parameter is being deprecated--please use the suffix parameter instead."  
          $suffix = $SnapName        
        }
        $newSnapshots = @()
    }
    Process 
    {
        foreach ($ds in $datastore)
        {
            if ($null -eq $flasharray)
            {
                $fa = get-pfaConnectionOfDatastore -datastore $ds -ErrorAction Stop
            }
            else 
            {
                $fa = get-pfaConnectionOfDatastore -datastore $ds -flasharrays $flasharray -ErrorAction Stop
            }
            $pureVol = $ds | get-pfaVolfromVMFS -flasharray $fa -ErrorAction Stop
            $Global:CurrentFlashArray = $fa
            if ($suffix -ne "")
            {
              $newSnapshots += New-PfaVolumeSnapshots -Array $fa -Sources $pureVol.name -Suffix $suffix
            }
            else {
              $newSnapshots += New-PfaVolumeSnapshots -Array $fa -Sources $pureVol.name 
            }
            
        }
    }
    End {
      return $newSnapshots
    }
}
function new-pfaVolVmfsFromSnapshot {
    <#
    .SYNOPSIS
      Mounts a copy of a VMFS datastore to a VMware cluster from a FlashArray snapshot.
    .DESCRIPTION
      Takes in a snapshot name, the corresponding FlashArray, and a cluster. The VMFS copy will be resignatured and mounted.
    .INPUTS
      FlashArray connection, a snapshotName, and a cluster.
    .OUTPUTS
      Returns the new datastore.
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  10/24/2018
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
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$True)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray,

            [Parameter(Position=2,mandatory=$true)]
            [string]$snapName
    )
    $volumeName = $snapName.split(".")[0] + "-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
    $newVol =New-PfaVolume -Array $flasharray -Source $snapName -VolumeName $volumeName -ErrorAction Stop
    $hostGroup = $flasharray |get-pfaHostGroupfromVcCluster -cluster $cluster
    New-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $newVol.name -HostGroupName $hostGroup.name |Out-Null
    $esxi = $cluster | Get-VMHost| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1 
    $esxi | Get-VMHostStorage -RescanAllHba -RescanVMFS -ErrorAction stop |Out-Null
    $hostStorage = get-view -ID $esxi.ExtensionData.ConfigManager.StorageSystem
    $resigVolumes= $hostStorage.QueryUnresolvedVmfsVolume()
    $newNAA =  "naa.624a9370" + $newVol.serial.toLower()
    $deleteVol = $false
    foreach ($resigVolume in $resigVolumes)
    {
        if ($deleteVol -eq $true)
        {
            break
        }
        foreach ($resigExtent in $resigVolume.Extent)
        {
            if ($resigExtent.Device.DiskName -eq $newNAA)
            {
                if ($resigVolume.ResolveStatus.Resolvable -eq $false)
                {
                    if ($resigVolume.ResolveStatus.MultipleCopies -eq $true)
                    {
                        write-host "The volume cannot be resignatured as more than one unresignatured copy is present. Deleting and ending." -BackgroundColor Red
                        write-host "The following volume(s) are presented and need to be removed/resignatured first:"
                        $resigVolume.Extent.Device.DiskName |where-object {$_ -ne $newNAA}
                    }
                    $deleteVol = $true
                    break
                }
                else {
                    $volToResignature = $resigVolume
                    break
                }
            }
        }
    }
    if (($null -eq $volToResignature) -and ($deleteVol -eq $false))
    {
        write-host "No unresolved volume found on the created volume. Deleting and ending." -BackgroundColor Red
        $deleteVol = $true
    }
    if ($deleteVol -eq $true)
    {
        Remove-PfaHostGroupVolumeConnection -Array $flasharray -VolumeName $newVol.name -HostGroupName $hostGroup.name |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $flasharray -Name $newVol.name |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $flasharray -Name $newVol.name -Eradicate |Out-Null
        return $null
    }
    $esxcli=get-esxcli -VMHost $esxi -v2 -ErrorAction stop
    $resigOp = $esxcli.storage.vmfs.snapshot.resignature.createargs()
    $resigOp.volumelabel = $volToResignature.VmfsLabel  
    $esxcli.storage.vmfs.snapshot.resignature.invoke($resigOp) |out-null
    Start-sleep -s 5
    $esxi |  Get-VMHostStorage -RescanVMFS -ErrorAction stop |Out-Null
    $datastores = $esxi| Get-Datastore -ErrorAction stop 
    foreach ($ds in $datastores)
    {
        $naa = $ds.ExtensionData.Info.Vmfs.Extent.DiskName
        if ($naa -eq $newNAA)
        {
            $resigds = $ds | Set-Datastore -Name $newVol.name -ErrorAction stop
            return $resigds
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
New-Alias -Name get-faVolfromVMFS -Value get-pfaVolfromVMFS
New-Alias -Name new-faVolVmfs -Value new-pfaVolVmfs
New-Alias -Name add-faVolVmfsToCluster -Value add-pfaVolVmfsToCluster
New-Alias -Name set-faVolVmfsCapacity -Value set-pfaVolVmfsCapacity
New-Alias -Name get-faVolVmfsSnapshots -Value get-pfaVolVmfsSnapshot
New-Alias -Name new-faVolVmfsSnapshot -Value new-pfaVolVmfsSnapshot
New-Alias -Name new-faVolVmfsFromSnapshot -Value new-pfaVolVmfsFromSnapshot
