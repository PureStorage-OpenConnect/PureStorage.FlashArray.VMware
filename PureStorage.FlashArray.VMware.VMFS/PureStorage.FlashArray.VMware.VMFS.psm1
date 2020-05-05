$ErrorActionPreference = 'Stop'
function Get-PfaVMFSVol {
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
      Version:        3.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/17/2019
      Purpose/Change: Added parameter sets, validation 
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore myVMFS
      PS C:\ Get-PfaVMFSVol -datastore $ds -flasharray $fa
      
      Returns the volume that hosts the VMFS datastore.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ New-PfaConnection -endpoint flasharray-x20-1 -credentials $faCreds -nondefaultArray
      PS C:\ $ds = get-datastore myVMFS
      PS C:\ Get-PfaVMFSVol -datastore $ds
      
      Returns the volume that hosts the VMFS datastore by finding it on one of the connected FlashArrays.

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
            [ValidateScript({
              if ($_.Type -ne 'VMFS')
              {
                  throw "The entered datastore is not a VMFS datastore. It is type $($_.Type). Please only enter a VMFS datastore"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray
    )

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
function New-PfaVmfs {
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
      Version:        3.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/23/2019
      Purpose/Change: Added parameter sets, validation and creation from snapshot
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ New-PfaVmfs -cluster (get-cluster MountainView) -volName codytest0001 -sizeInTB 12
      
      Creates a 12 TB VMFS for a cluster named MountainView on the default FlashArray connection
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ New-PfaVmfs -cluster (get-cluster MountainView) -volName codytest0002 -sizeInGB 16384 -flasharray $fa
      
      Creates a 16384 GB VMFS for a cluster named MountainView on the specified FlashArray connection

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

            [Parameter(ParameterSetName='GB',Position=2,mandatory=$true)]
            [Parameter(ParameterSetName='TB',Position=2,mandatory=$true)]
            [ValidateScript({
              if (($_ -match "^[A-Za-z][a-zA-Z0-9\-_]+[a-zA-Z0-9]$") -and ($_.length -lt 64))
              {
                $true
              }
              else {
                throw "The name must be no more than 63 characters, start with a letter, and consist of only numbers, letters, and dashes."
              }
            })]
            [string]$volName,

            [ValidateRange(1,63488)]
            [Parameter(ParameterSetName='GB',Position=3)]
            [int]$sizeInGB,

            [ValidateRange(1,62)]
            [Parameter(ParameterSetName='TB',Position=4)]
            [int]$sizeInTB,

            [Parameter(ParameterSetName='Snapshot',Position=5,mandatory=$true)]
            [string]$snapName
    )
    Begin {
        if ($sizeInGB -ne 0) {
            $volSize = $sizeInGB * 1024 *1024 *1024   
        }
        elseif ($sizeInTB -ne 0) {
            $volSize = $sizeInTB * 1024 *1024 *1024 * 1024
        }
        $allFAs = @()
        $newNAAs = @()
        $volNames = @()
        $hostGroupNames = @()
        $oneVolume = 0
        $newDatastores = @()
    }
    Process 
    {
        if ($null -eq $flasharray)
        {
          $flasharray = checkDefaultFlashArray
        }
        if ($null -eq $volSize)
        {
          foreach ($fa in $flasharray)
          {
            $snapshot = Get-PfaVolumeSnapshot -Array $fa -SnapshotName $snapName
            if ($null -ne $snapshot)
            {
              break
            }
          } 
          $newDatastores = New-PfaVmfsFromSnapshot -cluster $cluster -flasharray $fa -snapName $snapshot.name
          $Global:CurrentFlashArray = $fa
        }
        else 
        {
          foreach ($fa in $flasharray)
          {
            try {
              $hostGroup = $cluster | get-pfaHostGroupfromVcCluster -flasharray $fa
            }  
            catch 
            {
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
    }
    End 
    {
      if ($newDatastores.count -lt 1)
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
      }
      return $newDatastores
    }
}
function Add-PfaVmfsToCluster {
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
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ Add-PfaVmfsToCluster -cluster (get-cluster Cupertino) -datastore $ds
      
      Adds an existing datastore to another VMware cluster. The FlashArray connection is discovered in the default connection.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ Add-PfaVmfsToCluster -cluster (get-cluster Cupertino) -datastore $ds -flasharray $fa
      
      Adds an existing datastore to another VMware cluster.
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
            [ValidateScript({
              if ($_.Type -ne 'VMFS')
              {
                  throw "The entered datastore is not a VMFS datastore. It is type $($_.Type). Please only enter a VMFS datastore"
              }
              else {
                $true
              }
            })]
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
function Set-PfaVmfsCapacity {
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
      Version:        2.1
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  01/04/2019
      Purpose/Change: Updated to remove code that causes deprecation warning from VMware
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds | Set-PfaVmfsCapacity -sizeInTB 16
      
      Expands the size of the VMFS datastore to 16 TB. The FlashArray connection is discovered in the default connection.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds | Set-PfaVmfsCapacity -sizeInTB 16 -flasharray $fa
      
      Expands the size of the VMFS datastore to 16 TB. 
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
            [ValidateScript({
              if ($_.Type -ne 'VMFS')
              {
                  throw "The entered datastore is not a VMFS datastore. It is type $($_.Type). Please only enter a VMFS datastore"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

            [ValidateRange(1,63488)]
            [Parameter(ParameterSetName='GB',Position=2,mandatory=$true)]
            [int]$sizeInGB,

            [ValidateRange(1,62)]
            [Parameter(ParameterSetName='TB',Position=3,mandatory=$true)]
            [int]$sizeInTB
    )
   if ($sizeInGB -ne 0) {
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
    foreach ($dsHost in $datastore.ExtensionData.Host.Key)
    {
      #had to change this as get-vmhost -datastore spits out a deprecation error.
      get-vmhost -id "HostSystem-$($dsHost.value)" | Get-VMHostStorage -RescanAllHba -RescanVmfs -ErrorAction Stop  -WarningAction SilentlyContinue |Out-Null
    }
    $esxiView = Get-View -Id ($Datastore.ExtensionData.Host |Select-Object -last 1 | Select-Object -ExpandProperty Key)
    $datastoreSystem = Get-View -Id $esxiView.ConfigManager.DatastoreSystem
    $expandOptions = $datastoreSystem.QueryVmfsDatastoreExpandOptions($datastore.ExtensionData.MoRef)
    $expandedDS = $datastoreSystem.ExpandVmfsDatastore($datastore.ExtensionData.MoRef,$expandOptions[0].spec)
    $ds = get-datastore -Id $expandedDS
    return $ds 
}
function Get-PfaVmfsSnapshot {
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
      Version:        3.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/23/2019
      Purpose/Change: Updated for new connection mgmt
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds |Get-PfaVmfsSnapshot
      
      Returns all snapshots on the array for the VMFS. The FlashArray connection is discovered in the default connection.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds |Get-PfaVmfsSnapshot 
      
      Returns all snapshots on the array for the VMFS. The FlashArray connection is discovered in the default connection.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds |Get-PfaVmfsSnapshot -flasharray $fa
      
      Returns all snapshots on the array for the VMFS. The FlashArray connection is specified.

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
            [ValidateScript({
              if ($_.Type -ne 'VMFS')
              {
                  throw "The entered datastore is not a VMFS datastore. It is type $($_.Type). Please only enter a VMFS datastore"
              }
              else {
                $true
              }
            })]
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
function New-PfaVmfsSnapshot {
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
      Version:        3.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  12/23/2019
      Purpose/Change: Added examples and parameter sets/validation.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds |New-PfaVmfsSnapshot
      
      Create a snapshot of the VMFS volume with default snapshot name. The FlashArray connection is discovered in the default connection.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds |New-PfaVmfsSnapshot -suffix codysnap1
      
      Create a snapshot of the VMFS volume with the specified snapshot name. The FlashArray connection is discovered in the default connection.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $ds = get-datastore codytest0001
      PS C:\ $ds |New-PfaVmfsSnapshot -suffix codysnap1 -flasharray $fa
      
      Create a snapshot of the VMFS volume with the specified snapshot name. The FlashArray connection is specified.

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

            [Parameter(ParameterSetName='datastore',Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [Parameter(ParameterSetName='snapname',Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [Parameter(ParameterSetName='suffix',Position=1,mandatory=$true,ValueFromPipeline=$True)]
            [ValidateScript({
              if ($_.Type -ne 'VMFS')
              {
                  throw "The entered datastore is not a VMFS datastore. It is type $($_.Type). Please only enter a VMFS datastore"
              }
              else {
                $true
              }
            })]
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore[]]$datastore,

            [ValidateScript({
              if (($_ -match "^[A-Za-z][a-zA-Z0-9\-_]+[a-zA-Z0-9]$") -and ($_.length -lt 64))
              {
                $true
              }
              else {
                throw "Volume name must be between 1 and 63 characters (alphanumeric, _ and -) in length and begin and end with a letter or number. The name must include at least one letter, _, or -"
              }
            })]
            [Parameter(ParameterSetName='snapname',Position=2,mandatory=$true)]
            [string]$SnapName,

            [ValidateScript({
              if (($_ -match "^[A-Za-z][a-zA-Z0-9\-_]+[a-zA-Z0-9]$") -and ($_.length -lt 64))
              {
                $true
              }
              else {
                throw "Volume name must be between 1 and 63 characters (alphanumeric, _ and -) in length and begin and end with a letter or number. The name must include at least one letter, _, or -"
              }
            })]
            [Parameter(ParameterSetName='suffix',Position=3,mandatory=$true)]
            [string]$suffix
    )
    Begin 
    {
      if ("" -ne $Snapname) 
      {
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

##Private functions
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
function New-PfaVmfsFromSnapshot {
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
  $volumeName = $snapName.split(".")
  if ($volumeName.count -eq 3)
  {
    $volumeName = $volumeName[2]
  } elseif ($volumeName.count -eq 2) 
  {
    $volumeName = $volumeName[0]
  }
  $volumeName = $volumeName.Split("/")
  if ($volumeName.count -eq 2) {
    $volumeName = $volumeName[1]
  }
  $volumeName = "$($volumeName)-snap-" + (Get-Random -Minimum 1000 -Maximum 9999)
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
New-Alias -Name get-faVolfromVMFS -Value Get-PfaVMFSVol
New-Alias -Name new-faVolVmfs -Value New-PfaVmfs
New-Alias -Name add-faVolVmfsToCluster -Value Add-PfaVmfsToCluster
New-Alias -Name set-faVolVmfsCapacity -Value Set-PfaVmfsCapacity
New-Alias -Name get-faVolVmfsSnapshots -Value get-pfaVolVmfsSnapshot
New-Alias -Name new-faVolVmfsSnapshot -Value new-pfaVolVmfsSnapshot
New-Alias -Name new-faVolVmfsFromSnapshot -Value New-PfaVmfs
New-Alias -Name get-pfaVolfromVMFS -Value Get-PfaVMFSVol 
New-Alias -Name new-pfaVolVmfs -Value New-PfaVmfs
New-Alias -Name add-pfaVolVmfsToCluster -Value Add-PfaVmfsToCluster
New-Alias -Name set-pfaVolVmfsCapacity -Value Set-PfaVmfsCapacity
New-Alias -Name get-pfaVolVmfsSnapshot -Value Get-PfaVmfsSnapshot
New-Alias -Name New-PfaVolVmfsSnapshot -Value New-PfaVmfsSnapshot
New-Alias -Name New-PfaVolVmfsFromSnapshot -Value New-PfaVmfs