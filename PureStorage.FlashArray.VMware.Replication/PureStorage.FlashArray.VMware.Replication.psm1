function Start-PfaActiveDRFailover {
    <#
    .SYNOPSIS
      Fails over VMFS or RDM-based virtual machines on ActiveDR
    .DESCRIPTION
      Fails over VMFS or RDM-based virtual machines on ActiveDR
    .INPUTS
      TBD
    .OUTPUTS
        TBD
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  06/23/2020
      Purpose/Change: Function creation
    .EXAMPLE
      PS C:\ New-PfavVolStoragePolicy -policyName
  
      Creates a new vVol policy with the specified name and default description. The only capability is ensuring it is a FlashArray policy.
    
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
          [Parameter(Position=0,mandatory=$true)]
          [string]$sourcePod,

          [Parameter(Position=0)]
          [string]$targetPod,

          [Parameter(Position=1,mandatory=$true)]
          [PurePowerShell.PureArray]$sourceFlasharray,

          [Parameter(Position=1,mandatory=$true)]
          [PurePowerShell.PureArray]$targetFlasharray,

          [Parameter(Position=12)]
          [VMware.VimAutomation.ViCore.Types.V1.VIServer]$sourcevCenter,

          [Parameter(Position=12)]
          [VMware.VimAutomation.ViCore.Types.V1.VIServer]$targetvCenter,

          [Parameter(Position=0)]
          [switch]$starttestRecovery,

          [Parameter(Position=0)]
          [switch]$stoptestRecovery,

          [Parameter(Position=0)]
          [switch]$plannedMigration,

          [Parameter(Position=0)]
          [switch]$generateRecoveryReport,

          [Parameter(Position=0)]
          [switch]$exportRecoveryPlan,
          
          [Parameter(Position=0,ParameterSetName='Single')]
          [VMware.VimAutomation.ViCore.Types.V1.Host.Networking.VirtualPortGroup]$targetPortGroup,
          [Parameter(Position=0,ParameterSetName='Single',mandatory=$true)]
          [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$targetCluster,
          [Parameter(Position=0,ParameterSetName='Single')]
          [VMware.VimAutomation.ViCore.Types.V1.Inventory.ResourcePool]$targetPool,
          [Parameter(Position=0,ParameterSetName='Single')]
          [VMware.VimAutomation.ViCore.Types.V1.Inventory.Folder]$targetVMFolder,
          [Parameter(Position=0,ParameterSetName='Single')]
          [VMware.VimAutomation.ViCore.Types.V1.Inventory.Folder]$targetDatastoreFolder
    )
    #connect to REST 2.x on source FA
    $sourceFaToken = @{"api-token" = $sourceFlasharray.ApiToken}
    $sourceAuthResponse = Invoke-webrequest -Method Post -Uri "https://$($sourceFlasharray.Endpoint)/api/2.2/login" -Headers $sourceFaToken -SkipCertificateCheck 
    $sourceAuthHeader = @{"x-auth-token" = ($sourceAuthResponse.Headers."x-auth-token")[0]}
    #find source pod
    $uri = ("https://$($sourceFlasharray.Endpoint)/api/2.2/pods?filter=" + ([System.Web.HttpUtility]::Urlencode("name")) + "=`'$($sourcePod)`'")
    $sourcePodResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $sourceAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
    if ($null -eq $sourcePodResponse)
    {
        throw "Pod named $($sourcePod) was not found on $($sourceFlashArray.EndPoint)"
    }
    #get source pod volumes
    $uri = ("https://$($sourceFlasharray.Endpoint)/api/2.2/volumes?filter=" + ([System.Web.HttpUtility]::Urlencode("pod.name")) + "=`'$($sourcePod)`'")
    $sourceVolumes = ((Invoke-webrequest -Method GET -Uri $uri -Headers $sourceAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
    Write-Debug ($sourceVolumes |format-list * |Out-String)
    #connect to REST 2.x on target FA
    $targetFaToken = @{"api-token" = $targetFlasharray.ApiToken}
    $targetAuthResponse = Invoke-webrequest -Method Post -Uri "https://$($targetFlasharray.Endpoint)/api/2.2/login" -Headers $targetFaToken -SkipCertificateCheck 
    $targetAuthHeader = @{"x-auth-token" = ($targetAuthResponse.Headers."x-auth-token")[0]}
    #find target pod
    $uri = ("https://$($targetFlasharray.Endpoint)/api/2.2/pods?filter=" + ([System.Web.HttpUtility]::Urlencode("name")) + "=`'$($targetPod)`'")
    $targetPodResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $targetAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
    if ($null -eq $targetPodResponse)
    {
        throw "Pod named $($targetPod) was not found on $($targetFlashArray.EndPoint)"
    }
    #get target pod volumes
    $uri = ("https://$($targetFlasharray.Endpoint)/api/2.2/volumes?filter=" + ([System.Web.HttpUtility]::Urlencode("pod.name")) + "=`'$($targetPod)`'")
    $targetVolumes = ((Invoke-webrequest -Method GET -Uri $uri -Headers $targetAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
    Write-Debug ($targetVolumes |format-list * |Out-String)

    $allDatastores = get-datastore | Where-Object {$_.Type -eq 'VMFS'}
    $recoveryVolumes = @()
    $volCount = 1
    foreach ($sourceVolume in $sourceVolumes) 
    {
        Write-Progress -Activity "Identifying volume usage from the ActiveDR pod $($sourcePod) in the VMware environment" -Status "Iterating through $($sourceVolumes.count) volumes. Examining volume $($volCount).." -PercentComplete (($volCount /$sourceVolumes.count)*100) -CurrentOperation $sourceVolume.Name
        $volCount++
        #find if the volume is a datastore
        $foundVMFS = $null
        $foundVMFS = $allDatastores | Where-Object {(($_.ExtensionData.Info.Vmfs.Extent[0].DiskName.ToUpper()).substring(12)) -eq $sourceVolume.serial}
        if ($null -ne $foundVMFS)
        {
            $faVolumeProperties = [PureStorageVMwareVolumeProperties]::new()
            $faVolumeProperties.vmfs = $true
            $faVolumeProperties.sourceVol = $sourceVolume
            $faVolumeProperties.targetVol = ($targetVolumes | where-object {$_.name -eq ($sourceVolume.name -replace $sourcePod, $targetPod)})
            $faVolumeProperties.sourceClusterNames = (Get-VmHost -Id ($foundVMFS.ExtensionData.Host.Key) | Get-Cluster).Name
            $recoveryVolumes += $faVolumeProperties
            continue
        }
        $rdmDisks = get-vm|Get-HardDisk -DiskType "RawPhysical","RawVirtual" | where-object {$_.ExtensionData.Backing.LunUuid.substring(10).substring(0,32) -eq ("624a9370" + $sourceVolume.serial.ToLower())}
        if ($null -ne $rdmDisks) 
        {
            #check if it is an RDM 
            $foundRDM = $null
            $faVolumeProperties = $null
            $faVolumeProperties = [PureStorageVMwareVolumeProperties]::new()
            $faVolumeProperties.rdm = $true
            $faVolumeProperties.sourceVol = $sourceVolume
            $faVolumeProperties.targetVol = ($targetVolumes | where-object {$_.name -eq ($sourceVolume.name -replace $sourcePod, $targetPod)})
            $clusters = Get-Cluster
            foreach ($cluster in $clusters) 
            {
                $lunPresent = $cluster |get-vmhost |get-scsilun -CanonicalName ("naa.624a9370" + $sourceVolume.serial.ToLower()) -LunType disk
                if ($null -ne $lunPresent)
                {
                    $faVolumeProperties.sourceClusterNames += $cluster.Name
                }
            }
            foreach ($foundRDM in $rdmDisks) 
            {
                $rdmMapping = [PureStorageVMwareRDMMapping]::new()
                $rdmMapping.sourceRDMvolKey = $foundRDM.ExtensionData.Key
                $rdmMapping.sourceRDMvolControllerKey = $foundRDM.ExtensionData.ControllerKey 
                $rdmMapping.sourceRDMvolUnitNumber = $foundRDM.ExtensionData.UnitNumber  
                $rdmMapping.rdmType = $foundRDM.DiskType
                $rdmMapping.sourceRDMsharing = $foundRDM.ExtensionData.Backing.Sharing
                $rdmMapping.vmName = $foundRDM.parent.name
                $rdmMapping.vmPersistentId = $foundRDM.parent.PersistentId  
                $faVolumeProperties.rdmMapping += $rdmMapping
            }              
            $recoveryVolumes += $faVolumeProperties
            continue
    }
        else 
        {
            $foundunUsedDisk = Get-vmhost |get-scsilun -CanonicalName ("naa.624a9370" + $sourceVolume.serial.ToLower()) -LunType disk -ErrorAction SilentlyContinue |Select-Object -Unique
            if ($null -ne $foundunUsedDisk)
            {
                $faVolumeProperties = [PureStorageVMwareVolumeProperties]::new()
                $faVolumeProperties.unknown = $true
                $faVolumeProperties.sourceVol = $sourceVolume
                $faVolumeProperties.targetVol = ($targetVolumes | where-object {$_.name -eq ($sourceVolume.name -replace $sourcePod, $targetPod)})
                $clusters = Get-Cluster
                foreach ($cluster in $clusters) 
                {
                    $lunPresent = $cluster |get-vmhost |get-scsilun -CanonicalName ("naa.624a9370" + $sourceVolume.serial.ToLower()) -LunType disk
                    if ($null -ne $lunPresent)
                    {
                        $faVolumeProperties.sourceClusterNames += $cluster.Name
                    }
                }
                $recoveryVolumes += $faVolumeProperties
            }
            else {
                $uri = ("https://$($sourceFlasharray.Endpoint)/api/2.2/connections?volume_names=$($sourceVolume.name)")
                $volConnectionsResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $sourceAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
                if ($volConnectionsResponse.count -gt 0)
                {
                    throw "A volume named $($sourceVolume.name) has been found in the pod but is not present in the VMware environment but does have connections to other hosts/host groups. Failing this procedure."
                }
            }
        }
    }
    Write-Debug ($recoveryVolumes |format-list * |Out-String)
    $allDatastores = get-datastore | Where-Object {$_.Type -eq 'VMFS'}
    $foundSourceDatastores = @()
    foreach ($recoveryVolume in $recoveryVolumes) 
    {
        if ($recoveryVolume.vmfs -eq $True)
        {
            $foundSourceDatastores += $allDatastores | Where-Object {(($_.ExtensionData.Info.Vmfs.Extent[0].DiskName.ToUpper()).substring(12)) -eq $recoveryVolume.sourceVol.serial}
        }
    }
    $recoveryVMs = $foundSourceDatastores |get-vm
    $foundDatastores = $recoveryVMs |get-datastore
    if ($foundSourceDatastores.count -lt $foundDatastores.count)
    {
        Write-Host ""
        Write-Error -Message "There are virtual machines on the ActiveDR datastores that are using external datastores which would prevent their full failover. Ending process."
        $VMUnknownDSReport = @()
        foreach ($recoveryVM in $recoveryVMs) {
            $VMInfo =  [pscustomobject]@{
            Name = $recoveryVM.Name
            ("Unknown Datastores") = ((Compare-Object ($recoveryVM |get-datastore).Name $foundSourceDatastores.name) |where-object {$_.SideIndicator -eq "<="}).InputObject
            }
            if ($null -ne $VMInfo."Unknown Datastores")
            {
                $VMUnknownDSReport += $VMInfo
            }
        }
        return $VMUnknownDSReport
    }
    if ($exportRecoveryPlan -eq $true)
    {
        return ($recoveryVolumes | ConvertTo-Json -Depth 4)
    }
    if ($generateRecoveryReport -eq $true)
    {
        new-InternalPfaRecoveryReport -recoveryVolumes $recoveryVolumes
        Start-Process .\ActiveDR-Recovery-Plan.html
        $global:reportHasBeenRun = $true
        return $recoveryVolumes
    }
    if ($global:reportHasBeenRun -eq $true)
    {
        if ($plannedMigration -eq $true)
        {
            $clusters = get-cluster ($recoveryVolumes.sourceClusterNames |Select-Object -Unique)
            foreach ($recoveryVolume in ($recoveryVolumes | Where-Object {$_.vmfs -eq $True})) 
            {
                $vmfsToUnmount = $allDatastores | Where-Object {(($_.ExtensionData.Info.Vmfs.Extent[0].DiskName.ToUpper()).substring(12)) -eq $recoveryVolume.sourceVol.serial}
                if ($null -ne $vmfsToUnmount)
                {
                    Stop-InternalPfaVM -datastore $vmfsToUnmount
                    $vms = $vmfsToUnmount |get-vm
                    if ($null -ne $vms)
                    {
                        $vmfsToUnmount |get-vm | remove-vm -RunAsync -confirm:$false |Out-Null
                    } 
                }
            }
            foreach ($recoveryVolume in ($recoveryVolumes | Where-Object {$_.vmfs -eq $True})) 
            {
                $vmfsToUnmount = $allDatastores | Where-Object {(($_.ExtensionData.Info.Vmfs.Extent[0].DiskName.ToUpper()).substring(12)) -eq $recoveryVolume.sourceVol.serial}
                if ($null -ne $vmfsToUnmount)
                {
                    Disable-InternalPfaVMFS -datastore $vmfsToUnmount   
                }
            }
            foreach ($recoveryVolume in ($recoveryVolumes | Where-Object {($_.rdm -eq $True) -or ($_.unknown -eq $True)}))  
            {
                $vmhostsWithVolume = $clusters |get-vmhost | where-object {$null -ne (get-scsilun -VmHost $_ -CanonicalName ("naa.624a9370" + $recoveryVolume.sourceVol.serial.ToLower()) -LunType disk)}
                foreach ($vmhostWithVolume in $vmhostsWithVolume) 
                {
                    Disable-InternalPfaLun -vmhost $vmhostWithVolume -CanonicalName ("naa.624a9370" + $recoveryVolume.sourceVol.serial.ToLower())
                }
                $clusters |get-vmhost | Get-VMHostStorage -RescanVmfs |Out-Null
            } 
            #find source pod state
            $uri = ("https://$($sourceFlasharray.Endpoint)/api/2.2/pods?filter=" + ([System.Web.HttpUtility]::Urlencode("name")) + "=`'$($sourcePod)`'")
            $sourcePodResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $sourceAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
            if ($sourcePodResponse.promotion_status -eq "Promoted")
            {
                $uri = ("https://$($sourceFlasharray.Endpoint)/api/2.2/pods/performance?names=$($sourcePod)")
                $sourcePodPerformanceResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $sourceAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
                if (($sourcePodPerformanceResponse.read_bytes_per_sec -ne 0) -or ($sourcePodPerformanceResponse.write_bytes_per_sec -ne 0))
                {
                    throw "Cannot demote. The pod still has active I/O--please ensure that all workloads have stopped to the pod and retry."
                }
                else {
                    $uri = ("https://$($sourceFlasharray.Endpoint)/api/2.2/pods/?quiesce=true&names=$($sourcePod)")
                    $demotePod = [pscustomobject]@{
                        requested_promotion_state = "demoted"
                        } |ConvertTo-Json
                    $sourcePodDemoteResponse = ((Invoke-webrequest -Method PATCH -Uri $uri -body $demotePod -Headers $sourceAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
                }
            }
        }
        if (($starttestRecovery -eq $true) -or ($plannedMigration -eq $true))
        {
            #find target pod state
            $targetAuthResponse = Invoke-webrequest -Method Post -Uri "https://$($targetFlasharray.Endpoint)/api/2.2/login" -Headers $targetFaToken -SkipCertificateCheck 
            $targetAuthHeader = @{"x-auth-token" = ($targetAuthResponse.Headers."x-auth-token")[0]}
            $uri = ("https://$($targetFlasharray.Endpoint)/api/2.2/pods?filter=" + ([System.Web.HttpUtility]::Urlencode("name")) + "=`'$($targetPod)`'")
            $targetPodResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $targetAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
            if ($targetPodResponse.promotion_status -eq "Demoted")
            {
                $AuthAction = @{
                    requested_promotion_state = "promoted"
                }|Convertto-Json
                Invoke-webrequest -Method Patch -Uri "https://$($targetFlasharray.Endpoint)/api/2.2/pods?names=$($targetPod)" -Headers $targetAuthHeader -Body $AuthAction -SkipCertificateCheck

            }
            $uri = ("https://$($targetFlasharray.Endpoint)/api/2.2/pods?filter=" + ([System.Web.HttpUtility]::Urlencode("name")) + "=`'$($targetPod)`'")
            $targetPodResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $targetAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
            while ($targetPodResponse.promotion_status -ne "Promoted")
            {
                Start-Sleep -Seconds 5
                $uri = ("https://$($targetFlasharray.Endpoint)/api/2.2/pods?filter=" + ([System.Web.HttpUtility]::Urlencode("name")) + "=`'$($targetPod)`'")
                $targetPodResponse = ((Invoke-webrequest -Method GET -Uri $uri -Headers $targetAuthHeader -SkipCertificateCheck).content |ConvertFrom-Json).items
            }
            if ($null -ne $targetCluster)
            {
                $targetHostGroup = $targetCluster |Get-PfaHostGroupfromVcCluster -flasharray $targetFlasharray
            }
            foreach ($recoveryVolume in ($recoveryVolumes | Where-Object {$_.external -ne $True})) 
            {
                if ($null -eq $targetCluster)
                {
                    foreach ($sourceClusterName in $recoveryVolume.sourceClusterNames) 
                    {
                        $targetClusterPair = $clusterMapping | Where-Object {$_.sourceCluster.name -eq $sourceClusterName}
                    }
                    $targetHostGroup = $targetCluster |Get-PfaHostGroupfromVcCluster -flasharray $targetFlasharray
                }
                if ($PSEdition -ne 'Core')
                {
                    try {
                        Invoke-webrequest -Method Post -Uri "https://$($flasharray.Endpoint)/api/2.2/connections?host_group_names=$($targetHostGroup)&volume_names=$($recoveryVolume.targetVol.name)" -Headers $targetAuthHeader |Out-Null
                    }
                    catch {
                        if ((($_ |ConvertFrom-Json).Errors.message) -ne "Connection already exists.")
                        {
                            throw ($recoveryVolume.targetVol.name + " " + ($_[0] |ConvertFrom-Json).Errors.message)
                        }
                    }
                }
                else {
                    try {
                        Invoke-webrequest -Method Post -Uri "https://$($flasharray.Endpoint)/api/2.2/connections?host_group_names=$($targetHostGroup)&volume_names=$($recoveryVolume.targetVol.name)" -Headers $targetAuthHeader -SkipCertificateCheck |Out-Null
                    }
                    catch {
                        if ((($_ |ConvertFrom-Json).Errors.message) -ne "Connection already exists.")
                        {
                            throw ($recoveryVolume.targetVol.name + " " + ($_[0] |ConvertFrom-Json).Errors.message)
                        }
                    }
                }
            }
            if ($null -ne $targetCluster)
            {
                $targetCluster| Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs|Out-Null
            }
            foreach ($recoveryVolume in ($recoveryVolumes | Where-Object {$_.vmfs -eq $True})) 
            {
                # Searches for .VMX Files in datastore variable
                $ds = Get-Datastore -Name $Datastore | ForEach-Object {Get-View $_.Id}
                $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
                $SearchSpec.matchpattern = "*.vmx";
                $dsBrowser = Get-View $ds.browser
                $DatastorePath = "[" + $ds.Summary.Name + "]";
                
                # Find all .VMX file paths in Datastore variable and filters out .snapshot
                $SearchResult = $dsBrowser.SearchDatastoreSubFolders($DatastorePath, $SearchSpec) | ForEach-Object{$_.FolderPath + ($_.File | Select-Object Path).Path}
                
                # Register all .VMX files with vCenter
                foreach($VMXFile in $SearchResult) 
                {
                    New-VM -VMFilePath $VMXFile -VMHost $ESXHost -Location $VMFolder -RunAsync
                }  
            }
        }   
    }
}

function Export-PfaActiveDRResourceMappings {
    <#
    .SYNOPSIS
      Fails over VMFS or RDM-based virtual machines on ActiveDR
    .DESCRIPTION
      Fails over VMFS or RDM-based virtual machines on ActiveDR
    .INPUTS
      TBD
    .OUTPUTS
        TBD
    .NOTES
      Version:        1.0
      Author:         Cody Hosterman https://codyhosterman.com
      Creation Date:  06/23/2020
      Purpose/Change: Function creation
    .EXAMPLE
      PS C:\ New-PfavVolStoragePolicy -policyName
  
      Creates a new vVol policy with the specified name and default description. The only capability is ensuring it is a FlashArray policy.
    
      *******Disclaimer:******************************************************
      This scripts are offered "as is" with no warranty.  While this 
      scripts is tested and working in my environment, it is recommended that you test 
      this script in a test lab before using in a production environment. Everyone can 
      use the scripts/commands provided here without any written permission but I
      will not be liable for any damage or loss to the system.
      ************************************************************************
      #>
  
    [CmdletBinding(DefaultParameterSetName='Source')]
    Param(
          [Parameter(Position=0,mandatory=$true)]
          [string]$fileLocation,

          [Parameter(Position=1,mandatory=$true,ParameterSetName='Source')]
          [switch]$source,

          [Parameter(Position=2,mandatory=$true,ParameterSetName='Target')]
          [switch]$target
    )
    if (($source -eq $false) -and ($target -eq $false))
    {
        throw "You must specify either source as true or target, both cannot be false. Either add -source or -target."
    }
    $clusters = Get-Cluster
    $portgroups = Get-VirtualPortGroup |Select-Object -Unique
    $vmFolders = get-folder -Type VM
    $datastoreFolders = get-folder -Type Datastore
    $resourcePools = Get-ResourcePool

    #build cluster mappings
    $clusterObjects = New-Object -TypeName psobject
    $clusterArray = @()
    foreach ($cluster in $clusters) {
        if ($source -eq $true)
        {
            $sourceClusterName = $cluster.Name
            $targetClusterName = "NULL--ENTER TARGET CLUSTER NAME"
        }
        else 
        {
            $sourceClusterName = "NULL--ENTER SOURCE CLUSTER NAME"
            $targetClusterName = $cluster.Name
        }
        $clusterObject = New-Object -TypeName psobject
        $clusterObject | Add-Member -MemberType NoteProperty -Name "Source" -Value $sourceClusterName
        $clusterObject | Add-Member -MemberType NoteProperty -Name "Target" -Value $targetClusterName
        $clusterArray += $clusterObject
    }
    $clusterObjects | Add-Member -MemberType NoteProperty -Name "ClusterMappings" -Value $clusterArray

    #build network mappings
    $networkObjects = New-Object -TypeName psobject
    $networkArray = @()
    foreach ($portGroup in $portgroups) {
        if ($source -eq $true)
        {
            $sourceNetworkName = $portGroup.Name
            $targetNetworkName = "NULL--ENTER TARGET NETWORK PORTGROUP NAME"
        }
        else 
        {
            $sourceNetworkName = "NULL--ENTER SOURCE NETWORK PORTGROUP NAME"
            $targetNetworkName = $portGroup.Name
        }
        $portGroupObject = New-Object -TypeName psobject
        $portGroupObject | Add-Member -MemberType NoteProperty -Name "Source" -Value $sourceNetworkName
        $portGroupObject | Add-Member -MemberType NoteProperty -Name "Target" -Value $targetNetworkName
        $networkArray += $portGroupObject
    }
    $networkObjects | Add-Member -MemberType NoteProperty -Name "Network Mappings" -Value $networkArray

    #build VM folder mappings
    $vmFolderObjects = New-Object -TypeName psobject
    $vmFolderArray = @()
    foreach ($vmFolder in $vmFolders) {
        if ($source -eq $true)
        {
            $sourcevmFolderName = $vmFolder.Name
            $targetvmFolderName = "NULL--ENTER TARGET VM FOLDER NAME"
        }
        else 
        {
            $sourcevmFolderName = "NULL--ENTER SOURCE VM FOLDER NAME"
            $targetvmFolderName = $vmFolder.Name
        }
        $vmFolderObject = New-Object -TypeName psobject
        $vmFolderObject | Add-Member -MemberType NoteProperty -Name "Source" -Value $sourcevmFolderName
        $vmFolderObject | Add-Member -MemberType NoteProperty -Name "Target" -Value $targetvmFolderName
        $vmFolderArray += $vmFolderObject
    }
    $vmFolderObjects | Add-Member -MemberType NoteProperty -Name "VM Folder Mappings" -Value $vmFolderArray

    #build datastore folder mappings
    $datastoreFolderObjects = New-Object -TypeName psobject
    $datastoreFolderArray = @()
    foreach ($datastoreFolder in $datastoreFolders) {
        if ($source -eq $true)
        {
            $sourcedatastoreFolderName = $datastoreFolder.Name
            $targetdatastoreFolderName = "NULL--ENTER TARGET DATASTORE FOLDER NAME"
        }
        else 
        {
            $sourcedatastoreFolderName = "NULL--ENTER SOURCE DATASTORE FOLDER NAME"
            $targetdatastoreFolderName = $datastoreFolder.Name
        }
        $datastoreFolderObject = New-Object -TypeName psobject
        $datastoreFolderObject | Add-Member -MemberType NoteProperty -Name "Source" -Value $sourcedatastoreFolderName
        $datastoreFolderObject | Add-Member -MemberType NoteProperty -Name "Target" -Value $targetdatastoreFolderName
        $datastoreFolderArray += $datastoreFolderObject
    }
    $datastoreFolderObjects | Add-Member -MemberType NoteProperty -Name "Datastore Folder Mappings" -Value $datastoreFolderArray

    #build resource pool mappings
    $resourcePoolObjects = New-Object -TypeName psobject
    $resourcePoolArray = @()
    foreach ($resourcePool in $resourcePools) {
        if ($source -eq $true)
        {
            $sourceresourcePoolName = $resourcePool.Name
            $targetresourcePoolName = "NULL--ENTER TARGET RESOURCE POOL NAME"
        }
        else 
        {
            $sourceresourcePoolName = "NULL--ENTER SOURCE RESOURCE POOL NAME"
            $targetresourcePoolName = $resourcePool.Name
        }
        $resourcePoolObject = New-Object -TypeName psobject
        $resourcePoolObject | Add-Member -MemberType NoteProperty -Name "Source" -Value $sourceresourcePoolName
        $resourcePoolObject | Add-Member -MemberType NoteProperty -Name "Target" -Value $targetresourcePoolName
        $resourcePoolArray += $resourcePoolObject
    }
    $resourcePoolObjects | Add-Member -MemberType NoteProperty -Name "Resource Pool Mappings" -Value $resourcePoolArray
    $allMappings = @()
    $allMappings += $resourcePoolObjects
    $allMappings += $datastoreFolderObjects
    $allMappings += $vmFolderObjects
    $allMappings += $networkObjects
    $allMappings += $clusterObjects
    return $allMappings |Convertto-Json -Depth 4
}


function resignatureVolumes {
    $esxi = $cluster | Get-VMHost| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1 

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
      write-host "No unresolved volume found on the created volume. " -BackgroundColor Red
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

function new-InternalPfaRecoveryReport {
    param (
        [PureStorageVMwareVolumeProperties[]]$recoveryVolumes
    )
        $datastoreInfo = @()
        $allDatastores = get-datastore | Where-Object {$_.Type -eq 'VMFS'}
        $foundSourceDatastores = @()
        foreach ($recoveryVolume in $recoveryVolumes) 
        {
            if ($recoveryVolume.vmfs -eq $True)
            {
                $foundVMFS = $null
                $foundVMFS = $allDatastores | Where-Object {(($_.ExtensionData.Info.Vmfs.Extent[0].DiskName.ToUpper()).substring(12)) -eq $recoveryVolume.sourceVol.serial}
                $datastoreInfo +=  [pscustomobject]@{
                    Name = $foundVMFS.Name
                    NAA = ($foundVMFS.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique)
                    ("FlashArray Volume Name") = $recoveryVolume.sourceVol.Name
                    }
                $foundSourceDatastores += $foundVMFS
            }
        }
        $header = @"
<style>

    h1 {

        font-family: Arial, Helvetica, sans-serif;
        color: #FD5000;
        font-size: 28px;

    } 
    h2 {

        font-family: Arial, Helvetica, sans-serif;
        color: #FD5000;
        font-size: 16px;

    }
    h3 {

        font-family: Arial, Helvetica, sans-serif;
        font-size: 8px;

    }
    h4 {

        font-family: Arial, Helvetica, sans-serif;
        color: #000000;
        font-size: 16px;

    }
    th {
        background: #395870;
        background: #FA5000;
        color: #fff;
        font-size: 14px;
        padding: 10px 15px;
        vertical-align: left;
	}

    tbody tr:nth-child(even) {
        background: #f0f0f2;
    }
</style>
"@
        $foundVMs = $foundSourceDatastores |get-vm
        $HTMLheading = "<h1>Pure Storage ActiveDR Pre-Failover Report</h1>"
        $HTMLtime = "<h4>$(get-date)</h4>"
        $HTMLpod = "<h4>Failover Report for ActiveDR Pod $($sourcePod)</h4>"
        $HTMLVMFS = $datastoreInfo | ConvertTo-Html -Fragment -PreContent "<h2>VMFS Datastores ($($datastoreInfo.count))</h2>" -PostContent "<h3>These are discovered VMFS datastores that are hosted on volumes in the pod $($sourcePod)</h3>"
        $recoveryRDMs = $recoveryVolumes |where-object {$_.rdm -eq $true}
        $HTMLRDM =  $recoveryRDMs|Select-Object @{L='FlashArray Volume Name';E={$_.sourceVol.name}},@{L='RDM Serial';E={$_.sourceVol.serial}},@{L='VM Name(s)';E={$_.rdmmapping.vmname}} | ConvertTo-Html -Fragment -PreContent "<h2>Raw Device Mappings ($($recoveryRDMs.count))</h2>" -PostContent "<h3>These are discovered RDMs that are hosted on volumes in the pod $($sourcePod)</h3>"
        $unknownVolumes = $recoveryVolumes |where-object {$_.unknown -eq $true}
        $HTMLunknown = $unknownVolumes |Select-Object @{L='FlashArray Volume Name';E={$_.sourceVol.name}},@{L='Volume Serial';E={$_.sourceVol.serial}}| ConvertTo-Html -Fragment -PreContent "<h2>Presented Volumes but Unused ($($unknownVolumes.count))</h2>" -PostContent "<h3>These are discovered devices in the VMware environment that are hosted on volumes in the pod $($sourcePod) </h3>"
        $HTMLVMs = $foundVMs |Select-Object Name,ID| ConvertTo-Html -Fragment -PreContent "<h2>Virtual Machines ($($foundVMs.count))</h2>" -PostContent "<h3>These are virtual machines hosted by VMFS datastores in the pod $($sourcePod) </h3>"
        $Report = ConvertTo-HTML -Body "$HTMLheading $HTMLtime $HTMLpod $HTMLVMFS $HTMLRDM $HTMLunknown $HTMLVMs" -Title "Pure Storage ActiveDR Failover Report" -Head $header
        $Report | Out-File -FilePath .\ActiveDR-Recovery-Plan.html
}

function Stop-InternalPfaVM {
    param (
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
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
    )
    $shutdownVMs = $datastore |get-vm | where-object {$_.PowerState -ne "PoweredOff"} 
    if ($null -ne $shutdownVMs)
    {
        foreach ($shutdownVM in $shutdownVMs) 
        {
            if ($shutdownVM.guest.State -eq "Running")
            {
            $shutdownVM|Stop-VMGuest -confirm:$false |Out-Null
            }
            else 
            {
                $shutdownVM|Stop-VM -confirm:$false -RunAsync|Out-Null
            }
        }
    }
    $vms = $datastore |get-vm 
    if ($null -ne $vms)
    {
        do 
        {
            $powerState = ($datastore |get-vm).PowerState |Select-Object -Unique
        } 
        while (($powerState[0] -ne "PoweredOff") -or ($powerState.count -gt 1))
    }
}

function Disable-InternalPfaVMFS {
    param (
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
            [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
    )
    $esxiHosts = Get-VmHost -Id ($datastore.ExtensionData.Host.Key)
    $CanonicalName = $datastore.ExtensionData.Info.Vmfs.Extent[0].Diskname
    foreach ($vmHost in $esxiHosts)
    {
        $hostMountInfo = $datastore.ExtensionData.Host | Where-Object  {$_.Key -eq $VMHost.Id}
        if($hostMountInfo.MountInfo.Mounted -eq "True")
        {
                $hostStorageSystem = Get-View $VMHost.Extensiondata.ConfigManager.StorageSystem
                $hostStorageSystem.UnmountVmfsVolume($datastore.ExtensionData.info.Vmfs.uuid)
        } 
        Disable-InternalPfaLun -CanonicalName $CanonicalName -vmhost $vmHost
    }
}

function Disable-InternalPfaLun {
    param (
        [Parameter(Position=0,mandatory=$true)]
        [string]$CanonicalName,

        [Parameter(Position=1,mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$vmhost
    )
    $LunUuid = (Get-ScsiLun -VmHost $vmhost | Where-Object {$_.CanonicalName -eq $CanonicalName}).ExtensionData.Uuid
    $esxcli = Get-EsxCli -VMHost $vmHost -V2
    $scsiDev = $esxcli.storage.core.device.list.Invoke(@{device=$CanonicalName})
    if ($scsiDev.Status -eq "on")
    {
        $hostStorageSystem = Get-View $VMHost.Extensiondata.ConfigManager.StorageSystem
        $hostStorageSystem.DetachScsiLun($LunUuid)
    }
}
#custom classes

Class PureStorageVMwareRDMMapping{
    static [String] $version = "1.0.0"
    static [String] $vendor = "Pure Storage"
    static [String] $objectName = "Pure Storage RDM Mapping"
    [Int32]$sourceRDMvolKey = $null
    [Int32]$sourceRDMvolControllerKey = $null
    [Int32]$sourceRDMvolUnitNumber = $null
    [string]$sourceRDMsharing = ""
    [string]$rdmType = ""
    [string]$vmName = ""
    [string]$vmPersistentId = ""
}

Class PureStorageVMwareVolumeProperties{
    static [String] $version = "1.0.0"
    static [String] $vendor = "Pure Storage"
    static [String] $objectName = "Pure Storage Volume Properties"
    [PSCustomObject]$sourceVol = $null
    [PSCustomObject]$targetVol = $null
    [bool]$vmfs = $false
    [bool]$rdm = $false
    [bool]$unknown = $false
    [bool]$external = $false
    [PureStorageVMwareRDMMapping[]]$rdmMapping
    [string[]]$sourceClusterNames
}
