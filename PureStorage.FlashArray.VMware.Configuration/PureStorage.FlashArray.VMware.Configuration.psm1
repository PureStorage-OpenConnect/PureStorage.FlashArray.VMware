function new-pfaConnection {
  <#
  .SYNOPSIS
    Uses new-pfaarray to store the connection in a global parameter
  .DESCRIPTION
    Creates a FlashArray connection and stores it in global variable $Global:DefaultFlashArray. If you make more than one connection it will store them all in $Global:AllFlashArrays
  .INPUTS
    An FQDN or IP, credentials, and ignore certificate boolean
  .OUTPUTS
    Returns the FlashArray connection.
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  05/23/2019
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
      [string]$endpoint,

      [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
      [System.Management.Automation.PSCredential]$credentials,

      [Parameter(Position=2)]
      [switch]$defaultArray,

      [Parameter(Position=3)]
      [switch]$nonDefaultArray,

      [Parameter(Position=4)]
      [switch]$ignoreCertificateError
  )
  Begin {
      if (($true -eq $defaultArray) -and ($true -eq $nonDefaultArray))
      {
          throw "You can only specify defaultArray or nonDefaultArray, not both."
      }
      if (($false -eq $defaultArray) -and ($false -eq $nonDefaultArray))
      {
          throw "Please specify this to be either the new default array or a non-default array"
      }
      $ErrorActionPreference = "stop"
  }
  Process {
      if ($null -eq $Global:AllFlashArrays)
      {
          $Global:AllFlashArrays = @()
      }
      $flasharray = New-PfaArray -EndPoint $endpoint -Credentials $credentials -IgnoreCertificateError:$ignoreCertificateError
      $Global:AllFlashArrays += $flasharray
      if ($defaultArray -eq $true)
      {
          $Global:DefaultFlashArray = $flasharray
      }
  }
  End {
      return $flasharray
  } 
}
function get-pfaDatastore {
  <#
  .SYNOPSIS
    Retrieves all Pure Storage FlashArray datastores
  .DESCRIPTION
    Will return all FlashArray-based datastores, either VMFS or VVols, and if specified just for a particular FlashArray connection.
  .INPUTS
    A FlashArray connection, a cluster or VMhost, and filter of VVol or VMFS. All optional.
  .OUTPUTS
    Returns the relevant datastores.
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  06/04/2019
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

      [Parameter(Position=0,ValueFromPipeline=$True)]
      [PurePowerShell.PureArray]$flasharray,
    
      [Parameter(Position=1)]
      [switch]$vvol,

      [Parameter(Position=2)]
      [switch]$vmfs,

      [Parameter(Position=3,ValueFromPipeline=$True)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,
      
      [Parameter(Position=4,ValueFromPipeline=$True)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$esxi
  )
  if (($null -ne $esxi) -and ($null -ne $cluster))
  {
      throw "Please only pass in an ESXi host or a cluster, or neither"
  }
  if ($null -ne $esxi)
  {
      $datastores = $esxi | get-datastore
  }
  elseif ($null -ne $cluster) 
  {
      $datastores = $cluster | get-datastore
  }
  else {
      $datastores = get-datastore
  }
  if (($true -eq $vvol) -or (($false -eq $vvol) -and ($false -eq $vmfs)))
  {
    $vvolDatastores = $datastores  |where-object {$_.Type -eq "VVOL"} |Where-Object {$_.ExtensionData.Info.VvolDS.StorageArray[0].VendorId -eq "PURE"} 
    if ($null -ne $flasharray)
    {
      $arrayID = (Get-PfaArrayAttributes -Array $flasharray).id
      $vvolDatastores = $vvolDatastores |Where-Object {$_.ExtensionData.info.vvolDS.storageArray[0].uuid.substring(16) -eq $arrayID}
    }
  }
  if (($true -eq $vmfs) -or (($false -eq $vmfs) -and ($false -eq $vvol)))
  {
      $vmfsDatastores = $datastores  |where-object {$_.Type -eq "VMFS"} |Where-Object {$_.ExtensionData.Info.Vmfs.Extent.DiskName -like 'naa.624a9370*'} 
      if ($null -ne $flasharray)
      {
          $faVMFSdatastores = @()
          foreach ($vmfsDatastore in $vmfsDatastores)
          {
              try 
              {
                  get-pfaConnectionOfDatastore -datastore $vmfsDatastore -flasharrays $flasharray |Out-Null
                  $faVMFSdatastores += $vmfsDatastore
              }
              catch 
              {
                  continue
              }
          }
          $vmfsDatastores = $faVMFSdatastores
      }
  }
  $allDatastores = @()
  if ($null -ne $vmfsDatastores)
  {
      $allDatastores += $vmfsDatastores
  }
  if ($null -ne $vvolDatastores)
  {
      $allDatastores += $vvolDatastores
  }
  return $allDatastores
}
function get-pfaConnectionOfDatastore {
<#
.SYNOPSIS
  Takes in a VVol or VMFS datastore, one or more FlashArray connections and returns the correct connection.
.DESCRIPTION
  Will iterate through any connections stored in $Global:AllFlashArrays or whatever is passed in directly.
.INPUTS
  A datastore and one or more FlashArray connections
.OUTPUTS
  Returns the correct FlashArray connection.
.NOTES
  Version:        1.0
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
  [PurePowerShell.PureArray[]]$flasharrays,

  [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
  [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore
)
if ($null -eq $flasharrays)
{
    $flasharrays = getAllFlashArrays 
}
if ($datastore.Type -eq 'VMFS')
{
    $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
    if ($lun -like 'naa.624a9370*')
    { 
        $volserial = ($lun.ToUpper()).substring(12)
        foreach ($flasharray in $flasharrays)
        { 
            $pureVolumes = Get-PfaVolumes -Array  $flasharray
            $purevol = $purevolumes | where-object { $_.serial -eq $volserial }
            if ($null -ne $purevol.name)
            {
                return $flasharray
            }
        }
    }
    else 
    {
        throw "This VMFS is not hosted on FlashArray storage."
    }
}
elseif ($datastore.Type -eq 'VVOL') 
{
    $datastoreArraySerial = $datastore.ExtensionData.Info.VvolDS.StorageArray[0].uuid.Substring(16)
    foreach ($flasharray in $flasharrays)
    {
        $arraySerial = (Get-PfaArrayAttributes -array $flasharray).id
        if ($arraySerial -eq $datastoreArraySerial)
        {
            $Global:CurrentFlashArray = $flasharray
            return $flasharray
        }
    }
}
else 
{
    throw "This is not a VMFS or VVol datastore."
}
$Global:CurrentFlashArray = $null
throw "The datastore was not found on any of the FlashArray connections."
}
function new-pfaRestSession {
     <#
    .SYNOPSIS
      Connects to FlashArray and creates a REST connection.
    .DESCRIPTION
      For operations that are in the FlashArray REST, but not in the Pure Storage PowerShell SDK yet, this provides a connection for invoke-restmethod to use.
    .INPUTS
      FlashArray connection or FlashArray IP/FQDN and credentials
    .OUTPUTS
      Returns REST session
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
        [PurePowerShell.PureArray]$flasharray
    )
    #Connect to FlashArray
    if ($null -eq $flasharray)
    {
        $flasharray = checkDefaultFlashArray
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
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
  #Create FA REST session
    $SessionAction = @{
        api_token = $flasharray.ApiToken
    }
    Invoke-RestMethod -Method Post -Uri "https://$($flasharray.Endpoint)/api/$($flasharray.apiversion)/auth/session" -Body $SessionAction -SessionVariable Session -ErrorAction Stop |Out-Null
    $global:faRestSession = $Session
    return $global:faRestSession
}
function remove-pfaRestSession {
    <#
    .SYNOPSIS
      Disconnects a FlashArray REST session
    .DESCRIPTION
      Takes in a FlashArray Connection or session and disconnects on the FlashArray.
    .INPUTS
      FlashArray connection or session
    .OUTPUTS
      Returns success or failure.
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
            [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
            [Microsoft.PowerShell.Commands.WebRequestSession]$faSession,

            [Parameter(Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray]$flasharray
    )
      if ($null -eq $flasharray)
      {
          $flasharray = checkDefaultFlashArray
      }
      $purevip = $flasharray.endpoint
      $apiVersion = $flasharray.ApiVersion
      #Delete FA session
      Invoke-RestMethod -Method Delete -Uri "https://${purevip}/api/${apiVersion}/auth/session"  -WebSession $faSession -ErrorAction Stop |Out-Null
}
function new-pfaHostFromVmHost {
    <#
    .SYNOPSIS
      Create a FlashArray host from an ESXi vmhost object
    .DESCRIPTION
      Takes in a vCenter ESXi host and creates a FlashArray host
    .INPUTS
      FlashArray connection, a vCenter ESXi vmHost, and iSCSI/FC option
    .OUTPUTS
      Returns new FlashArray host object.
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
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$esxi,

            [Parameter(Position=1)]
            [string]$protocolType,

            [Parameter(Position=2,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$flasharray,

            [Parameter(Position=3)]
            [switch]$iscsi,

            [Parameter(Position=4)]
            [switch]$fc
    )
    Begin {
      if (($protocolType -eq "FC") -and ($protocolType -eq "iSCSI"))
      {
          Write-Warning -Message "The protocolType parameter is being deprecated, please use the -fc or -iscsi switch parameters instead."
      }
      if (($protocolType -ne "FC") -and ($protocolType -ne "iSCSI") -and ($iscsi -ne $true) -and ($protocolType -ne $true))
      {
          throw 'No valid protocol entered. Please add the -fc or -iscsi switch parameter"'
      }
      if (($iscsi -eq $true) -and ($protocolType -eq $true))
      {
          throw "You cannot use both the -fc and -iscsi switch"
      }
      if (($iscsi -eq $true) -and ($protocolType -eq "FC"))
      {
          throw "You cannot use the iSCSI switch parameter and specify FC in the protocolType option. The protocolType parameter is being deprecated."
      }
      if (($fc -eq $true) -and ($protocolType -eq "iSCSI"))
      {
          throw "You cannot use the FC switch parameter and specify iSCSI in the protocolType option. The protocolType parameter is being deprecated."
      }
      if ($protocolType -eq "FC")
      {
        $fc = $true
      }
      if ($protocolType -eq "iSCSI")
      {
        $iscsi = $true
      }
      $vmHosts = @()
    } 
    Process 
    {
        if ($null -eq $flasharray)
        {
          $flasharray = checkDefaultFlashArray
        }
        foreach ($fa in $flasharray)
        {
            if ($iscsi -eq $true)
            {
                $iscsiadapter = $esxi | Get-VMHostHBA -Type iscsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
                if ($null -eq $iscsiadapter)
                {
                    throw "No Software iSCSI adapter found on host $($esxi.NetworkInfo.HostName)."
                }
                else
                {
                    $iqn = $iscsiadapter.ExtensionData.IScsiName
                }
                try
                {
                    $newFaHost = New-PfaHost -Array $fa -Name $esxi.NetworkInfo.HostName -IqnList $iqn -ErrorAction stop
                    $vmHosts += $newFaHost
                }
                catch
                {
                    Write-Error $Global:Error[0]
                    return $null
                }
            }
            if ($fc -eq $true)
            {
                $wwns = $esxi | Get-VMHostHBA -Type FibreChannel | Select-Object VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
                $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
                $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
                {
                        $wwns.substring($i,16)
                }}
                try
                {
                    $newFaHost = New-PfaHost -Array $fa -Name $esxi.NetworkInfo.HostName -WwnList $wwns -ErrorAction stop
                    $vmHosts += $newFaHost
                    $Global:CurrentFlashArray = $fa
                }
                catch
                {
                    Write-Error $Global:Error[0]
                }
            }
        }
    }
    End {
      return $vmHosts
    }  
}
function get-pfaHostFromVmHost {
    <#
    .SYNOPSIS
      Gets a FlashArray host object from a ESXi vmhost object
    .DESCRIPTION
      Takes in a vmhost and returns a matching FA host if found
    .INPUTS
      FlashArray connection and a vCenter ESXi host
    .OUTPUTS
      Returns FA host if matching one is found.
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$esxi,

        [Parameter(Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$flasharray
    )
    if ($null -eq $flasharray)
    {
      $flasharray = checkDefaultFlashArray
    }
    $iscsiadapter = $esxi | Get-VMHostHBA -Type iscsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
    $wwns = $esxi | Get-VMHostHBA -Type FibreChannel | Select-Object VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
    $wwns = (($wwns.Replace("`n","")).Replace("`r","")).Replace(" ","")
    $wwns = &{for ($i = 0;$i -lt $wwns.length;$i += 16)
    {
            $wwns.substring($i,16)
    }}
    $fahosts = Get-PFAHosts -array $flasharray -ErrorAction Stop
    if ($null -ne $iscsiadapter)
    {
        $iqn = $iscsiadapter.ExtensionData.IScsiName
        foreach ($fahost in $fahosts)
        {
            if ($fahost.iqn.count -ge 1)
            {
                foreach ($fahostiqn in $fahost.iqn)
                {
                    if ($iqn.ToLower() -eq $fahostiqn.ToLower())
                    {
                        $faHostMatch = $fahost
                    }
                }
            }
        }   
    }
    if (($null -ne $wwns) -and ($null -eq $faHostMatch))
    {
        foreach ($wwn in $wwns)
        {
            foreach ($fahost in $fahosts)
            {
                if ($fahost.wwn.count -ge 1)
                {
                    foreach($fahostwwn in $fahost.wwn)
                    {
                        if ($wwn.ToLower() -eq $fahostwwn.ToLower())
                        {
                          $faHostMatch = $fahost
                        }
                    }
                }
            }
        }
    }
    if ($null -ne $faHostMatch)
    { 
      $Global:CurrentFlashArray = $flasharray
      return $faHostMatch
    }
    else 
    {
        throw "No matching host could be found on the FlashArray $($flasharray.EndPoint)"
    }
}
function get-pfaHostGroupfromVcCluster {
    <#
    .SYNOPSIS
      Retrieves a FA host group from an ESXi cluster
    .DESCRIPTION
      Takes in a vCenter Cluster and retrieves corresonding host group
    .INPUTS
      FlashArray connection and a vCenter cluster
    .OUTPUTS
      Returns success or failure.
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

        [Parameter(Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$flasharray
    )
    if ($null -eq $flasharray)
    {
      $flasharray = checkDefaultFlashArray
    }
    $esxiHosts = $cluster |Get-VMHost
    $faHostGroups = @()
    $faHostGroupNames = @()
    foreach ($esxiHost in $esxiHosts)
    {
        try {
            $faHost = $esxiHost | get-pfaHostFromVmHost -flasharray $flasharray
            if ($null -ne $faHost.hgroup)
            {
                if ($faHostGroupNames.contains($faHost.hgroup))
                {
                    continue
                }
                else {
                    $faHostGroupNames += $faHost.hgroup
                    $faHostGroup = Get-PfaHostGroup -Array $flasharray -Name $faHost.hgroup
                    $faHostGroups += $faHostGroup
                }
            }
        }
        catch{
            continue
        }
    }
    if ($null -eq $faHostGroup)
    {
        throw "No host group found for this cluster on $($flasharray.EndPoint). You can create a host group with new-pfahostgroupfromvcCluster"
    }
    if ($faHostGroups.count -gt 1)
    {
        Write-Warning -Message "This cluster spans more than one host group. The recommendation is to have only one host group per cluster"
    }
    $Global:CurrentFlashArray = $flasharray
    return $faHostGroups
}
function new-pfaHostGroupfromVcCluster {
    <#
    .SYNOPSIS
      Create a host group from an ESXi cluster
    .DESCRIPTION
      Takes in a vCenter Cluster and creates hosts (if needed) and host group
    .INPUTS
      FlashArray connection, a vCenter cluster, and iSCSI/FC option
    .OUTPUTS
      Returns success or failure.
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
        
        [Parameter(Position=1)]
        [string]$protocolType,

        [Parameter(Position=2,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray[]]$flasharray,

        [Parameter(Position=3)]
        [switch]$iscsi,

        [Parameter(Position=4)]
        [switch]$fc
    )
    Begin {
      if (($protocolType -eq "FC") -and ($protocolType -eq "iSCSI"))
      {
          Write-Warning -Message "The protocolType parameter is being deprecated, please use the -fc or -iscsi switch parameters instead."
      }
      if (($protocolType -ne "FC") -and ($protocolType -ne "iSCSI") -and ($iscsi -ne $true) -and ($protocolType -ne $true))
      {
          throw 'No valid protocol entered. Please add the -fc or -iscsi switch parameter"'
      }
      if (($iscsi -eq $true) -and ($protocolType -eq $true))
      {
          throw "You cannot use both the -fc and -iscsi switch"
      }
      if (($iscsi -eq $true) -and ($protocolType -eq "FC"))
      {
          throw "You cannot use the iSCSI switch parameter and specify FC in the protocolType option. The protocolType parameter is being deprecated."
      }
      if (($fc -eq $true) -and ($protocolType -eq "iSCSI"))
      {
          throw "You cannot use the FC switch parameter and specify iSCSI in the protocolType option. The protocolType parameter is being deprecated."
      }
      if ($protocolType -eq "FC")
      {
        $fc = $true
      }
      if ($protocolType -eq "iSCSI")
      {
        $iscsi = $true
      }
      $pfaHostGroups = @()
    } 
    Process 
    {
        if ($null -eq $flasharray)
        {
          $flasharray = checkDefaultFlashArray
        }
        foreach ($fa in $flasharray)
        {

            $hostGroup =  get-pfaHostGroupfromVcCluster -flasharray $fa -ErrorAction SilentlyContinue -cluster $cluster
            if ($hostGroup.count -gt 1)
            {
                throw "The cluster already is configured on the FlashArray and spans more than one host group. This cmdlet does not support a multi-hostgroup configuration."
            }
            if ($null -ne $hostGroup)
            {
                $clustername = $hostGroup.name
            }
            $esxiHosts = $cluster |Get-VMHost
            $faHosts = @()
            foreach ($esxiHost in $esxiHosts)
            {
                $faHost = $null
                try {
                    $faHost = get-pfaHostFromVmHost -flasharray $fa -esxi $esxiHost
                }
                catch {}
                if ($null -eq $faHost)
                {
                    try {
                        $faHost = new-pfaHostFromVmHost -flasharray $fa -iscsi:$iscsi -fc:$fc -ErrorAction Stop -esxi $esxiHost
                        $faHosts += $faHost
                    }
                    catch {
                        Write-Error $Global:Error[0]
                        throw "Could not create host. Cannot create host group." 
                    }
                    
                }
                else {
                    $faHosts += $faHost
                }
            }
            #FlashArray only supports Alphanumeric or the dash - character in host group names. Checking for VMware cluster name compliance and removing invalid characters.
            if ($null -eq $hostGroup)
            {
                if ($cluster.Name -match "^[a-zA-Z0-9\-]+$")
                {
                    $clustername = $cluster.Name
                }
                else
                {
                    $clustername = $cluster.Name -replace "[^\w\-]", ""
                    $clustername = $clustername -replace "[_]", ""
                    $clustername = $clustername -replace " ", ""
                }
                $hg = Get-PfaHostGroup -Array $fa -Name $clustername -ErrorAction SilentlyContinue
                if ($null -ne $hg)
                {
                    if ($hg.hosts.count -ne 0)
                    {
                        #if host group name is already in use and has only unexpected hosts i will create a new one with a random number at the end
                        $nameRandom = get-random -Minimum 1000 -Maximum 9999
                        $hostGroup = New-PfaHostGroup -Array $fa -Name "$($clustername)-$($nameRandom)" -ErrorAction stop
                        $clustername = "$($clustername)-$($nameRandom)"
                    }
                }
                else {
                    #if there is no host group, it will be created
                    $hostGroup = New-PfaHostGroup -Array $fa -Name $clustername -ErrorAction stop
                }
            }
            $faHostNames = @()
            foreach ($faHost in $faHosts)
            {
                if ($null -eq $faHost.hgroup)
                {
                    $faHostNames += $faHost.name
                }
            }
            #any hosts that are not already in the host group will be added
            Add-PfaHosts -Array $fa -Name $clustername -HostsToAdd $faHostNames -ErrorAction Stop |Out-Null
            $Global:CurrentFlashArray = $fa
            $fahostGroup = Get-PfaHostGroup -Array $fa -Name $clustername
            $pfaHostGroups += $fahostGroup
        }
    }
    End 
    {
      return $pfaHostGroups
    }   
}
function set-vmHostPfaiSCSI{
    <#
    .SYNOPSIS
      Configure FlashArray iSCSI target information on ESXi host
    .DESCRIPTION
      Takes in an ESXi host and configures FlashArray iSCSI target info
    .INPUTS
      FlashArray connection and an ESXi host
    .OUTPUTS
      Returns ESXi iSCSI targets.
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$esxi,

        [Parameter(Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray[]]$flasharray
    )
    Begin {
      $allESXitargets = @()
    }
    Process {
        if ($null -eq $flasharray)
        {
          $flasharray = checkDefaultFlashArray
        }
        foreach ($fa in $flasharray)
        {
            if ($esxi.ExtensionData.Runtime.ConnectionState -ne "connected")
            {
                Write-Warning "Host $($esxi.NetworkInfo.HostName) is not in a connected state and cannot be configured."
                return
            }
            $ESXitargets = @()
            $faiSCSItargets = Get-PfaNetworkInterfaces -Array $fa |Where-Object {$_.services -eq "iscsi"} |Where-Object {$_.enabled -eq $true} | Where-Object {$null -ne $_.address}
            if ($null -eq $faiSCSItargets)
            {
                throw "The target FlashArray does not currently have any iSCSI targets configured."
            }
            $iscsi = $esxi |Get-VMHostStorage
            if ($iscsi.SoftwareIScsiEnabled -ne $true)
            {
                $esxi | get-vmhoststorage |Set-VMHostStorage -SoftwareIScsiEnabled $True |out-null
            }
            foreach ($faiSCSItarget in $faiSCSItargets)
            {
                $iscsiadapter = $esxi | Get-VMHostHba -Type iScsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
                if (!(Get-IScsiHbaTarget -IScsiHba $iscsiadapter -Type Send -ErrorAction stop | Where-Object {$_.Address -cmatch $faiSCSItarget.address}))
                {
                    New-IScsiHbaTarget -IScsiHba $iscsiadapter -Address $faiSCSItarget.address -ErrorAction stop 
                }
                $esxcli = $esxi |Get-esxcli -v2 
                $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.CreateArgs()
                $iscsiargs.adapter = $iscsiadapter.Device
                $iscsiargs.address = $faiSCSItarget.address
                $delayedAck = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "DelayedAck"}
                $loginTimeout = $esxcli.iscsi.adapter.discovery.sendtarget.param.get.invoke($iscsiargs) |where-object {$_.name -eq "LoginTimeout"}
                if ($delayedAck.Current -eq "true")
                {
                    $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
                    $iscsiargs.adapter = $iscsiadapter.Device
                    $iscsiargs.address = $faiSCSItarget.address
                    $iscsiargs.value = "false"
                    $iscsiargs.key = "DelayedAck"
                    $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
                }
                if ($loginTimeout.Current -ne "30")
                {
                    $iscsiargs = $esxcli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
                    $iscsiargs.adapter = $iscsiadapter.Device
                    $iscsiargs.address = $faiSCSItarget.address
                    $iscsiargs.value = "30"
                    $iscsiargs.key = "LoginTimeout"
                    $esxcli.iscsi.adapter.discovery.sendtarget.param.set.invoke($iscsiargs) |out-null
                }
                $ESXitargets += Get-IScsiHbaTarget -IScsiHba $iscsiadapter -Type Send -ErrorAction stop | Where-Object {$_.Address -cmatch $faiSCSItarget.address}
            }
            $allESXitargets += $ESXitargets
            $Global:CurrentFlashArray = $fa
          }
    }
    End {
      return $allESXitargets
    }  
}
function set-clusterPfaiSCSI {
    <#
    .SYNOPSIS
      Configure an ESXi cluster with FlashArray iSCSI information
    .DESCRIPTION
      Takes in a vCenter Cluster and configures iSCSI on each host.
    .INPUTS
      FlashArray connection and a vCenter cluster.
    .OUTPUTS
      Returns iSCSI targets.
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
        [PurePowerShell.PureArray[]]$flasharray
    )
    Begin {
      $allEsxiiSCSItargets = @()
    }
    Process 
    {
        if ($null -eq $flasharray)
        {
          $flasharray = checkDefaultFlashArray
        }
        foreach ($fa in $flasharray)
        {
            $esxihosts = $cluster |Get-VMHost
            $esxiiSCSItargets = @()
            $hostCount = 0
            foreach ($esxihost in $esxihosts)
            {
                if ($hostCount -eq 0)
                {
                    Write-Progress -Activity "Configuring iSCSI" -status "Host: $esxihost" -percentComplete 0
                }
                else {
                    Write-Progress -Activity "Configuring iSCSI" -status "Host: $esxihost" -percentComplete (($hostCount / $esxihosts.count) *100)
                }
                $esxiiSCSItargets +=  set-vmHostPfaiSCSI -flasharray $fa -esxi $esxihost 
                $hostCount++
            }
            $allEsxiiSCSItargets += $esxiiSCSItargets
            $Global:CurrentFlashArray = $fa
        }
    }
    End 
    { 
      return $allEsxiiSCSItargets
    }
}

New-Alias -Name new-pureflasharrayRestSession -Value new-pfaRestSession
New-Alias -Name remove-pureflasharrayRestSession -Value remove-pfaRestSession
New-Alias -Name new-faHostFromVmHost -Value new-pfaHostFromVmHost
New-Alias -Name get-faHostFromVmHost -Value get-pfaHostFromVmHost
New-Alias -Name get-faHostGroupfromVcCluster -Value get-pfaHostGroupfromVcCluster 
New-Alias -Name new-faHostGroupfromVcCluster -Value new-pfaHostGroupfromVcCluster
New-Alias -Name set-vmHostPureFaiSCSI -Value set-vmHostPfaiSCSI
New-Alias -Name set-clusterPureFAiSCSI -Value set-clusterPfaiSCSI


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
