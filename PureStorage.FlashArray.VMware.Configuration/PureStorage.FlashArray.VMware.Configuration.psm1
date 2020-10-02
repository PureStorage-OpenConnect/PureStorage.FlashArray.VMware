$ErrorActionPreference = 'Stop'
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
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/24/2020
    Purpose/Change: Core support
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
    
    Connects to a FlashArray and stores it as the default connection in $Global:DefaultFlashArray and in $Global:AllFlashArrays
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nonDefaultArray
    
    Connects to a FlashArray and stores it as the default connection only in $Global:AllFlashArrays
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nonDefaultArray -ignoreCertificateError
    
    Connects to a FlashArray and stores it as the default connection only in $Global:AllFlashArrays and ignores certificate errors.

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
      [string]$Endpoint,

      [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
      [System.Management.Automation.PSCredential]$Credentials,

      [Parameter(ParameterSetName='Primary',Mandatory = $true)]
      [switch]$DefaultArray,

      [Parameter(ParameterSetName='Non-Primary',Mandatory = $true)]
      [switch]$NonDefaultArray,

      [Parameter(Position=3)]
      [switch]$IgnoreCertificateError
  )
  Begin {
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
    Will return all FlashArray-based datastores, either VMFS or vVols, and if specified just for a particular FlashArray connection.
  .INPUTS
    A FlashArray connection, a cluster or VMhost, and filter of vVol or VMFS. All optional.
  .OUTPUTS
    Returns the relevant datastores.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/24/2020
    Purpose/Change: Core support
  .EXAMPLE
    PS C:\ Get-PfaDatastores 
    
    Returns all of the FlashArray datastores for the whole connected vCenter
  .EXAMPLE
    PS C:\ Get-PfaDatastores -vvol
    
    Returns all of the FlashArray vVol datastores for the whole connected vCenter
  .EXAMPLE
    PS C:\ Get-PfaDatastores -vvol -cluster (get-cluster Infrastructure)
    
    Returns all of the FlashArray vVol datastores for the specified VMware cluster
  .EXAMPLE
    PS C:\ Get-PfaDatastores -vmfs
    
    Returns all of the FlashArray VMFS datastores for the whole connected vCenter
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
    PS C:\ Get-PfaDatastores -flasharray $fa
    
    Returns all of the datastores hosted on a particular FlashArray for the whole connected vCenter
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
    PS C:\ Get-PfaDatastores -vmfs -flasharray $fa
    
    Returns all of the VMFS datastores hosted on a particular FlashArray for the whole connected vCenter
  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  [CmdletBinding(DefaultParameterSetName="All")]
  Param(

      [Parameter(ParameterSetName='Cluster',Position=0,ValueFromPipeline=$True)]
      [Parameter(ParameterSetName='Host',Position=0,ValueFromPipeline=$True)]
      [Parameter(ParameterSetName='All',Position=0,ValueFromPipeline=$True)]
      [PurePowerShell.PureArray]$Flasharray,
    
      [Parameter(ParameterSetName='Cluster',Position=1)]
      [Parameter(ParameterSetName='Host',Position=1)]
      [Parameter(ParameterSetName='All',Position=1)]
      [switch]$Vvol,

      [Parameter(ParameterSetName='Cluster',Position=2)]
      [Parameter(ParameterSetName='Host',Position=2)]
      [Parameter(ParameterSetName='All',Position=2)]
      [switch]$Vmfs,

      [Parameter(ParameterSetName='Cluster',ValueFromPipeline=$True)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,
      
      [Parameter(ParameterSetName='Host',ValueFromPipeline=$True)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$Esxi
  )
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
      $arrayID = (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
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
  Takes in a vVol or VMFS datastore, one or more FlashArray connections and returns the correct connection.
.DESCRIPTION
  Will iterate through any connections stored in $Global:AllFlashArrays or whatever is passed in directly.
.INPUTS
  A datastore and one or more FlashArray connections
.OUTPUTS
  Returns the correct FlashArray connection.
.NOTES
  Version:        2.0
  Author:         Cody Hosterman https://codyhosterman.com
  Creation Date:  08/24/2020
  Purpose/Change: Core support
.EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
    PS C:\ New-PfaConnection -endpoint flasharray-x70-1 -credentials $faCreds -nondefaultArray
    PS C:\ New-PfaConnection -endpoint flasharray-x70-2 -credentials $faCreds -nondefaultArray
    PS C:\ $ds = get-datastore MyDatastore
    PS C:\ Get-PfaConnectionOfDatastore -datastore $ds
    
    Returns the connection of the FlashArray that hosts the specified datastore
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
  [PurePowerShell.PureArray[]]$Flasharrays,

  [Parameter(Position=1,mandatory=$true,ValueFromPipeline=$True)]
  [ValidateScript({
    if (($_.Type -ne 'VMFS') -and ($_.Type -ne 'VVOL'))
    {
        throw "The entered datastore is not a VMFS or vVol datastore. It is type $($_.Type). Please only enter a VMFS or vVol datastore"
    }
    else {
      $true
    }
  })]
  [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$Datastore
)
  if ($null -eq $flasharrays)
  {
      $flasharrays = getAllFlashArrays 
  }
  if ($flasharrays.count -eq 0)
  {
      throw "Cannot find any FlashArray connections. Please authenticate your FlashArrays." 
  }
  if ($datastore.Type -eq 'VMFS')
  {
      $lun = $datastore.ExtensionData.Info.Vmfs.Extent.DiskName |select-object -unique
      if ($lun -like 'naa.624a9370*')
      { 
          $volserial = ($lun.ToUpper()).substring(12)
          foreach ($flasharray in $flasharrays)
          { 
              $pureVolumes = New-PfaRestOperation -resourceType volume -restOperationType GET -flasharray $flasharray -SkipCertificateCheck
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
          $arraySerial = (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
          if ($arraySerial -eq $datastoreArraySerial)
          {
              $Global:CurrentFlashArray = $flasharray
              return $flasharray
          }
      }
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
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/24/2020
    Purpose/Change: Core support
  .EXAMPLE
    PS C:\ $faCreds = get-credential
    PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
    PS C:\ New-PfaConnection -endpoint flasharray-x70-1 -credentials $faCreds -nondefaultArray
    PS C:\ New-PfaConnection -endpoint flasharray-x70-2 -credentials $faCreds -nondefaultArray
    PS C:\ $arrayID = "7b5ecbdc-9241-42cc-8648-95e4f6d311c6"
    PS C:\ Get-PfaConnectionFromArrayId -arrayId $arrayID
    
    Returns the connection of the FlashArray of the specified FlashArray serial number
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
      [PurePowerShell.PureArray[]]$Flasharrays,

      [Parameter(Position=1,mandatory=$true)]
      [string]$ArrayId
  )
  if ($null -eq $flasharrays)
  {
      $flasharrays = getAllFlashArrays 
  }
  foreach ($flasharray in $flasharrays)
  {
      $returnedID = (New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $flasharray -SkipCertificateCheck).id
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $restSession = New-PfaRestSession -flasharray $fa 
      
      Creates a direct REST session to the FlashArray for REST operations that are not supported by the PowerShell SDK yet. Returns it and also stores it in $global:faRestSession
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
    #Connect to FlashArray
    if ($null -eq $flasharray)
    {
        $flasharray = checkDefaultFlashArray
    }
    if ($PSEdition -ne 'Core'){
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
  }
  else {
    $SessionAction = @{
      api_token = $flasharray.ApiToken
  }
    Invoke-RestMethod -Method Post -Uri "https://$($flasharray.Endpoint)/api/$($flasharray.apiversion)/auth/session" -Body $SessionAction -SessionVariable Session -ErrorAction Sto -SkipCertificateCheck |Out-Null
  }
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $restSession | Remove-PfaRestSession -flasharray $fa 
      
      Disconnects a direct REST session to a FlashArray. Does not disconnect the PowerShell session.
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
            [Microsoft.PowerShell.Commands.WebRequestSession]$FaSession,

            [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
            [PurePowerShell.PureArray]$Flasharray
    )
      if ($null -eq $flasharray)
      {
          $flasharray = checkDefaultFlashArray
      }
      $purevip = $flasharray.endpoint
      $apiVersion = $flasharray.ApiVersion
      #Delete FA session
      if ($PSVersionTable.PSEdition -ne "Core")
      {
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
          Invoke-RestMethod -Method Delete -Uri "https://${purevip}/api/${apiVersion}/auth/session"  -WebSession $faSession -ErrorAction Stop |Out-Null
      }
      else {
        Invoke-RestMethod -Method Delete -Uri "https://${purevip}/api/${apiVersion}/auth/session"  -WebSession $faSession -ErrorAction Stop -SkipCertificateCheck |Out-Null
      }
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ new-pfahostfromVmhost -esxi $esxi -iscsi

      Creates a new iSCSI host object on the default FlashArray connection from the specified ESXi host 
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ new-pfahostfromVmhost -esxi $esxi -fc

      Creates a new Fibre Channel host object on the default FlashArray connection from the specified ESXi host 
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ New-PfaConnection -endpoint flasharray-x50-2 -credentials $faCreds -nonDefaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ new-pfahostfromVmhost -esxi $esxi -iscsi -flasharray $Global:AllFlashArrays

      Creates a new iSCSI host object on all of the connected FlashArrays from the specified ESXi host 
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
            [Parameter(ParameterSetName='iSCSI',Position=0,mandatory=$true)]
            [Parameter(ParameterSetName='FC',Position=0,mandatory=$true)]
            [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$Esxi,

            [Parameter(ParameterSetName='iSCSI',Position=1,ValueFromPipeline=$True)]
            [Parameter(ParameterSetName='FC',Position=1,ValueFromPipeline=$True)]
            [PurePowerShell.PureArray[]]$Flasharray,

            [Parameter(ParameterSetName='iSCSI',mandatory=$true)]
            [switch]$Iscsi,

            [Parameter(ParameterSetName='FC',mandatory=$true)]
            [switch]$Fc
    )
    Begin {
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
            try {
              $newFaHost = $null
              $newFaHost = Get-PfaHostFromVmHost -flasharray $fa -esxi $esxi -ErrorAction Stop
              $vmHosts += $newFaHost
            }
            catch {}
            if ($null -eq $newFaHost)
            {
                if ($iscsi -eq $true)
                {
                    set-vmHostPfaiSCSI -esxi $esxi -flasharray $fa  -ErrorAction Stop|Out-Null
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
                        if ($iqn.count -gt 1)
                        {
                          $iqnJson = $iqn |ConvertTo-Json
                        }
                        else {
                          $iqnJson = ("[" + ($iqn |ConvertTo-Json) + "]")
                        }
                        Write-debug $iqnJson
                        $newFaHost = New-PfaRestOperation -resourceType host/$($esxi.NetworkInfo.HostName) -restOperationType POST -flasharray $fa -SkipCertificateCheck -jsonBody "{`"iqnlist`":$($iqnJson)}" -ErrorAction Stop
                        $majorVersion = ((New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $fa -SkipCertificateCheck).version[0])
                        if ($majorVersion -ge 5)
                        {
                          New-PfaRestOperation -resourceType host/$($newFaHost.name) -restOperationType PUT -flasharray $fa -SkipCertificateCheck -jsonBody "{`"personality`":`"esxi`"}" |Out-Null
                        }
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
                      if ($wwns.count -gt 1)
                      {
                        $wwnsJson = $wwns |ConvertTo-Json
                      }
                      else {
                        $wwnsJson = ("[" + ($wwns |ConvertTo-Json) + "]")
                      }
                      Write-debug $wwnsJson
                      $newFaHost = New-PfaRestOperation -resourceType host/$($esxi.NetworkInfo.HostName) -restOperationType POST -flasharray $fa -SkipCertificateCheck -jsonBody "{`"wwnlist`":$($wwnsJson)}" -ErrorAction Stop
                      $majorVersion = ((New-PfaRestOperation -resourceType array -restOperationType GET -flasharray $fa -SkipCertificateCheck).version[0])
                      if ($majorVersion -ge 5)
                      {
                        New-PfaRestOperation -resourceType host/$($newFaHost.name) -restOperationType PUT -flasharray $fa -SkipCertificateCheck -jsonBody "{`"personality`":`"esxi`"}" |Out-Null
                      }
                      $vmHosts += $newFaHost
                      $Global:CurrentFlashArray = $fa
                    }
                    catch
                    {
                        Write-Error $Global:Error[0]
                    }
                }
            }
            else {
              if ($true -eq $iscsi)
              {
                if ($newFaHost.wwn.count -gt 0)
                {
                  throw "The host $($esxi.NetworkInfo.HostName) is already configured on array $($fa.endpoint) with FibreChannel. Multiple-protocols at once are not supported by VMware."
                }
              }
              elseif ($true -eq $fc) 
              {
                if ($newFaHost.iqn.count -gt 0)
                {
                  throw "The host $($esxi.NetworkInfo.HostName) is already configured on array $($fa.endpoint) with iSCSI. Multiple-protocols at once are not supported by VMware."
                }
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ get-pfahostfromVmhost -esxi $esxi 

      Returns the host object from the default FlashArray connection from the specified ESXi host 
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nonDefaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ get-pfahostfromVmhost -esxi $esxi -flasharray $fa

      Returns the host object from the specified FlashArray connection from the specified ESXi host 
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$Esxi,

        [Parameter(Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$Flasharray
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
    $fahosts = New-PfaRestOperation -resourceType host -restOperationType GET -flasharray $flasharray -SkipCertificateCheck -ErrorAction Stop
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ get-PfaHostGroupfromVcCluster -cluster $cluster

      Returns the host group object from the default FlashArray for the specified VMware ESXi cluster.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nonDefaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ get-PfaHostGroupfromVcCluster -cluster $cluster -flasharray $fa

      Returns the host group object from the specified FlashArray for the specified VMware ESXi cluster.
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,

        [Parameter(Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray]$Flasharray
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
                    $faHostGroup = New-PfaRestOperation -resourceType "hgroup/$($faHost.hgroup)" -restOperationType GET -flasharray $flasharray -SkipCertificateCheck  -ErrorAction stop
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ new-PfaHostGroupfromVcCluster -cluster $cluster -iscsi

      Creates a host group and iSCSI-based hosts for each ESXi server on the default FlashArray for the specified VMware ESXi cluster.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ new-PfaHostGroupfromVcCluster -cluster $cluster -fc

      Creates a host group and Fibre Channel-based hosts for each ESXi server on the default FlashArray for the specified VMware ESXi cluster.
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -nonDefaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ new-PfaHostGroupfromVcCluster -cluster $cluster -fc -flasharray $fa

      Creates a host group and Fibre Channel-based hosts for each ESXi server on the specified FlashArray for the specified VMware ESXi cluster.
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
        [Parameter(ParameterSetName='iSCSI',Position=0,mandatory=$true)]
        [Parameter(ParameterSetName='FC',Position=0,mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,

        [Parameter(ParameterSetName='iSCSI',Position=1,ValueFromPipeline=$True)]
        [Parameter(ParameterSetName='FC',Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray[]]$Flasharray,

        [Parameter(ParameterSetName='iSCSI',mandatory=$true)]
        [switch]$Iscsi,

        [Parameter(ParameterSetName='FC',mandatory=$true)]
        [switch]$Fc
    )
    Begin {
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
                  if ($null -ne $faHost.hgroup)
                  {
                      if ($null -ne $hostGroup)
                      {
                          if ($hostGroup.name -ne $faHost.hgroup)
                          {
                            throw "The host $($faHost.name) already exists and is already in the host group $($faHost.hgroup). Ending workflow."
                          }
                      }
                  }
                }
                catch {}
                if ($null -ne $faHost)
                {
                  if ($iscsi -eq $true)
                  {
                    if ($fahost.wwn.count -ge 1)
                    {
                      throw "The host $($esxiHost.NetworkInfo.HostName) is already configured on the FlashArray for FC. Mixed mode is not supported by VMware."
                    }
                  }
                  else {
                    if ($fahost.iqn.count -ge 1)
                    {
                      throw "The host $($esxiHost.NetworkInfo.HostName) is already configured on the FlashArray for iSCSI. Mixed mode is not supported by VMware."
                    }
                  }
                }
                if ($null -eq $faHost)
                {
                    try {
                        if ($iscsi -eq $true)
                        {
                          $faHost = New-PfaHostFromVmHost -flasharray $fa -iscsi:$iscsi -ErrorAction Stop -esxi $esxiHost
                        }
                        else {
                          $faHost = New-PfaHostFromVmHost -flasharray $fa -fc:$fc -ErrorAction Stop -esxi $esxiHost
                        }
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
                $hg = $null
                $hg = New-PfaRestOperation -resourceType "hgroup/$($clustername)" -restOperationType GET -flasharray $fa -SkipCertificateCheck -ErrorAction SilentlyContinue
                if ($null -ne $hg)
                {
                    if ($hg.hosts.count -ne 0)
                    {
                        #if host group name is already in use and has only unexpected hosts i will create a new one with a random number at the end
                        $nameRandom = Get-random -Minimum 1000 -Maximum 9999
                        $clustername = "$($clustername)-$($nameRandom)"
                        $hostGroup = New-PfaRestOperation -resourceType "hgroup/$($clustername)" -restOperationType POST -flasharray $fa -SkipCertificateCheck  -ErrorAction stop
                        
                    }
                    else {
                      $hostGroup = $hg
                    }
                }
                else {
                      #if there is no host group, it will be created
                      $hostGroup = New-PfaRestOperation -resourceType "hgroup/$($clustername)" -restOperationType POST -flasharray $fa -SkipCertificateCheck  -ErrorAction stop
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
            if ($faHostNames.count -gt 0)
            {
              if ($faHostNames.count -gt 1)
              {
                $hostsJson = $faHostNames |ConvertTo-Json
              }
              else {
                $hostsJson = ("[" + ($faHostNames |ConvertTo-Json) + "]")
              }
              Write-debug $hostsJson
              New-PfaRestOperation -resourceType "hgroup/$($clustername)" -restOperationType PUT -flasharray $fa -jsonBody "{`"addhostlist`":$($hostsJson)}" -SkipCertificateCheck  -ErrorAction stop |Out-Null
            }
            $Global:CurrentFlashArray = $fa
            $fahostGroup = New-PfaRestOperation -resourceType "hgroup/$($clustername)" -restOperationType GET -flasharray $fa -SkipCertificateCheck  -ErrorAction stop
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ Set-VmHostPfaiSCSI -esxi $esxi 

      Configures iSCSI on an ESXi server for the default FlashArray
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ Set-VmHostPfaiSCSI -esxi $esxi -flasharray $fa

      Configures iSCSI on an ESXi server for the specified FlashArray
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ New-PfaConnection -endpoint flasharray-x50-2 -credentials $faCreds -nonDefaultArray
      PS C:\ $esxi = get-vmhost esxi-01.purecloud.com
      PS C:\ Set-VmHostPfaiSCSI -esxi $esxi -flasharray $Global:AllFlashArrays

      Configures iSCSI on an ESXi server for all of the connected FlashArrays 
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$Esxi,

        [Parameter(Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray[]]$Flasharray
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
            $faiSCSItargets = New-PfaRestOperation -resourceType network -restOperationType GET -flasharray $fa -SkipCertificateCheck |Where-Object {$_.services -eq "iscsi"} |Where-Object {$_.enabled -eq $true} | Where-Object {$null -ne $_.address}
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
      Creation Date:  08/24/2020
      Purpose/Change: Core support
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ Set-ClusterPfaiSCSI -cluster $cluster 

      Configures iSCSI on all of the ESXi servers in a cluster for the default FlashArray
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ $fa = New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ Set-ClusterPfaiSCSI -cluster $cluster -flasharray $fa

      Configures iSCSI on all of the ESXi servers in a cluster for the specified FlashArray
    .EXAMPLE
      PS C:\ $faCreds = get-credential
      PS C:\ New-PfaConnection -endpoint flasharray-m20-2 -credentials $faCreds -defaultArray
      PS C:\ New-PfaConnection -endpoint flasharray-x50-2 -credentials $faCreds -nonDefaultArray
      PS C:\ $cluster = get-cluster Infrastructure
      PS C:\ Set-ClusterPfaiSCSI -cluster $cluster -flasharray $Global:AllFlashArrays

      Configures iSCSI on all of the ESXi servers in a cluster for all of the connected FlashArrays 
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
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster,

        [Parameter(Position=1,ValueFromPipeline=$True)]
        [PurePowerShell.PureArray[]]$Flasharray
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
function New-PfaRestOperation {
  <#
  .SYNOPSIS
    Allows you to run a FlashArray REST operation that has not yet been built into this module.
  .DESCRIPTION
    Runs a REST operation to Pure1
  .INPUTS
    A filter/query, an resource, a REST body, and optionally an access token.
  .OUTPUTS
    Returns FA REST response.
  .EXAMPLE
    PS C:\ $fa = New-PfaArray -endpoint flasharray-m20-2 -credentials (get-credential) 
    PS C:\ $volName = "newVolume"
    PS C:\ New-PfaRestOperation -resourceType "volume/$($volName)" -restOperationType POST -flasharray $fa -jsonBody "{`"size`":`"1010010108)`"}" -SkipCertificateCheck 
    
    Creates a volume named newVolume and skips cert checking.
  .EXAMPLE
    PS C:\ $fa = New-PfaArray -endpoint flasharray-m20-2 -credentials (get-credential) 
    PS C:\ New-PfaRestOperation -resourceType "volume" -restOperationType GET -flasharray $fa 
    
    Returns all volumes on target array
  .EXAMPLE
    PS C:\ $fa = New-PfaArray -endpoint flasharray-m20-2 -credentials (get-credential) 
    PS C:\ New-PfaRestOperation -resourceType volume -restOperationType GET -flasharray $fa -queryFilter "?filter=serial=`'7B5ECBDC924142CC0009CB39`'"
    
    Returns the volume with the specified serial number.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/24/2020
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
      [Parameter(Position=0,mandatory=$True)]
      [string]$ResourceType,

      [Parameter(Position=1)]
      [string]$QueryFilter,

      [Parameter(Position=2)]
      [string]$JsonBody,

      [Parameter(Position=3,mandatory=$True)]
      [ValidateSet('POST','GET','DELETE','PUT','PATCH')]
      [string]$RestOperationType,

      [Parameter(ParameterSetName='REST',Position=4)]
      [Microsoft.PowerShell.Commands.WebRequestSession]$PfaSession,

      [Parameter(ParameterSetName='FlashArray',Position=5,ValueFromPipeline=$True)]
      [PurePowerShell.PureArray]$Flasharray,

      [Parameter(ParameterSetName='REST',Position=6)]
      [string]$Url,

      [Parameter(Position=7)]
      [switch]$SkipCertificateCheck,

      [Parameter(ParameterSetName='REST',Position=8)]
      [string]$PfaRestVersion
  )
    if ($null -ne $flasharray)
    {
      $pfaSession = new-PfaRestSession -flasharray $flasharray
      $url = $flasharray.EndPoint
      $pfaRestVersion = $flasharray.ApiVersion
    }
    else 
    {
      if ([string]::IsNullOrWhiteSpace($pfaRestVersion))
      {
        if ($PSVersionTable.PSEdition -ne "Core")
        {
          if ($SkipCertificateCheck -eq $True)
          {
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
            $versions = ((Invoke-WebRequest -Uri https://$($url)/api/api_version).Content |ConvertFrom-Json).version |where-object {$_ -notlike "2.*"}
          }
        }
        else {
          $versions = ((Invoke-WebRequest -Uri https://$($url)/api/api_version -SkipCertificateCheck).Content |ConvertFrom-Json).version |where-object {$_ -notlike "2.*"}
        }
        $pfaRestVersion = $versions[$versions.count-1]
      }
    }
    $apiendpoint = "https://$($url)/api/$($pfaRestVersion)/" + $resourceType + $queryFilter
    Write-debug $apiendpoint
    if ($PSVersionTable.PSEdition -eq "Core")
    {
      if ($jsonBody -ne "")
      {
          $pfaResponse = Invoke-RestMethod -Method $restOperationType -Uri $apiendpoint -ContentType "application/json" -WebSession $pfaSession -SkipCertificateCheck:$SkipCertificateCheck  -Body $jsonBody -ErrorAction Stop
      }
      else 
      {
          $pfaResponse = Invoke-RestMethod -Method $restOperationType -Uri $apiendpoint -ContentType "application/json" -WebSession $pfaSession -SkipCertificateCheck:$SkipCertificateCheck  -ErrorAction Stop
      }
    }
    else {
        if ($jsonBody -ne "")
        {
            $pfaResponse = Invoke-RestMethod -Method $restOperationType -Uri $apiendpoint -ContentType "application/json" -WebSession $pfaSession -Body $jsonBody -ErrorAction Stop
        }
        else 
        {
            $pfaResponse = Invoke-RestMethod -Method $restOperationType -Uri $apiendpoint -ContentType "application/json" -WebSession $pfaSession -ErrorAction Stop
        }
    }
    if ($null -ne $flasharray)
    {
      Remove-PfaRestSession -faSession $pfaSession -flasharray $flasharray|Out-Null
    }
    return $pfaResponse
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

