function Install-PfaVspherePlugin {
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
    
    Installs the latest appropriate plugin (flash or HTML) located on Pure1 on every vCenter in $Global:DefaultViservers
  .EXAMPLE
    PS C:\ $vCenter = connect-viserver -Server myVcenter.purestorage.com
    PS C:\ Install-PfavSpherePlugin -Server $vCenter
    
    Installs the latest appropriate plugin (flash or HTML) located on Pure1 on the specified vCenter(s)
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin -confirm:$false
    
    Installs the latest appropriate plugin (flash or HTML) located on Pure1 without prompting for confirmation on every vCenter in $Global:DefaultViservers
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin -flash -version 3.1.2
    
    Installs the Flash 3.1.2 plugin located on Pure1 on every vCenter in $Global:DefaultViservers.  
  .EXAMPLE
    PS C:\ Install-PfavSpherePlugin -customSource https://myflasharray.pure.com/plugin.zip
    
    Installs the plugin that is hosted on the specified HTTPS zip source (a web server or object target) on every vCenter in $Global:DefaultViservers. 

  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/26/2020
    Purpose/Change: Multi-vCenter support.

  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High',DefaultParameterSetName='Version')]
  Param(
          [Parameter(ParameterSetName='HTML',Position=0)]
          [Parameter(ParameterSetName='Custom',Position=0)]
          [switch]$html,

          [Parameter(ParameterSetName='Flash',Position=1)]
          [Parameter(ParameterSetName='Custom',Position=1)]
          [switch]$flash,

          [ValidateScript({
            if ($_ -match '[0-9]+\.[0-9]+\.[0-9]+$')
            {
              $true
            }
            else {
              throw "The version must be in the format of x.x.x. Like 4.2.0 or 3.1.3."
            }
          })]
          [Parameter(ParameterSetName='HTML',Position=2)]
          [Parameter(ParameterSetName='Flash',Position=2)]
          [Parameter(ParameterSetName='Version',Position=2)]
          [Parameter(ParameterSetName='Custom',Position=2,mandatory=$true)]
          [string]$version,

          [ValidateScript({
            if ($_ -like "https://*.zip*")
            {
              $true
            }
            else {
              throw "The custom source must be a https URL ending with a zip file of the plugin, like https://mywebserver.pure.com/vsphereplugin.zip."
            }
          })]
          [Parameter(ParameterSetName='Custom',Position=2)]
          [string]$customSource,

          [Parameter(Position=3)]
          [VMware.VimAutomation.ViCore.Types.V1.VIServer[]]$server
      )
  if ($null -eq $server)
  {
    if ($global:defaultviservers.count -gt 0)
    {
      $vCenters = $global:defaultviservers
    }
    else {
      throw "You must connect to one or more vCenters with connect-viserver in order to install the plugin."
    }
  }
  else {
    $vCenters = $server
  }
  if (!([string]::IsNullOrWhiteSpace($customSource)))
  {
    if ($html -eq $flash)
    {
      throw "You must specify either flash or HTML, not both, and not neither."
    }
  }
  else {
    $pure1 = $true
  }
  $ErrorActionPreference = "Stop"
  foreach ($vCenter in $vCenters)
  {
    ####Check vCenter versions and plugin version compatibility
    $vCenterVersion = ($vCenter | Select-Object Version).version
    if ($vCenterVersion.split(".")[0] -eq 5)
    {
      Write-Warning "The vCenter $($vcenter.Name) is not version 6.5 or later. This cmdlet does not support vCenter $($vCenterVersion). Skipping this vCenter."
      continue
    }
    if (($html -eq $false) -and ($flash -eq $false))
    {
      if (($vCenterVersion.split(".")[1] -eq 0) -and ($vCenterVersion.split(".")[0] -eq 6))
      {
        $flash = $true
      }
      else {
        $html = $true
      }
    }
    if ($html -eq $true)
    {
      if (($vCenterVersion.split(".")[1] -eq 0) -and ($vCenterVersion.split(".")[0] -eq 6))
      {
        Write-Warning "The vCenter $($vcenter.Name) is not version 6.5 or later. This cmdlet does not support vCenter $($vCenterVersion). Skipping this vCenter."
        continue
      }
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
    #gather extension manager
    $services = Get-view 'ServiceInstance' -Server $vCenter
    $extensionMgr  = Get-view $services.Content.ExtensionManager -Server $vCenter

    #find what plugins are installed and their version
    $installedHtmlVersion = ($extensionMgr.FindExtension("com.purestorage.purestoragehtml")).version
    $installedFlashVersion = ($extensionMgr.FindExtension("com.purestorage.plugin.vsphere")).version

    #identify available plugin versions.
    if ($pure1 -eq $true)
    {
      $global:pfavSpherePluginUrl = $true
      if (!([string]::IsNullOrWhiteSpace($version)))
      {
        $fullPluginInfo = Get-PfavSpherePlugin -version $version -html:$html -flash:$flash -previous
      }
      else {
        $fullPluginInfo = Get-PfavSpherePlugin -html:$html -flash:$flash
      }
      if ($null -eq $fullPluginInfo)
      {
        throw "Specified plugin type or version not found on available source"
      }
      if ($fullPluginInfo.count -gt 1)
      {
        throw "Too many plugin versions returned. Internal script error!"
      }
      $hostedVersion = $fullPluginInfo.version
      $global:pfavSpherePluginUrl = $null
    }
    else {
      $hostedVersion = $version
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
                        Write-Warning -Message "The installed version of the plugin ($($installedHtmlVersion)) is the same as the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
                        continue
                    }
                    elseif ($splitInstalled[2] -gt $splitHosted[2])
                    {
                        Write-Warning -Message  "The installed version of the plugin ($($installedHtmlVersion)) is newer than the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
                        continue
                    }
                }
                elseif ($splitInstalled[1] -lt $splitHosted[1]) 
                {
                    $upgrade = $true
                }
                else {
                    Write-Warning -Message  "The installed version of the plugin ($($installedHtmlVersion)) is newer than the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
                    continue
                }
            }
            elseif ($splitInstalled[0] -lt $splitHosted[0]) 
            {
                $upgrade = $true
            }
            else {
                Write-Warning -Message "The installed version of the plugin ($($installedHtmlVersion)) is newer than the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
                continue
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
                      Write-Warning -Message "The installed version of the plugin ($($installedFlashVersion)) is the same as the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
                      continue
                    }
                    elseif ($splitInstalled[2] -gt $splitHosted[2])
                    {
                      Write-Warning -Message "The installed version of the plugin ($($installedFlashVersion)) is newer than the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
                      continue
                    }
                }
                elseif ($splitInstalled[1] -lt $splitHosted[1]) 
                {
                    $upgrade = $true
                }
                else {
                  Write-Warning -Message "The installed version of the plugin ($($installedFlashVersion)) is newer than the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
                  continue
                }
            }
            elseif ($splitInstalled[0] -lt $splitHosted[0]) 
            {
                $upgrade = $true
            }
            else {
              Write-Warning -Message "The installed version of the plugin ($($installedFlashVersion)) is newer than the version on the specified source ($($hostedVersion)). Skipping vCenter $($vCenter.name)."
              continue
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
    $extensionClientInfo.Version = $hostedVersion

    $extensionServerInfo = New-Object VMware.Vim.ExtensionServerInfo
    $extensionServerInfo.AdminEmail = "admin@purestorage.com"
    $extensionServerInfo.Company = "Pure Storage, Inc."
    $extensionServerInfo.Description = $description
    if ($pure1 -eq $true)
    {
      $extensionServerInfo.Url = $fullPluginInfo.URL
      $extensionClientInfo.Url = $fullPluginInfo.URL
      $extensionServerInfo.ServerThumbprint =  (Get-SSLThumbprint $fullPluginInfo.URL)
    }
    else 
    {
      $extensionServerInfo.Url = $customSource
      $extensionClientInfo.Url = $customSource
      $extensionServerInfo.ServerThumbprint =  (Get-SSLThumbprint "$($customSource)")
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

    if ($pure1 -eq $false)
    {
      $source = $customSource
    }
    else {
      $source = "Pure1"
    }
    if ($upgrade -eq $true)
    {

      $confirmText = "Upgrade $($pluginType) plugin from version $($pluginVersion) to $($hostedVersion) on vCenter $($vCenter.name)?"
    }
    else {
      $confirmText = "Install $($pluginType) plugin version $($hostedVersion) on vCenter $($vCenter.name)?"
    }
    if ($PSCmdlet.ShouldProcess("","$($confirmText)`n`r","Using $($source) as the download location`n`r")) 
    {
      #install or upgrade the vSphere plugin
      Write-Debug ($extensionSpec.Server |Out-String)
      Write-Debug ($extensionSpec.Client |Out-String)
      try {
        if ($upgrade -eq $true)
        {
            $extensionMgr.UpdateExtension($extensionSpec)
        }
        else 
        {
            $extensionMgr.RegisterExtension($extensionSpec)
        }
        write-host "Successfully installed $($pluginType) plugin version $($hostedVersion) on vCenter $($vCenter.name)." -ForegroundColor Green
      }
      catch {
        throw "Failed to install the vSphere plugin."
      }
      write-debug ($extensionMgr.FindExtension($extensionSpec.Key) | Out-String)
    }
  }
}
function Get-PfaVspherePlugin {
  <#
  .SYNOPSIS
    Retrieves version of FlashArray vSphere Plugin on one or more FlashArrays 
  .DESCRIPTION
    Retrieves version of FlashArray vSphere Plugin on one or more FlashArrays
  .INPUTS
    Versions or plugin type
  .OUTPUTS
    Returns plugin version for each array and/or Pure1.
  .EXAMPLE
    PS C:\ Get-PfavSpherePlugin
    
    Retrieves the latest vSphere plugin versions available on Pure1.
  .EXAMPLE
    PS C:\ Get-PfavSpherePlugin -previous
    
    Retrieves all of the vSphere plugin versions (old and latest) available on Pure1.
  .EXAMPLE
    PS C:\ Get-PfavSpherePlugin -html
    
    Retrieves the vSphere plugin HTML release available on Pure1.
  .EXAMPLE
    PS C:\ $vCenter = connect-viserver -Server myVcenter.purestorage.com
    PS C:\ Get-PfavSpherePlugin -Server $vCenter 
    
    Retrieves the plugin versions, type and source URL on the specified vCenter(s)
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/26/2020
    Purpose/Change: Multi-vCenter support.

  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  [CmdletBinding(DefaultParameterSetName='Hosted')]
  Param(
          [Parameter(Position=0)]
          [switch]$html,

          [Parameter(Position=1)]
          [switch]$flash,

          [Parameter(ParameterSetName='Hosted',Position=2)]
          [string]$version,

          [Parameter(ParameterSetName='Hosted',Position=3)]
          [switch]$previous,

          [Parameter(ParameterSetName='vCenter',Position=4,mandatory=$true)]
          [VMware.VimAutomation.ViCore.Types.V1.VIServer[]]$server
      )
    if ($null -ne $server)
    {
      $plugins =@()
      foreach ($vCenter in $server) 
      {
        $services = Get-view 'ServiceInstance' -Server $vCenter
        $extensionMgr  = Get-view $services.Content.ExtensionManager -Server $vCenter
        #check for HTML-5 client
        $installedHtmlVersion = $null
        $installedHtmlVersion = $extensionMgr.FindExtension("com.purestorage.purestoragehtml")
        $Result = $null
        $Result = "" | Select-Object Source,Type,Version,URL
        if ($null -ne $installedHtmlVersion)
        {
          $Result.URL = $installedHtmlVersion.Client.Url
          $Result.Version = $installedHtmlVersion.version
        }
        else {
          $Result.URL = $null
          $Result.Version = "Not Installed"
        }
        $Result.Source = $vCenter.name
        $Result.Type = "HTML-5"
        $plugins += $Result
        #check for flash client
        $installedFlashVersion = $null
        $installedFlashVersion = $extensionMgr.FindExtension("com.purestorage.plugin.vsphere")
        $Result = $null
        $Result = "" | Select-Object Source,Type,Version,URL
        if ($null -ne $installedFlashVersion)
        {
          $Result.URL = $installedFlashVersion.Client.Url
          $Result.Version = $installedFlashVersion.version
        }
        else {
          $Result.URL = $null
          $Result.Version = "Not Installed"
        }
        $Result.Source = $vCenter.name
        $Result.Type = "Flash"
        $plugins += $Result
      }
      if (($html -eq $True) -and ($flash -eq $false))
      {
          $plugins = $plugins |Where-Object {$_.Type -eq "HTML-5"}
      }
      elseif (($html -eq $false) -and ($flash -eq $true)) 
      {
          $plugins = $plugins |Where-Object {$_.Type -eq "Flash"}
      }
      return $plugins |Select-Object Source,Type,Version,Url
    }
    else 
    {
      $plugins =@()
      try {
        $flashS3tag = Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/Flex/purestorage-vsphere-plugin.zip?tagging"
        $Result = $null
        $Result = "" | Select-Object Source,Type,Version,URL
        $Result.Source = "Pure1"
        $Result.Version = $flashS3tag.Tagging.TagSet.Tag.Value
        $Result.Type = "Flash"
        $Result.URL = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/Flex/purestorage-vsphere-plugin.zip"
        $plugins += $Result
        if ($previous -eq $true)
        {
          $previousVersions = (Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/FlexOlderRevs/versions.txt?tagging").Tagging.TagSet.Tag.value.split(" ")
          foreach ($previousVersion in $previousVersions)
          {
            $flashS3tag = Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/FlexOlderRevs/$($previousVersion)/purestorage-vsphere-plugin.zip?tagging"
            $Result = $null
            $Result = "" | Select-Object Source,Type,Version,URL
            $Result.Source = "Pure1"
            $Result.Version = $flashS3tag.Tagging.TagSet.Tag.Value
            $Result.Type = "Flash"
            $Result.URL = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/FlexOlderRevs/$($previousVersion)/purestorage-vsphere-plugin.zip"
            $plugins += $Result
          }
        }
        $htmlS3tag = Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5/purestorage-vsphere-plugin.zip?tagging"
        $Result = $null
        $Result = "" | Select-Object Source,Type,Version,URL
        $Result.Source = "Pure1"
        $Result.Version = $htmlS3tag.Tagging.TagSet.Tag.Value
        $Result.Type = "HTML-5"
        $Result.URL = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5/purestorage-vsphere-plugin.zip"
        $plugins += $Result
        if ($previous -eq $true)
        {
          $previousVersions = (Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5OlderRevs/versions.txt?tagging").Tagging.TagSet.Tag.value.split(" ")
          foreach ($previousVersion in $previousVersions)
          {
            $htmlS3tag = Invoke-RestMethod -Method GET -Uri "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5OlderRevs/$($previousVersion)/purestorage-vsphere-plugin.zip?tagging"
            $Result = $null
            $Result = "" | Select-Object Source,Type,Version,URL
            $Result.Source = "Pure1"
            $Result.Version = $htmlS3tag.Tagging.TagSet.Tag.Value
            $Result.Type = "HTML-5"
            $Result.URL = "https://pure-vmware-plugin-repository.s3-us-west-1.amazonaws.com/vsphere/HTML5OlderRevs/$($previousVersion)/purestorage-vsphere-plugin.zip"
            $plugins += $Result
          }
        }
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
    if ($plugins.count -eq 0)
    {
      throw "The specified plugin version/type was not found on any of the available sources."
    }
    Write-Debug ($plugins |Out-String) |Format-Table -AutoSize
    if ($global:pfavSpherePluginurl -eq $True)
    {
      return $plugins
    }
    else {
      return $plugins |Select-Object Source,Type,Version
    }
  }
}
function Uninstall-PfaVspherePlugin {
  <#
  .SYNOPSIS
    Uninstall the Pure Storage FlashArray vSphere Plugin
  .DESCRIPTION
    Uninstall the Flash or HTML Pure Storage FlashArray vSphere Plugin from the connected vCenter
  .INPUTS
    HTML or Flash
  .OUTPUTS
    No output unless there is an error.
  .EXAMPLE
    PS C:\ Uninstall-PfavSpherePlugin 
    
    Uninstalls whichever plugin is currently installed on the connected vCenter.
  .EXAMPLE
    PS C:\ Uninstall-PfavSpherePlugin -Confirm:$false
    
    Uninstalls whichever plugin is currently installed on the connected vCenter with no confirmation prompt.
  .EXAMPLE
    PS C:\ Uninstall-PfavSpherePlugin -html
    
    Uninstalls the HTML-5-based plugin from a vCenter.
  .EXAMPLE
    PS C:\ Uninstall-PfavSpherePlugin -flash
    
    Uninstalls the flash-based plugin from a vCenter.
  .EXAMPLE
    PS C:\ $vCenter = connect-viserver -Server myVcenter.purestorage.com
    PS C:\ Uninstall-PfavSpherePlugin -Server $vCenter 
    
    Uninstalls the found plugin from the specified vCenter(s)
  .EXAMPLE
    PS C:\ $vCenter = connect-viserver -Server myVcenter.purestorage.com
    PS C:\ Uninstall-PfavSpherePlugin -Server $vCenter -flash
    
    Uninstalls the flash plugin from the specified vCenter(s)
  .EXAMPLE
    PS C:\ Uninstall-PfavSpherePlugin -Server $Global:DefaultViServers -flash
    
    Uninstalls the flash plugin from all currently connected vCenters.
  .EXAMPLE
    PS C:\ Uninstall-PfavSpherePlugin -Server $Global:DefaultViServers -flash -Confirm:$false
    
    Uninstalls the flash plugin from all currently connected vCenters with no confirmation prompt.
  .NOTES
    Version:        2.0
    Author:         Cody Hosterman https://codyhosterman.com
    Creation Date:  08/26/2020
    Purpose/Change: Multi-vCenter support.

  *******Disclaimer:******************************************************
  This scripts are offered "as is" with no warranty.  While this 
  scripts is tested and working in my environment, it is recommended that you test 
  this script in a test lab before using in a production environment. Everyone can 
  use the scripts/commands provided here without any written permission but I
  will not be liable for any damage or loss to the system.
  ************************************************************************
  #>

  [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High',DefaultParameterSetName='HTML')]
  Param(
          [Parameter(ParameterSetName='HTML',Position=0)]
          [switch]$html,

          [Parameter(ParameterSetName='Flash',Position=1)]
          [switch]$flash,

          [Parameter(Position=2)]
          [VMware.VimAutomation.ViCore.Types.V1.VIServer[]]$server
  )
  if ($null -eq $server)
  {
    $vCenters = $global:DefaultVIServers
  }
  else {
    $vCenters = $server
  }
  if ($null -eq $vCenters)
  {
    throw "You must specify one or more vCenter connections in the -server parameter or connect one with connect-viserver"
  }
  $ErrorActionPreference = "stop"
  foreach ($vCenter in $vCenters) 
  {
    #gather extension manager
    $services = Get-view 'ServiceInstance' -Server $vCenter
    $extensionMgr  = Get-view $services.Content.ExtensionManager -Server $vCenter
    $htmlPluginVersion = ($extensionMgr.FindExtension("com.purestorage.purestoragehtml")).version
    $flashPluginVersion = ($extensionMgr.FindExtension("com.purestorage.plugin.vsphere")).version

    if (($html -ne $true) -and ($flash -ne $true))
    {
      if (($null -ne $flashPluginVersion) -and ($null -ne $htmlPluginVersion))
      {
        Write-Warning -Message  "Both the Flash and HTML-5 Plugins are installed in vCenter $($vCenter.name). Please specify which plugin to uninstall with the -html or -flash parameter. Skipping this vCenter."
        Continue
      }
      elseif ($null -ne $flashPluginVersion) {
        $flash = $true
      }
      elseif ($null -ne $htmlPluginVersion) {
        $html = $true
      }
      else {
        Write-Warning -Message  "There is no Pure Storage plugin installed on vCenter $($vCenter.name). Skipping this vCenter."
        Continue
      }
    }
    #find what plugins are installed and their version
    if ($html -eq $true)
    {
      if ($null -eq $htmlPluginVersion)
      {
        Write-Warning -Message  "The HTML-5 plugin is not currently installed in vCenter $($vCenter.name). Skipping this vCenter."
        Continue
      }
      $confirmText = "Uninstall HTML-5 plugin version $($htmlPluginVersion) on vCenter $($vCenter.name)?"
      if ($PSCmdlet.ShouldProcess("","$($confirmText)`n`r","Please confirm uninstall.`n`r")) 
      {
        $extensionMgr.UnregisterExtension("com.purestorage.purestoragehtml")
        write-host "Pure Storage HTML-5 plugin has been uninstalled on $($vCenter.Name)." -ForegroundColor Yellow
      }
    }
    else {
      if ($null -eq $flashPluginVersion)
      {
        Write-Warning -Message "The flash plugin is not currently installed in vCenter $($vCenter.name).Skipping this vCenter."
        continue
      }
      $confirmText = "Uninstall flash plugin version $($flashPluginVersion) on vCenter $($vCenter.name)?"
      if ($PSCmdlet.ShouldProcess("","$($confirmText)`n`r","Please confirm uninstall.`n`r")) 
      {
        $extensionMgr.UnregisterExtension("com.purestorage.plugin.vsphere")
        write-host "Pure Storage flash plugin has been uninstalled on $($vCenter.Name)." -ForegroundColor Yellow
      }
    }
  }
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

      [Parameter(ParameterSetName='StaticHost',Position=1,ValueFromPipeline=$True,mandatory=$true)]
      [Parameter(ParameterSetName='DHCPHost',Position=1,ValueFromPipeline=$True,mandatory=$true)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$vmHost,

      [Parameter(Position=2,mandatory=$true)]
      [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$datastore,

      [Parameter(Position=3,mandatory=$true)]
      [VMware.VimAutomation.ViCore.Types.V1.Host.Networking.VirtualPortGroupBase]$portGroup,

      [Parameter(ParameterSetName='StaticCluster',Position=4,mandatory=$true,ValueFromPipeline=$True)]
      [Parameter(ParameterSetName='DHCPCluster',Position=4,mandatory=$true,ValueFromPipeline=$True)]
      [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$cluster,

      [Parameter(ParameterSetName='DHCPCluster',Position=5)]
      [Parameter(ParameterSetName='DHCPHost',Position=5)]
      [switch]$dhcp,

      [Parameter(Position=6,mandatory=$true)]
      [string]$authorizationKey,

      [Parameter(ParameterSetName='StaticCluster',Position=7,mandatory=$true)]
      [Parameter(ParameterSetName='StaticHost',Position=7,mandatory=$true)]
      [string]$ipAddress,

      [Parameter(ParameterSetName='StaticCluster',Position=8,mandatory=$true)]
      [Parameter(ParameterSetName='StaticHost',Position=8,mandatory=$true)]
      [string]$netmask,

      [Parameter(ParameterSetName='StaticCluster',Position=9,mandatory=$true)]
      [Parameter(ParameterSetName='StaticHost',Position=9,mandatory=$true)]
      [string]$gateway,

      [Parameter(ParameterSetName='StaticCluster',Position=10,mandatory=$true)]
      [Parameter(ParameterSetName='StaticHost',Position=10,mandatory=$true)]
      [string]$dnsPrimary,

      [Parameter(ParameterSetName='StaticCluster',Position=11,mandatory=$true)]
      [Parameter(ParameterSetName='StaticHost',Position=11,mandatory=$true)]
      [string]$dnsSecondary,

      [Parameter(ParameterSetName='StaticCluster',Position=12,mandatory=$true)]
      [Parameter(ParameterSetName='StaticHost',Position=12,mandatory=$true)]
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
    $vCenterVersion = $Global:DefaultVIServer | Select-Object Version
    if (($vCenterVersion.Version -eq "6.0.0") -and ($ovaPassword.length -ge 1))
    {
        Throw "vCenter version 6.0 does not support the APIs that are required to change the default password. Please re-run the deployment without specifying a password. You will then need to manually SSH in or use the VM console to change the default password to one of your own."
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
    if ($null -eq $vmhost)
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
    $creds = New-Object System.Management.Automation.PSCredential ("pureuser", $ovaPassword)
    return (Get-PfaAppliance -vm $vm -applianceCredentials $creds)
  }
  else {
    return get-vm $vm.name
  }
  
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
    $vCenterVersion = $Global:DefaultVIServer | Select-Object Version
    if ($vCenterVersion.Version -eq "6.0.0")
    {
        Throw "vCenter version 6.0 does not support the APIs that are required to import the configuration of another appliance. The simplest option is to manually add the vCenters to collector via .AddvCenter(<vCenter FQND>,<vCenter credentials>) method."
    }
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
  if ($URL -notlike "https://*")
  { 
    $URL = "https://" + $URL
  }
  $Code = @'
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
namespace CertificateCapture
{
  public class Utility
  {
      public static Func<HttpRequestMessage,X509Certificate2,X509Chain,SslPolicyErrors,Boolean> ValidationCallback =
          (message, cert, chain, errors) => {
              var newCert = new X509Certificate2(cert);
              var newChain = new X509Chain();
              newChain.Build(newCert);
              CapturedCertificates.Add(new CapturedCertificate(){
                  Certificate =  newCert,
                  CertificateChain = newChain,
                  PolicyErrors = errors,
                  URI = message.RequestUri
              });
              return true;
          };
      public static List<CapturedCertificate> CapturedCertificates = new List<CapturedCertificate>();
  }
  public class CapturedCertificate
  {
      public X509Certificate2 Certificate { get; set; }
      public X509Chain CertificateChain { get; set; }
      public SslPolicyErrors PolicyErrors { get; set; }
      public Uri URI { get; set; }
  }
}
'@
  if ($PSEdition -ne 'Core'){
      Add-Type -AssemblyName System.Net.Http
      if (-not ("CertificateCapture" -as [type])) {
          Add-Type $Code -ReferencedAssemblies System.Net.Http 
      }
  } else {
      if (-not ("CertificateCapture" -as [type])) {
          Add-Type $Code 
      }
  }

  $Certs = [CertificateCapture.Utility]::CapturedCertificates
  $Handler = [System.Net.Http.HttpClientHandler]::new()
  $Handler.ServerCertificateCustomValidationCallback = [CertificateCapture.Utility]::ValidationCallback
  $Client = [System.Net.Http.HttpClient]::new($Handler)
  $Client.GetAsync($Url).Result |Out-Null
  $sha1 = [Security.Cryptography.SHA1]::Create()
  $certBytes = $Certs[-1].Certificate.GetRawCertData()
  $hash = $sha1.ComputeHash($certBytes)
  $thumbprint = [BitConverter]::ToString($hash).Replace('-',':')
  return $thumbprint
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
    if (($null -eq $queryResponse.("P$($i)")) -or ($null -eq $queryResponse.("P$($i + 1)")))
    {
      break
    }
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
