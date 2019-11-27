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
  if ($null -eq $global:defaultviserver)
  {
    throw "There is no PowerCLI connection to a vCenter, please connect first with connect-viserver."
  }
  if (($null -ne $flasharray) -and ($source -ne ""))
  {
      throw "You cannot pass in both a source and a FlashArray connection. One or the other, or neither (defaults to Pure1)"
  }
  if ($null -ne $flasharray)
  {
      $noPureOne = $true
  }
  elseif (($source -ne "") -and ($source -ne "Pure1"))
  {
      $noPureOne = $true
  }
  else {
    $noPureOne = $false
  }
  $vCenterVersion = ($global:DefaultVIServer | Select-Object Version).version
  if ($vCenterVersion.split(".")[0] -eq 5)
  {
    throw "This cmdlet does not support vCenter 5.x"
  }
  $ErrorActionPreference = "Stop"
  if (($version -ne "") -and (($version -match '[0-9]+\.[0-9]+\.[0-9]+$') -eq $false))
  {
    throw "Invalid version syntax. Please enter it in the form of x.x.x like 4.0.0 or 3.1.12"
  }
  if (($html -eq $true) -and ($flash -eq $true))
  {
    throw "Please only use the -html switch, or the -flash switch. Not both."
  }
  if (($version -match '3\.[0-9]+\.[0-9]+$'))
  {
    $flash = $true
    if ($html -eq $true)
    {
      throw "The specified version $($version) is not a valid version for the HTML plugin. Must be 4.x.x or higher."
    }
  }
  if (($version -match '4\.[0-9]+\.[0-9]+$'))
  {
    $html = $true
    if ($flash -eq $true)
    {
      throw "The specified version $($version) is not a valid version for the flash plugin. Must be 3.x.x or lower."
    }
  }
  $bothFalse = $false
  if (($html -eq $false) -and ($flash -eq $false))
  {
    if (($vCenterVersion.split(".")[1] -eq 0) -and ($vCenterVersion.split(".")[0] -eq 6))
    {
      $flash = $true
    }
    else {
      $html = $true
      $bothFalse = $true
    }
  }
  if ($html -eq $true)
  {
    if (($vCenterVersion.split(".")[1] -eq 0) -and ($vCenterVersion.split(".")[0] -eq 6))
    {
      throw "The specified version of the plugin (HTML) does not support vCenter 6.0. 6.5 and later only."
    }
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
  if ($bothFalse -eq $false)
  {
    if ($source -eq "Pure1")
    {
      $hostedVersion = Get-PfavSpherePlugin -html:$html -flash:$flash -version $version
    }
    else 
    {
      $hostedVersion = Get-PfavSpherePlugin -html:$html -flash:$flash -version $version -source $ipAddress
    }
  }
  else {
    if ($source -eq "Pure1")
    {
      $hostedVersion = Get-PfavSpherePlugin -html:$html -flash:$flash -version $version
    }
    else 
    {
      $hostedVersion = Get-PfavSpherePlugin -version $version -source $ipAddress
    }
  }
  if ($null -eq $hostedVersion)
  {
    throw "Specified plugin type or version not found on available source"
  }
  if ($noPureOne -eq $true)
  {
    $hostedVersion = ($hostedVersion |Where-Object {$_.Source -ne "Pure1"}).version
  }
  else {
    $hostedVersion = $hostedVersion.version
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
  $extensionSpec.LastHeartbeatTime = get-date

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
    Version:        1.1
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  07/27/2019
    Purpose/Change: Bug fix for specifying Pure1 as source

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
    if ($ipTarget -eq "Pure1")
    {
      continue 
    }
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
  $identifiedArrays = @()
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    $hostedVersions = @()
    foreach ($targetAddress in $targetAddresses)
    {
        $hostedVersion = $null
        if ([string]::IsNullOrWhiteSpace($version))
        {
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
                            $identifiedArrays += $targetAddress
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
                        $identifiedArrays += $targetAddress
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
                                $identifiedArrays += $targetAddress
                                break
                            }
                        }
                        catch {}
                    }
                }
            }
        }
        else 
        {
            $HTTP_Request = [System.Net.WebRequest]::Create("https://$($targetAddress)/download/purestorage-vsphere-plugin.zip?version=$($version)")
            try {
                $HTTP_Response = $null
                $HTTP_Request.Timeout = 500
                $HTTP_Response = $HTTP_Request.GetResponse() 
                $HTTP_Status = [int]$HTTP_Response.StatusCode
                If ($HTTP_Status -eq 200) 
                {
                    $hostedVersion = $version
                    $hostedVersions += $hostedVersion
                    $identifiedArrays += $targetAddress
                }
            }
            catch {}
        }
    }
    $plugins =@()
    $arrays = 0
    foreach ($plugin in $hostedVersions)
    {
      $Result = $null
      $Result = "" | Select-Object Source,Type,Version
      $Result.Source = $identifiedArrays[$arrays]
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

function Deploy-PfaAppliance {
  <#
  .SYNOPSIS
    Deploys the Pure Storage OVA for off-array integrations and applications.
  .DESCRIPTION
    Deploys the Pure Storage OVA for off-array integrations and applications.
  .INPUTS
    An authorization key, DHCP info, IP info.
  .OUTPUTS
    Returns the Pure Storage Collector Object.
  .EXAMPLE
    PS C:\ $ds = get-datastore <datastore name>
    PS C:\ $esxi = Get-VMHost <ESXi host name>
    PS C:\ $pg = (Get-VirtualPortGroup -vmhost $esxi)[0]
    PS C:\ $vmname = <desired name of appliance VM>
    PS C:\ $authKey = <collector key from Pure1>
    PS C:\ $mycreds = get-credential
    PS C:\ Deploy-PfaAppliance -vmName $vmName -authorizationKey $authkey -datastore $ds -portGroup $pg -vmHost $esxi -dhcp -ovaPassword $mycreds.Password
    
    Deploys a new OVA with DHCP network configuration. This will also change the default password to the supplied password.
    .EXAMPLE
    PS C:\ $ds = get-datastore <datastore name>
    PS C:\ $esxi = Get-VMHost <ESXi host name>
    PS C:\ $pg = (Get-VirtualPortGroup -vmhost $esxi)[0]
    PS C:\ $vmname = <desired name of appliance VM>
    PS C:\ $authKey = <collector key from Pure1>
    PS C:\ Deploy-PfaAppliance -vmName $vmName -authorizationKey $authkey -datastore $ds -portGroup $pg -vmHost $esxi -dhcp
    
    Deploys a new OVA with DHCP network configuration. This will leave the default password as is. You must change it manually before using the collector.
  .EXAMPLE
    PS C:\ $ds = get-datastore <datastore name>
    PS C:\ $esxi = Get-VMHost <ESXi host name>
    PS C:\ $pg = (Get-VirtualPortGroup -vmhost $esxi)[0]
    PS C:\ $vmname = <desired name of appliance VM>
    PS C:\ $authKey = <collector key from Pure1>
    PS C:\ $mycreds = get-credential
    PS C:\ Deploy-PfaAppliance -vmName $vmName -authorizationKey $authkey -datastore $ds -portGroup $pg -vmHost $esxi -ovaPassword $mycreds.Password -ipaddress <IP> -netmask <netmask> -gateway <gateway> -dnsprimary <DNS> -hostname <FQDN>
    
    Deploys a new OVA with static network configuration. This will also change the default password to the supplied password.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  11/26/2019
    Purpose/Change: New cmdlet

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
      [string]$vmName,

      [Parameter(Position=1,ValueFromPipeline=$True)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$vmHost,

      [Parameter(Position=2)]
      [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

      [Parameter(Position=3)]
      [VMware.VimAutomation.ViCore.Types.V1.Host.Networking.VirtualPortGroupBase]$portGroup,

      [Parameter(Position=4)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

      [Parameter(Position=5)]
      [switch]$dhcp,

      [Parameter(Position=6,mandatory=$true)]
      [string]$authorizationKey,

      [Parameter(Position=7)]
      [string]$ipAddress,

      [Parameter(Position=8)]
      [string]$netmask,

      [Parameter(Position=9)]
      [string]$gateway,

      [Parameter(Position=10)]
      [string]$dnsPrimary,

      [Parameter(Position=11)]
      [string]$dnsSecondary,

      [Parameter(Position=12)]
      [string]$hostName,

      [Parameter(Position=13)]
      [string]$ovaLocation,

      [Parameter(Position=14)]
      [SecureString]$ovaPassword,

      [Parameter(Position=15)]
      [int32]$passwordChangeWait = 60,

      [Parameter(Position=16)]
      [switch]$silent
  )
  $ErrorActionPreference = "stop"
  if ($null -eq $portGroup)
  {
    throw "Please pass in a virtual port group with get-virtualportgroup"
  }
  if ($null -eq $datastore)
  {
    throw "Please pass in a datastore with get-datastore"
  }
  try
  {
    $foundVM = get-vm $vmName
  }
  catch  {}
  if ($null -ne $foundVM)
  {
    throw "A VM with the name $($vmName) already exists. Please specify a unique name."
  }
  if ($dhcp -eq $false)
    {
      if ([string]::IsNullOrEmpty($ipAddress))
      {
        throw "If you do not specify DHCP, you must enter an IP address."
      }
      if ([string]::IsNullOrEmpty($netmask))
      {
        throw "If you do not specify DHCP, you must enter a netmask"
      }
      if ([string]::IsNullOrEmpty($gateway))
      {
        throw "If you do not specify DHCP, you must enter a gateway"
      }
      if ([string]::IsNullOrEmpty($dnsPrimary))
      {
        throw "If you do not specify DHCP, you must enter at least one DNS server IP"
      }
      if ([string]::IsNullOrEmpty($hostName))
      {
        throw "If you do not specify DHCP, you must enter a fully-qualified domain name."
      }
    }
    if ([string]::IsNullOrEmpty($authorizationKey))
    {
      throw "You must pass in an authorization key. This can be acquired from Pure1.purestorage.com by your Pure1 organization admin(s)."
    }
    if (($null -eq $cluster) -and ($null -eq $vmHost))
    {
      throw "Please pass in a vSphere cluster or a specific ESXi host."
    }
    elseif ($null -eq $vmhost)
    {
        $vmHost = $cluster | get-vmhost | where-object {($_.version -like '5.5.*') -or ($_.version -like '6.*')}| where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1
    }
    if (($null -eq $ovaLocation)-or ($ovaLocation -eq ""))
    {
      if ($silent -ne $true)
      {
          write-host ""
          write-host "Downloading OVA to $($env:temp)\purestorage-vma-collector_latest-signed.ova..."
      }
      $ProgressPreference = 'SilentlyContinue'
      if ([System.IO.File]::Exists($ovaLocation))
      {
        throw "There is already an OVA at the default location. Ensure file at $($ovaLocation) is correct and directly specify it or delete it so it can be re-downloaded with the latest version."
      }
      Invoke-WebRequest -Uri "https://static.pure1.purestorage.com/vm-analytics-collector/purestorage-vma-collector_latest-signed.ova" -OutFile $env:temp\purestorage-vma-collector_latest-signed.ova
      $ovaLocation = "$($env:temp)\purestorage-vma-collector_latest-signed.ova"
      $deleteOVA = $true
      if ($silent -ne $true)
      {
        write-host "Download complete."
      } 
    }
    else {
      $deleteOVA = $false
      if (![System.IO.File]::Exists($ovaLocation))
      {
        throw "Could not find OVA file. Ensure file location $($ovaLocation) is correct/accessible."
      }
    }
    try 
    {
      $ovaConfig = Get-OvfConfiguration $ovaLocation
      if ($dhcp -eq $true)
      {
          $ovaConfig.Common.DHCP.value = $true
      }
      else 
      {
        $ovaConfig.Common.IP_Address.value = $ipAddress
        $ovaConfig.Common.Netmask.value = $netmask
        $ovaConfig.Common.Gateway.value = $gateway
        $ovaConfig.Common.DNS_Server_1.value = $dnsPrimary
        $ovaConfig.Common.DNS_Server_2.value = $dnsSecondary
        $ovaConfig.Common.Hostname.value = $hostName
        $ovaConfig.Common.DHCP.value = $false
      }
      $ovaConfig.Common.Authorization_Key.value = $authorizationKey
      $ovaConfig.NetworkMapping.VM_Network.value = $portGroup
      if ($silent -ne $true)
      {
        write-host "Deploying OVA..."
      } 
      $vm = Import-VApp -Source $ovaLocation -OvfConfiguration $ovaConfig -Name $vmName -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force
      if ($silent -ne $true)
      {
        write-host "OVA deployed."
      } 
    }
    catch 
    {
      if ($deleteOVA -eq $true)
      {
        Remove-Item $ovaLocation
      }
      throw $Global:Error[0]
    }
  if ($deleteOVA -eq $true)
  {
      Remove-Item $ovaLocation
  }
  if ($silent -ne $true)
  {
    write-host "Powering-on VM..."
  }
  Start-VM $vm  |out-null
  if ($ovaPassword.length -ge 1)
  {
    if ($silent -ne $true)
    {
      write-host "Pureuser password specified. Waiting for VM tools be to active in order to set new password..."
    }
    while ($vm.ExtensionData.Guest.GuestState -ne "running")
    {
      $vm = get-vm $vm.name
      Start-sleep 5
    }
    if ($silent -ne $true)
    {
      write-host "Waiting for post-boot first time configuration to complete (default is 60 seconds)..."
    }
    start-sleep $passwordChangeWait
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ovaPassword)
    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    Set-PfaVMKeystrokes -VMName $vm.name -StringInput "pureuser" -ReturnCarriage $true
    Set-PfaVMKeystrokes -VMName $vm.name -StringInput "pureuser" -ReturnCarriage $true
    Set-PfaVMKeystrokes -VMName $vm.name -StringInput "pureuser" -ReturnCarriage $true
    Set-PfaVMKeystrokes -VMName $vm.name -StringInput $UnsecurePassword -ReturnCarriage $true
    Set-PfaVMKeystrokes -VMName $vm.name -StringInput $UnsecurePassword -ReturnCarriage $true
    Set-PfaVMKeystrokes -VMName $vm.name -StringInput "exit" -ReturnCarriage $true
  }
  $creds = New-Object System.Management.Automation.PSCredential ("pureuser", $ovaPassword)
  return (Get-PfaAppliance -vm $vm -applianceCredentials $creds)
}

function Get-PfaAppliance {
  <#
  .SYNOPSIS
    Returns application information in the Pure Storge OVA
  .DESCRIPTION
    Returns application information in the Pure Storage OVA (connects vCenters etc.)
  .INPUTS
    OVA VM object and credentials and request.
  .OUTPUTS
    Text response.
  .NOTES
    Version:        1.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  11/26/2019
    Purpose/Change: New cmdlet
  .EXAMPLE
    PS C:\ $vm = get-vm ovatest
    PS C:\ $creds = get-credential
    PS C:\ Get-PfaAppliance -vm $vm -applianceCredentials $creds
    
    Returns a specific Pure Storage appliance 
  .EXAMPLE
    PS C:\ $creds = get-credential
    PS C:\ Get-PfaAppliance -applianceCredentials $creds
    
    Returns all discovered Pure Storage appliances 
  .EXAMPLE
    PS C:\ $creds = get-credential
    PS C:\ $clusterVMs = get-cluster Infrastructure |get-vm
    PS C:\ Get-PfaAppliance -vm $clusterVMs -applianceCredentials $creds
    
    Returns all discovered Pure Storage appliances in a cluster named Infrastructure
  
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

      [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
      [System.Management.Automation.PSCredential]$applianceCredentials  
  )
  if ($applianceCredentials.UserName -notlike "pureuser")
  {
    do
    {
      Write-Warning -Message "The username must stay as pureuser, do not change it. Please only enter in a new password."
      $applianceCredentials = Get-Credential -Credential pureuser
    }
    while ($applianceCredentials.UserName -notlike "pureuser")
  }
  if ($null -eq $vm)
  {
    $vm = get-vm |Where-Object {$_.ExtensionData.Config.VAppConfig.Product.Vendor -eq "Pure Storage"}
  }
  elseif ($vm.count -gt 1)
  {
    $vm = $vm |Where-Object {$_.ExtensionData.Config.VAppConfig.Product.Vendor -eq "Pure Storage"}
  }
  elseif ($vm.ExtensionData.Config.VAppConfig.Product.Vendor -ne "Pure Storage")
  {
    throw "This is not a Pure Storage-supplied virtual machine."
  }
  if ($null -eq $vm)
  {
    throw "No Pure Storage appliance found."
  }
  if ($vm.count -gt 1)
  {
    $pfaAppliances = @()
    foreach ($ova in $vm)
    {
      try 
      {
        $pfaAppliances += New-Object -TypeName PureStorageCollector -ArgumentList $ova.name,$applianceCredentials -ErrorAction Stop
      }
      catch 
      {
        $errorReturnType = $Global:Error[1].Exception.GetType()
        if ($errorReturnType.name -eq "InvalidGuestLogin")
        {
          throw "Invalid credentials for VM $($ova.name)"
        }
        else {
          throw $Global:Error[1].Exception
        }
      }
    }
  }
  else 
  {
    try 
      {
        $pfaAppliances += New-Object -TypeName PureStorageCollector -ArgumentList $vm.name,$applianceCredentials -ErrorAction Stop
      }
      catch 
      {
        $errorReturnType = $Global:Error[1].Exception.GetType()
        if ($errorReturnType.name -eq "InvalidGuestLogin")
        {
          throw "Invalid credentials for VM $($vm.name)"
        }
        else {
          throw $Global:Error[1].Exception
        }
      }
  }
  return $pfaAppliances
}

##############################################Custom Classes

Class PureStorageAppliance{
  hidden [String] $_version
  hidden [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine] $_vm
  static [String] $vendor = "Pure Storage"
  static [String] $name = "Pure Storage OVA Appliance"
  hidden [String]$_vmName = $null
  hidden [String]$_feature = $null
}

Class PureStorageCollector : PureStorageAppliance{
  hidden [vCenterStatus[]] $_vCenters
  hidden [String]$_build = $null
  hidden [System.Management.Automation.PSCredential] $ovaCreds
  PureStorageCollector ([String] $_vmName, [System.Management.Automation.PSCredential] $ovaCreds)
  {
      $vm = get-vm $_vmName
      $ovaApp = Get-PfaCollectorVersion -vm $vm -applianceCredentials $ovaCreds -ErrorAction Stop
      $this._vCenters = Get-PfaCollectorvCenter -vm $vm -applianceCredentials $ovaCreds
      $this._version = $ovaApp.version
      $this._build = $ovaApp.build
      $this._feature = $ovaApp.feature
      $this.ovaCreds = $ovaCreds
      $this._vm = $vm
      $this | Add-Member -MemberType ScriptProperty -Name 'VirtualMachine' -Value {
          return $this._vm
      } -SecondValue {
          throw 'This is a ReadOnly property!'
      }
      $this | Add-Member -MemberType ScriptProperty -Name 'Build' -Value {
        return $this._build
      } -SecondValue {
          throw 'This is a ReadOnly property!'
      }
      $this | Add-Member -MemberType ScriptProperty -Name 'Feature' -Value {
        return $this._feature
      } -SecondValue {
          throw 'This is a ReadOnly property!'
      }
      $this | Add-Member -MemberType ScriptProperty -Name 'Version' -Value {
          return $this._version
      } -SecondValue {
          throw 'This is a ReadOnly property!'
      }
      $this | Add-Member -MemberType ScriptProperty -Name 'vCenters' -Value {
          return $this._vCenters
      } -SecondValue {
          throw 'This is a ReadOnly property!'
      }
  }
  [vCenterConnection] AddvCenter ([String] $vCenter,[System.Management.Automation.PSCredential] $vcenterCreds)
  {
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($vcenterCreds.Password)
    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics connect --hostname $($vcenter) --username $($vcenterCreds.username) --password $($UnsecurePassword)" -VM $this.VirtualMachine -GuestCredential $this.ovaCreds).ScriptOutput 
    if ($queryResponse -like "*Error*")
    {
      throw "Pure VM Analytics $($queryResponse)"
    }
    $queryResponse = $queryResponse |Convertfrom-string
    $addedvCenter = New-Object vCenterConnection
    $addedvCenter.Name = $queryResponse.P5
    $addedvCenter.HostName = $queryResponse.P6
    $addedvCenter.Username = $queryResponse.P7
    $this._vCenters = Get-PfaCollectorvCenter -vm $this.VirtualMachine -applianceCredentials $this.ovaCreds
    $this.PSObject.Properties.Remove('vCenters')
    $this | Add-Member -MemberType ScriptProperty -Name 'vCenters' -Value {
      return $this._vCenters
    } -SecondValue {
      throw 'This is a ReadOnly property!'
  }
    return $addedvCenter
  }
  [vCenterConnection] RemovevCenter ([String] $vCenter)
  {
    $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics disconnect $($vCenter.ToLower())" -VM $this.VirtualMachine -GuestCredential $this.ovaCreds).ScriptOutput 
    if ($queryResponse -like "*Error*")
    {
      throw "Pure VM Analytics $($queryResponse)"
    }
    $queryResponse = $queryResponse |Convertfrom-string
    $removedvCenter = New-Object vCenterConnection
    $removedvCenter.Name = $queryResponse.P5
    $removedvCenter.HostName = $queryResponse.P6
    $this._vCenters = Get-PfaCollectorvCenter -vm $this.VirtualMachine -applianceCredentials $this.ovaCreds
    $this.PSObject.Properties.Remove('vCenters')
    $this | Add-Member -MemberType ScriptProperty -Name 'vCenters' -Value {
      return $this._vCenters
    } -SecondValue {
      throw 'This is a ReadOnly property!'
    }
    return $removedvCenter |Select-Object -Property Name
  }
  RefreshvCenterStatus ()
  {
    $this._vCenters = Get-PfaCollectorvCenter -vm $this.VirtualMachine -applianceCredentials $this.ovaCreds
    $this.PSObject.Properties.Remove('vCenters')
    $this | Add-Member -MemberType ScriptProperty -Name 'vCenters' -Value {
      return $this._vCenters
    } -SecondValue {
      throw 'This is a ReadOnly property!'
    }
    return 
  }
  [vCenterStatus[]] ImportConfig ([PureStorageCollector]$sourceCollector)
  {
    Reset-VMConsole($this.VirtualMachine)
    Start-sleep 1
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.ovaCreds.Password)
    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    Set-PfaVMKeystrokes -VMName $this.VirtualMachine.name -StringInput "pureuser" -ReturnCarriage $true
    Set-PfaVMKeystrokes -VMName $this.VirtualMachine.name -StringInput $UnsecurePassword -ReturnCarriage $true
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sourceCollector.ovaCreds.Password)
    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    Set-PfaVMKeystrokes -VMName $this.VirtualMachine.name -StringInput "purevmanalytics config import --host $($sourceCollector.VirtualMachine.Guest.IPAddress[0]) --user $($sourceCollector.ovaCreds.UserName)" -ReturnCarriage $true
    Start-sleep 5
    Set-PfaVMKeystrokes -VMName $this.VirtualMachine.name -StringInput $UnsecurePassword -ReturnCarriage $true
    Start-sleep 3
    Set-PfaVMKeystrokes -VMName $this.VirtualMachine.name -StringInput "exit" -ReturnCarriage $true
    if ($sourceCollector.vCenters.Count -ge 1)
    {
      $this._vCenters = Get-PfaCollectorvCenter -vm $this.VirtualMachine -applianceCredentials $this.ovaCreds
      if ($this._vCenters.Count -lt $sourceCollector.vCenters.Count)
      {
        throw "Target collector vCenter connections import failed. Please verify authentication information."
      }
      $this.PSObject.Properties.Remove('vCenters')
      $this | Add-Member -MemberType ScriptProperty -Name 'vCenters' -Value {
        return $this._vCenters
      } -SecondValue {
        throw 'This is a ReadOnly property!'
      }
    }
    return $this._vCenters
  }
  [string] TestPhoneHome ()
  {
    $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics test pinghome" -VM $this.VirtualMachine -GuestCredential $this.ovaCreds).ScriptOutput
    if ($queryResponse -like "*Connection to the cloud was successful!*")
    {
      return $queryResponse
    }
    else {
      throw "Pure VM Analytics $($queryResponse)"
    }
  }
  [string] Stop ()
  {
    $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics stop" -VM $this.VirtualMachine -GuestCredential $this.ovaCreds).ScriptOutput 
    return $queryResponse
  }
  [string] Start ()
  {
    $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics start" -VM $this.VirtualMachine -GuestCredential $this.ovaCreds).ScriptOutput 
    return $queryResponse
  }
  [string] Restart ()
  {
    $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics restart" -VM $this.VirtualMachine -GuestCredential $this.ovaCreds).ScriptOutput 
    return $queryResponse
  }
}
Class vCenterStatus
{
    [String]$Name
    [boolean]$Enabled
    [String]$State
    [int]$Duration
    [datetime]$LastCollection
}
Class vCenterConnection
{
    [String]$Name
    [String]$HostName
    [String]$Username
}
Class applianceVersion
{
    [String]$Feature
    [String]$Version
    [String]$Build
}


#### helper functions
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
function Get-PfaCollectorvCenter {
  [CmdletBinding()]
  Param(
      [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,

      [Parameter(Position=1,ValueFromPipeline=$True,mandatory=$true)]
      [System.Management.Automation.PSCredential]$applianceCredentials  
  )
  $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics list" -VM $vm -GuestCredential $appliancecredentials).ScriptOutput |Convertfrom-string
  if ($null -eq $queryResponse)
  {
    return $null
  }
  $propertyCount = ($queryResponse | Get-Member -MemberType NoteProperty).Count
  $foundvCenters = @()
  for ($i =13;$i -lt $propertyCount; $i++)
  {
    $foundvCenter = New-Object vCenterStatus
    $foundvCenter.Name = $queryResponse.("P$($i)")
    $i++
    $foundvCenter.Enabled = $queryResponse.("P$($i)")
    $i++
    $foundvCenter.State = $queryResponse.("P$($i)")
    $i++
    if ($queryResponse.("P$($i)").GetType().Name -eq "Byte")
    {
      $foundvCenter.Duration = $queryResponse.("P$($i)")
      $i = $i + 2
      $foundvCenter.LastCollection = $queryResponse.("P$($i)")
    }
    else {
      $foundvCenter.Duration = $null
      $i++
      $foundvCenter.LastCollection = Get-Date -Date "8/05/2015 19:00:00"
    }
    $foundvCenters += $foundvCenter
  }
  return $foundvCenters 
}
function Get-PfaCollectorVersion {

  [CmdletBinding()]
  Param(
      [Parameter(Position=0,ValueFromPipeline=$True,mandatory=$true)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm,

      [Parameter(Position=2,ValueFromPipeline=$True,mandatory=$true)]
      [System.Management.Automation.PSCredential]$applianceCredentials  
  )
    $queryResponse = (Invoke-VMScript -ScriptText "purevmanalytics version" -VM $vm -GuestCredential $appliancecredentials).ScriptOutput |Convertfrom-string -Delimiter `n
    $applianceVersion = new-object applianceVersion
    $applianceVersion.Feature = $queryResponse.P1.replace(" Configuration","")
    $applianceVersion.Version = $queryResponse.P2.split(" ")[1]
    $applianceVersion.Build = $queryResponse.P3.split(" ")[1]
    return $applianceVersion
}

Function Reset-VMConsole {
  param(
        [Parameter(Mandatory=$true)][VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$vm
    )
  $hidCodesEvents = @()
  $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent
  $modifer = New-Object Vmware.Vim.UsbScanCodeSpecModifierType
  $modifer.LeftControl = $true
  $tmp.Modifiers = $modifer
  
  $hidCodeHexToInt = [Convert]::ToInt64('0x06',"16")
  $hidCodeValue = ($hidCodeHexToInt -shl 16) -bor 0007
  $tmp.UsbHidCode = $hidCodeValue
  $hidCodesEvents+=$tmp
  
  $spec = New-Object Vmware.Vim.UsbScanCodeSpec
  $spec.KeyEvents = $hidCodesEvents
  $vm.ExtensionData.PutUsbScanCodes($spec) |Out-Null
}
Function Set-PfaVMKeystrokes {
<#
    .NOTES
    ===========================================================================
     Created by:    William Lam (edited by Cody)
     Organization:  VMware
     Blog:          www.virtuallyghetto.com
     Twitter:       @lamw
    ===========================================================================
    .DESCRIPTION
        This function sends a series of character keystrokse to a particular VM
    .PARAMETER VMName
		The name of a VM to send keystrokes to
	.PARAMETER StringInput
		The string of characters to send to VM
	.PARAMETER DebugOn
		Enable debugging which will output input charcaters and their mappings
    .EXAMPLE
        Set-VMKeystrokes -VMName $VM -StringInput "root"
    .EXAMPLE
        Set-VMKeystrokes -VMName $VM -StringInput "root" -ReturnCarriage $true
#>
    param(
        [Parameter(Mandatory=$true)][String]$VMName,
        [Parameter(Mandatory=$true)][String]$StringInput,
        [Parameter(Mandatory=$false)][Boolean]$ReturnCarriage
    )

    # Map subset of USB HID keyboard scancodes
    # https://gist.github.com/MightyPork/6da26e382a7ad91b5496ee55fdc73db2
    $hidCharacterMap = @{
		"a"="0x04";
		"b"="0x05";
		"c"="0x06";
		"d"="0x07";
		"e"="0x08";
		"f"="0x09";
		"g"="0x0a";
		"h"="0x0b";
		"i"="0x0c";
		"j"="0x0d";
		"k"="0x0e";
		"l"="0x0f";
		"m"="0x10";
		"n"="0x11";
		"o"="0x12";
		"p"="0x13";
		"q"="0x14";
		"r"="0x15";
		"s"="0x16";
		"t"="0x17";
		"u"="0x18";
		"v"="0x19";
		"w"="0x1a";
		"x"="0x1b";
		"y"="0x1c";
		"z"="0x1d";
		"1"="0x1e";
		"2"="0x1f";
		"3"="0x20";
		"4"="0x21";
		"5"="0x22";
		"6"="0x23";
		"7"="0x24";
		"8"="0x25";
		"9"="0x26";
		"0"="0x27";
		"!"="0x1e";
		"@"="0x1f";
		"#"="0x20";
		"$"="0x21";
		"%"="0x22";
		"^"="0x23";
		"&"="0x24";
		"*"="0x25";
		"("="0x26";
		")"="0x27";
		"_"="0x2d";
		"+"="0x2e";
		"{"="0x2f";
		"}"="0x30";
		"|"="0x31";
		":"="0x33";
		"`""="0x34";
		"~"="0x35";
		"<"="0x36";
		">"="0x37";
		"?"="0x38";
		"-"="0x2d";
		"="="0x2e";
		"["="0x2f";
		"]"="0x30";
		"\"="0x31";
		"`;"="0x33";
		"`'"="0x34";
		","="0x36";
		"."="0x37";
		"/"="0x38";
		" "="0x2c";
    }

    $vm = Get-View -ViewType VirtualMachine -Filter @{"Name"="^$($VMName)$"}
    $hidCodesEvents = @()
    foreach($character in $StringInput.ToCharArray()) {
        # Check to see if we've mapped the character to HID code
        if($hidCharacterMap.ContainsKey([string]$character)) {
            $hidCode = $hidCharacterMap[[string]$character]

            $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent

            # Add leftShift modifer for capital letters and/or special characters
            if( ($character -cmatch "[A-Z]") -or ($character -match "[!|@|#|$|%|^|&|(|)|_|+|{|}|||:|~|<|>|?|*]") ) {
                $modifer = New-Object Vmware.Vim.UsbScanCodeSpecModifierType
                $modifer.LeftShift = $true
                $tmp.Modifiers = $modifer
            }

            # Convert to expected HID code format
            $hidCodeHexToInt = [Convert]::ToInt64($hidCode,"16")
            $hidCodeValue = ($hidCodeHexToInt -shl 16) -bor 0007

            $tmp.UsbHidCode = $hidCodeValue
            $hidCodesEvents+=$tmp

        } else {
            Write-Host "The following character `"$character`" has not been mapped, you will need to manually process this character"
            break
        }
    }

    # Add return carriage to the end of the string input (useful for logins or executing commands)
    if($ReturnCarriage) {
        # Convert return carriage to HID code format
        $hidCodeHexToInt = [Convert]::ToInt64("0x28","16")
        $hidCodeValue = ($hidCodeHexToInt -shl 16) + 7

        $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent
        $tmp.UsbHidCode = $hidCodeValue
        $hidCodesEvents+=$tmp
    }

    # Call API to send keystrokes to VM
    $spec = New-Object Vmware.Vim.UsbScanCodeSpec
    $spec.KeyEvents = $hidCodesEvents
    $results = $vm.PutUsbScanCodes($spec)
}
