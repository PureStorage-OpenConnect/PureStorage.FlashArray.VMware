function New-PfaConnection {
  <#
  .SYNOPSIS
    Uses New-Pfaarray to store the connection in a global parameter
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
function Get-PfaDatastore {
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
      $datastores = $esxi | Get-datastore
  }
  elseif ($null -ne $cluster) 
  {
      $datastores = $cluster | Get-datastore
  }
  else {
      $datastores = Get-datastore
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
                  Get-PfaConnectionOfDatastore -datastore $vmfsDatastore -flasharrays $flasharray |Out-Null
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
function Get-PfaConnectionOfDatastore {
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
function Get-PfaConnectionFromArrayId {
  <#
  .SYNOPSIS
    Retrieves the FlashArray connection from the specified array ID.
  .DESCRIPTION
    Retrieves the FlashArray connection from the specified array ID.
  .INPUTS
    FlashArray array ID/serial
  .OUTPUTS
    FlashArray connection.
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  06/10/2019
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
      [PurePowerShell.PureArray[]]$flasharrays,

      [Parameter(Position=1,mandatory=$true)]
      [string]$arrayId
  )
  if ($null -eq $flasharrays)
  {
      $flasharrays = getAllFlashArrays 
  }
  foreach ($flasharray in $flasharrays)
  {
      $returnedID = (Get-PfaArrayAttributes -Array $flasharray).id
      if ($returnedID.ToLower() -eq $arrayId.ToLower())
      {
          return $flasharray
      }
  }
  throw "FlashArray connection not found for serial $($arrayId)"
}
function New-PfaRestSession {
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
function Remove-PfaRestSession {
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
function New-PfaHostFromVmHost {
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
function Get-PfaHostFromVmHost {
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
function Get-PfaHostGroupfromVcCluster {
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
            $faHost = $esxiHost | Get-PfaHostFromVmHost -flasharray $flasharray
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
        throw "No host group found for this cluster on $($flasharray.EndPoint). You can create a host group with New-PfahostgroupfromvcCluster"
    }
    if ($faHostGroups.count -gt 1)
    {
        Write-Warning -Message "This cluster spans more than one host group. The recommendation is to have only one host group per cluster"
    }
    $Global:CurrentFlashArray = $flasharray
    return $faHostGroups
}
function New-PfaHostGroupfromVcCluster {
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

            $hostGroup =  Get-PfaHostGroupfromVcCluster -flasharray $fa -ErrorAction SilentlyContinue -cluster $cluster
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
                    $faHost = Get-PfaHostFromVmHost -flasharray $fa -esxi $esxiHost
                }
                catch {}
                if ($null -eq $faHost)
                {
                    try {
                        $faHost = New-PfaHostFromVmHost -flasharray $fa -iscsi:$iscsi -fc:$fc -ErrorAction Stop -esxi $esxiHost
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
                        $nameRandom = Get-random -Minimum 1000 -Maximum 9999
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
function Set-VmHostPfaiSCSI{
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
                $esxi | Get-vmhoststorage |Set-VMHostStorage -SoftwareIScsiEnabled $True |out-null
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
function Set-ClusterPfaiSCSI {
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
                $esxiiSCSItargets +=  Set-vmHostPfaiSCSI -flasharray $fa -esxi $esxihost 
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
function Install-PfavSpherePlugin {
  <#
  .SYNOPSIS
    Installs or updates the FlashArray vSphere Plugin
  .DESCRIPTION
    Install or updates the vSphere Plugin, HTML or Flash version.
  .INPUTS
    A plugin download source (FlashArray or Pure1), plugin type, or version.
  .OUTPUTS
    Returns registered extension.
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin 
    
    Installs the plugin the latest HTML-5 plugin located on Pure1 to the connected vCenter
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin -confirm:$false
    
    Installs the plugin the latest HTML-5 plugin located on Pure1 to the connected vCenter without prompting for confirmation
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin -flash -version 3.1.2
    
    Installs the Flash 3.1.2 plugin located on Pure1 to the connected vCenter.  
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin -address 10.21.20.20
    
    Installs the plugin that is hosted on the specified FlashArray IP to the connected vCenter. 
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin -address flasharray.purestorage.com
    
    Installs the plugin that is hosted on the specified FlashArray FQDN to the connected vCenter. 
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  07/13/2019
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
          [Parameter(Position=0,ValueFromPipeline=$True)]
          [PurePowerShell.PureArray]$flasharray,

          [Parameter(Position=1)]
          [string]$source,

          [Parameter(Position=2)]
          [switch]$html,

          [Parameter(Position=3)]
          [switch]$flash,

          [Parameter(Position=4)]
          [string]$version
      )
  $ErrorActionPreference = "Stop"
  if (($version -ne "") -and (($version -match '[0-9]+\.[0-9]+\.[0-9]+$') -eq $false))
  {
    throw "Invalid version syntax. Please enter it in the form of x.x.x like 4.0.0 or 3.1.12"
  }
  if (($html -eq $true) -and ($flash -eq $true))
  {
    throw "Please only use the -html switch, or the -flash switch. Not both."
  }
  if (($html -eq $false) -and ($flash -eq $false) -and ($null -eq $version))
  {
    $html = $true
  }
  if ($null -ne $flasharray)
  {
    $ipAddress = (Get-PfaNetworkInterface -Array $flasharray -Name vir0).address
  }
  elseif (($source -ne "Pure1") -and !([string]::IsNullOrWhiteSpace($source)))
  {
    $ipAddress = [System.Net.Dns]::GetHostAddresses($source).IPAddressToString
  }
  elseif (($source -eq "Pure1") -or ([string]::IsNullOrWhiteSpace($source)))
  {
    if ($flash -eq $true)
    {
      $ipAddress = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/Flex/purestorage-vsphere-plugin.zip"
    }
    else 
    {
      $ipAddress = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5/purestorage-vsphere-plugin.zip"
    }
    $source = "Pure1"
  }
  #gather extension manager
  $services = Get-view 'ServiceInstance'
  $extensionMgr  = Get-view $services.Content.ExtensionManager

  #find what plugins are installed and their version
  $installedHtmlVersion = ($extensionMgr.FindExtension("com.purestorage.purestoragehtml")).version
  $installedFlashVersion = ($extensionMgr.FindExtension("com.purestorage.plugin.vsphere")).version

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

  #identify version of the plugin on the array
  if ($source -eq "Pure1")
  {
    $hostedVersion = (Get-PfavSpherePlugin -html:$html -flash:$flash -version $version).Version
  }
  else 
  {
    $hostedVersion = (Get-PfavSpherePlugin -html:$html -flash:$flash -version $version -source $ipAddress).Version
  }
  if ($null -eq $hostedVersion)
  {
    throw "Specified plugin type or version not found on available source"
  }

  #find out what plugin will be installed and whether it is an upgrade. Will fail if newer version is on vCenter
  $upgrade = $false
  if ($hostedVersion.split(".")[0] -ge 4)
  {
      if ($null -ne $installedHtmlVersion)
      {
          $splitInstalled = $installedHtmlVersion.split(".")
          $splitHosted = $hostedVersion.split(".")
          if ($splitInstalled[0] -eq $splitHosted[0])
          {
              if ($splitInstalled[1] -eq $splitHosted[1])
              {
                  if ($splitInstalled[2] -lt $splitHosted[2])
                  {
                      $upgrade = $true
                  }
                  elseif ($splitInstalled[2] -eq $splitHosted[2])
                  {
                      throw "The installed version of the plugin ($($installedHtmlVersion)) is the same as the version on the specified source ($($hostedVersion))"
                  }
                  elseif ($splitInstalled[2] -gt $splitHosted[2])
                  {
                      throw "The installed version of the plugin ($($installedHtmlVersion)) is newer than the version on the specified source ($($hostedVersion))"
                  }
              }
              elseif ($splitInstalled[1] -lt $splitHosted[1]) 
              {
                  $upgrade = $true
              }
              else {
                  throw "The installed version of the plugin ($($installedHtmlVersion)) is newer than the version on the specified source ($($hostedVersion))"
              }
          }
          elseif ($splitInstalled[0] -lt $splitHosted[0]) 
          {
              $upgrade = $true
          }
          else {
              throw "The installed version of the plugin ($($installedHtmlVersion)) is newer than the version on the specified source ($($hostedVersion))"
          }
      }
  }
  elseif ($hostedVersion.split(".")[0] -eq 3) 
  {
      if ($null -ne $installedFlashVersion)
      {
          $splitInstalled = $installedFlashVersion.split(".")
          $splitHosted = $hostedVersion.split(".")
          if ($splitInstalled[0] -eq $splitHosted[0])
          {
              if ($splitInstalled[1] -eq $splitHosted[1])
              {
                  if ($splitInstalled[2] -lt $splitHosted[2])
                  {
                      $upgrade = $true
                  }
                  elseif ($splitInstalled[2] -eq $splitHosted[2])
                  {
                      throw "The installed version of the plugin ($($installedFlashVersion)) is the same as the version on the specified source ($($hostedVersion))"
                  }
                  elseif ($splitInstalled[2] -gt $splitHosted[2])
                  {
                      throw "The installed version of the plugin ($($installedFlashVersion)) is newer than the version on the specified source ($($hostedVersion))"
                  }
              }
              elseif ($splitInstalled[1] -lt $splitHosted[1]) 
              {
                  $upgrade = $true
              }
              else {
                  throw "The installed version of the plugin ($($installedFlashVersion)) is newer than the version on the specified source ($($hostedVersion))"
              }
          }
          elseif ($splitInstalled[0] -lt $splitHosted[0]) 
          {
              $upgrade = $true
          }
          else {
              throw "The installed version of the plugin ($($installedFlashVersion)) is newer than the version on the specified source ($($hostedVersion))"
          }
      }
  }
  
  #build extension to register. Will pull the SSL thumprint from the target address
  $description = New-Object VMware.Vim.Description
  $description.label = "Pure Storage Plugin"
  $description.summary = "Pure Storage vSphere Plugin for Managing FlashArray"


  $extensionClientInfo = New-Object VMware.Vim.ExtensionClientInfo
  $extensionClientInfo.Company = "Pure Storage, Inc."
  $extensionClientInfo.Description = $description
  $extensionClientInfo.Type = 	"vsphere-client-serenity"
  if ($source -eq "Pure1")
  {
    if ($flash -eq $true)
    {
      $extensionClientInfo.Url = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/Flex/purestorage-vsphere-plugin.zip"
    }
    else 
    {
      $extensionClientInfo.Url = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5/purestorage-vsphere-plugin.zip"
    }
  }
  else {
      $extensionClientInfo.Url = "https://$($ipAddress)/download/purestorage-vsphere-plugin.zip?version=$($hostedVersion)"
  }
  $extensionClientInfo.Version = $hostedVersion

  $extensionServerInfo = New-Object VMware.Vim.ExtensionServerInfo
  $extensionServerInfo.AdminEmail = "admin@purestorage.com"
  $extensionServerInfo.Company = "Pure Storage, Inc."
  $extensionServerInfo.Description = $description
  if ($source -eq "Pure1")
  {
    if ($flash -eq $true)
    {
      $extensionServerInfo.Url = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/Flex/purestorage-vsphere-plugin.zip"
      $extensionServerInfo.ServerThumbprint =  (Get-SSLThumbprint "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/Flex/purestorage-vsphere-plugin.zip")
    }
    else 
    {
      $extensionServerInfo.Url = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5/purestorage-vsphere-plugin.zip"
      $extensionServerInfo.ServerThumbprint =  (Get-SSLThumbprint "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5/purestorage-vsphere-plugin.zip")
    }
  }
  else {
    $extensionServerInfo.ServerThumbprint =  (Get-SSLThumbprint "https://$($ipAddress)")
    $extensionServerInfo.Url = "https://$($ipAddress)/download/purestorage-vsphere-plugin.zip?version=$($hostedVersion)"
  }
  $extensionServerInfo.Type = "https"

  $extensionSpec = New-Object VMware.Vim.Extension
  if ($hostedVersion.split(".")[0] -eq 3)
  {
      $extensionSpec.key = "com.purestorage.plugin.vsphere"
      $pluginType = "Flash"
      $pluginVersion = $installedFlashVersion
  } 
  else 
  {
      $extensionSpec.key = "com.purestorage.purestoragehtml"
      $pluginType = "HTML-5"
      $pluginVersion = $installedHtmlVersion
  }
  $extensionSpec.version = $hostedVersion
  $extensionSpec.Description = $description
  $extensionSpec.Client += $extensionClientInfo
  $extensionSpec.Server += $extensionServerInfo

  if ($source -ne "Pure1")
  {
    $source = $ipAddress
  }
    if ($upgrade -eq $true)
  {

    $confirmText = "Upgrade $($pluginType) plugin from version $($pluginVersion) to $($hostedVersion) on vCenter $($global:DefaultVIServer.name)?"
  }
  else {
    $confirmText = "Install $($pluginType) plugin version $($hostedVersion) on vCenter $($global:DefaultVIServer.name)?"
  }

  if ($PSCmdlet.ShouldProcess("","$($confirmText)`n`r","Using $($source) as the download location`n`r")) 
  {
    #install or upgrade the vSphere plugin
    if ($upgrade -eq $true)
    {
        $extensionMgr.UpdateExtension($extensionSpec)
    }
    else 
    {
        $extensionMgr.RegisterExtension($extensionSpec)
    }
    return $extensionMgr.FindExtension($extensionSpec.Key)
  }
}
function Get-PfavSpherePlugin {
  <#
  .SYNOPSIS
    Retrieves version of FlashArray vSphere Plugin on one or more FlashArrays 
  .DESCRIPTION
    Retrieves version of FlashArray vSphere Plugin on one or more FlashArrays
  .INPUTS
    One or more FlashArray connections/FQDN/IPs
  .OUTPUTS
    Returns plugin version for each array.
  .EXAMPLE
    PS C:\ Get-PfavSpherePlugin
    
    Retrieves the vSphere plugin versions available on Pure1.
  .EXAMPLE
    PS C:\ $fa = new-pfaarray -endpoint flasharray-m20-1 -credentials (get-credential) -ignoreCertificateError 
    PS C:\ Get-PfavSpherePlugin -FlashArray $fa
    
    Retrieves the vSphere plugin version from the target FlashArray connection and Pure1.
  .EXAMPLE
    PS C:\ new-pfaconnection -endpoint flasharray-m20-1 -credentials (get-credential) -ignoreCertificateError -nonDefaultArray
    PS C:\ new-pfaconnection -endpoint flasharray-420-1 -credentials (get-credential) -ignoreCertificateError -nonDefaultArray
    PS C:\ Get-PfavSpherePlugin 
    
    Retrieves the vSphere plugin version from the FlashArray connections stored in the global variable $Global:AllFlashArrays and Pure1.
  .EXAMPLE
    PS C:\ Get-PfavSpherePlugin -address "10.21.202.52","flasharray-m20-1",10.21.88.7
    
    Retrieves the vSphere plugin version from the FlashArray IPs or FQDNs and Pure1
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  07/13/2019
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
          [PurePowerShell.PureArray[]]$flasharray,

          [Parameter(Position=1)]
          [string[]]$source,

          [Parameter(Position=2)]
          [switch]$html,

          [Parameter(Position=3)]
          [switch]$flash,

          [Parameter(Position=4)]
          [string]$version
      )
  if (($version -ne "") -and (($version -match '[0-9]+\.[0-9]+\.[0-9]+$') -eq $false))
  {
    throw "Invalid version syntax. Please enter it in the form of x.x.x like 4.0.0 or 3.1.12"
  }
  if (($flasharray.count -eq 0) -and ($source.count -eq 0))
  {
      $flasharray = $Global:AllFlashArrays
  }
  #identify version of the plugin on the array
  $targetAddresses = @()  
  foreach ($fa in $flasharray)
  {
    $ipAddress = (Get-PfaNetworkInterface -Array $fa -Name vir0).address
    try {
      $targetAddresses += ([system.net.dns]::GetHostByAddress($ipAddress)).HostName
    }
    catch {
      $targetAddresses += $ipAddress
    }
  }
  foreach ($ipTarget in $source)
  {
    try {
      $targetAddresses += ([system.net.dns]::GetHostByAddress($ipTarget)).HostName
    }
    catch {
      $targetAddresses += $ipTarget
    }
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
  $hostedVersions = @()
  foreach ($targetAddress in $targetAddresses)
  {
      $hostedVersion = $null
      for ($major=0; $major -le 9; $major++)
      {
          if ($null -ne $hostedVersion)
          {
              break
          }
          for ($minor=0; $minor -le 9; $minor++)
          {
              $HTTP_Request = [System.Net.WebRequest]::Create("https://$($targetAddress)/download/purestorage-vsphere-plugin.zip?version=4.$($major).$($minor)")
              try {
                  $HTTP_Response = $null
                  $HTTP_Request.Timeout = 500
                  $HTTP_Response = $HTTP_Request.GetResponse() 
                  $HTTP_Status = [int]$HTTP_Response.StatusCode
                  If ($HTTP_Status -eq 200) 
                  {
                      $hostedVersion = "4.$($major).$($minor)"
                      $hostedVersions += $hostedVersion
                      break
                  }
              }
              catch {}
          }
      }
      
      if ($null -eq $hostedVersion)
      {
          $HTTP_Request = [System.Net.WebRequest]::Create("https://$($targetAddress)/download/purestorage-vsphere-plugin.zip?version=4.0.999999")
          try {
              $HTTP_Response = $null
              $HTTP_Request.Timeout = 500
              $HTTP_Response = $HTTP_Request.GetResponse() 
              $HTTP_Status = [int]$HTTP_Response.StatusCode
              If ($HTTP_Status -eq 200) 
              {
                  $hostedVersion = "4.0.999999"
                  $hostedVersions += $hostedVersion
              }
          }
          catch {}
          for ($major=0; $major -le 1; $major++)
          {
              if ($null -ne $hostedVersion)
              {
                  break
              }
              for ($minor=0; $minor -le 9; $minor++)
              {
                  $HTTP_Request = [System.Net.WebRequest]::Create("https://$($targetAddress)/download/purestorage-vsphere-plugin.zip?version=3.$($major).$($minor)")
                  try {
                      $HTTP_Response = $null
                      $HTTP_Request.Timeout = 500
                      $HTTP_Response = $HTTP_Request.GetResponse() 
                      $HTTP_Status = [int]$HTTP_Response.StatusCode
                      If ($HTTP_Status -eq 200) 
                      {
                          $hostedVersion = "3.$($major).$($minor)"
                          $hostedVersions += $hostedVersion
                          break
                      }
                  }
                  catch {}
              }
          }
      }
  }
  $plugins =@()
  $arrays = 0
  foreach ($plugin in $hostedVersions)
  {
    $Result = $null
    $Result = "" | Select-Object Source,Type,Version
    $Result.Source = $targetAddresses[$arrays]
    $Result.Version = $plugin
    if ($plugin.split(".")[0] -ge 4)
    {
      $Result.Type = "HTML-5"
    }
    else {
      $Result.Type = "Flash"
    }
    $arrays++
    $plugins += $Result
  }
  try {
    $flashS3tag = Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/Flex/purestorage-vsphere-plugin.zip?tagging"
    $Result = $null
    $Result = "" | Select-Object Source,Type,Version
    $Result.Source = "Pure1"
    $Result.Version = $flashS3tag.Tagging.TagSet.Tag.Value
    $Result.Type = "Flash"
    $plugins += $Result
    $htmlS3tag = Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5/purestorage-vsphere-plugin.zip?tagging"
    $Result = $null
    $Result = "" | Select-Object Source,Type,Version
    $Result.Source = "Pure1"
    $Result.Version = $htmlS3tag.Tagging.TagSet.Tag.Value
    $Result.Type = "HTML-5"
    $plugins += $Result
  }
  catch {}
  if (($html -eq $True) -and ($flash -eq $false))
  {
      $plugins = $plugins |Where-Object {$_.Type -eq "HTML-5"}
  }
  elseif (($html -eq $false) -and ($flash -eq $true)) 
  {
      $plugins = $plugins |Where-Object {$_.Type -eq "Flash"}
  }
  if ($version -ne "")
  {
    $plugins = $plugins |Where-Object {$_.Version -eq $version}
  }
  return $plugins
}

#aliases to not break compatibility with original cmdlet names
New-Alias -Name New-pureflasharrayRestSession -Value New-PfaRestSession
New-Alias -Name remove-pureflasharrayRestSession -Value remove-PfaRestSession
New-Alias -Name New-faHostFromVmHost -Value New-PfaHostFromVmHost
New-Alias -Name Get-faHostFromVmHost -Value Get-PfaHostFromVmHost
New-Alias -Name Get-faHostGroupfromVcCluster -Value Get-PfaHostGroupfromVcCluster 
New-Alias -Name New-faHostGroupfromVcCluster -Value New-PfaHostGroupfromVcCluster
New-Alias -Name Set-vmHostPureFaiSCSI -Value Set-vmHostPfaiSCSI
New-Alias -Name Set-clusterPureFAiSCSI -Value Set-clusterPfaiSCSI


#### helper functions
function checkDefaultFlashArray{
    if ($null -eq $Global:DefaultFlashArray)
    {
        throw "You must pass in a FlashArray connection or create a default FlashArray connection with New-Pfaconnection"
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
      throw "Please either pass in one or more FlashArray connections or create connections via the New-PfaConnection cmdlet."
  }
}
Function Get-SSLThumbprint {
  param(
  [Parameter(
      Position=0,
      Mandatory=$true,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$true)
  ]
  [Alias('FullName')]
  [String]$URL
  )

add-type @"
      using System.Net;
      using System.Security.Cryptography.X509Certificates;
          public class IDontCarePolicy : ICertificatePolicy {
          public IDontCarePolicy() {}
          public bool CheckValidationResult(
              ServicePoint sPoint, X509Certificate cert,
              WebRequest wRequest, int certProb) {
              return true;
          }
      }
"@
  [System.Net.ServicePointManager]::CertificatePolicy = New-object IDontCarePolicy

  # Need to connect using simple GET operation for this to work
  Invoke-RestMethod -Uri $URL -Method Get | Out-Null

  $ENDPOINT_REQUEST = [System.Net.Webrequest]::Create("$URL")
  $SSL_THUMBPRINT = $ENDPOINT_REQUEST.ServicePoint.Certificate.GetCertHashString()

  return $SSL_THUMBPRINT -replace '(..(?!$))','$1:'
}

