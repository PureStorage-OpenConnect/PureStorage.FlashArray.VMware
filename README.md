<!-- wp:heading -->
<h2>Pure Storage VMware PowerShell Module Help Info</h2>
<!-- /wp:heading -->
<p><!--StartFragment--></p>

<p><!--StartFragment--></p>

<!-- wp:paragraph -->
<p>To help our customers I have written a module that includes a lot of the common operations people might need to “connect” PowerCLI to our PowerShell SDK.</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p><strong>Latest version 2.0.0.0 (August 26th, 2020)</strong></p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p>The module is called <a href="https://www.powershellgallery.com/packages/PureStorage.FlashArray.VMware/">PureStorage.FlashArray.VMware</a>.</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p><strong>New Features:</strong></p>
<!-- /wp:paragraph -->

<!-- wp:list -->
<ul><li><strong>New CMDLETS: </strong><ul><li><strong>New-PfaRestOperation</strong> is a new command for running REST API operations against a flasharray</li><li><strong>Get-PfavVolVol </strong>Returns the volumes and volume group(s) of a given vVol VM</li></ul></li><li>Added parameter to Update-PfavVolVMVolume group of -volumeGroupName for specifying a custom vgroup name instead of using the default naming scheme</li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/39">Get-PfaVasaProvider return all providers now if you do not specify a FlashArray</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/37">Improved error handling</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/6"><strong>PowerShell Core support</strong></a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/16">Multi-vCenter support for get-pfaVsphereplugin, install-pfaVspherePlugin, and uninstall-pfaVspherePlugin</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/11">Can now specify a source volume name when creating a VMFS from a snapshot instead of it being auto-generated</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/27">Can now provision VMFS volumes on ESXi 7 host</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/26">Get-PfaVspherePlugin now can return what is installed on a vCenter when -Server parameter is supplied</a></li></ul>
<!-- /wp:list -->

<!-- wp:paragraph -->
<p><strong>Fixed Issues:</strong></p>
<!-- /wp:paragraph -->

<!-- wp:list -->
<ul><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/41">New-PfaSnapshotOfVvolVmdk : Suffix parameter is not honored. Snapshot is created but with an incremental number</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/38">Misspelled out-null in Copy-PfaVvolVmdkToExistingVvolVmdk</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/25">unable to manage/login to the Pure1 Collector via PowerShell</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/34">Copy-PfaSnapshotToRDM fails badly if snapshot is not found.</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/35">Some RDM workflows did not pick up default FA connection</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/44">Mount-PfaVvolDatastore fails if no datastore, VASA array or FA input</a></li><li><a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues/15">Issue slowing down Get-PfaVspherePlugin when a FlashArray connection exists is resolved</a></li></ul>
<!-- /wp:list -->

<!-- wp:paragraph -->
<p><em>To report issues or request new features, please enter them here:</em></p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p> <a href="https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues">https://github.com/PureStorage-OpenConnect/PureStorage.FlashArray.VMware/issues</a> </p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p> For questions, <a href="https://codeinvite.purestorage.com/">join our Pure Storage Code Slack</a> team! Check out the #PowerCLI channel<span id="more-4949"></span></p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p>The module is designed into six separate modules that are included when you install the main one:</p>
<!-- /wp:paragraph -->

<!-- wp:list -->
<ul><li><strong>PureStorage.FlashArray.VMware.Configuration</strong> --this does connection management, host configuration, and generic initial setup.</li><li><strong>PureStorage.FlashArray.VMware.VMFS</strong>--this offers VMFS-related cmdlets</li><li><strong>PureStorage.FlashArray.VMware.vVol</strong>--this offers vVol-related cmdlets</li><li><strong>PureStorage.FlashArray.VMware.RDM</strong>--this offers RDM-related cmdlets</li><li> <strong>PureStorage.FlashArray.VMware.Pure1</strong>--this offers Pure1 Meta-related cmdlets (experimental)</li><li> <strong>PureStorage.FlashArray.VMware.Software</strong>--this offers Pure Storage software deployment and management cmdlets </li></ul>
<!-- /wp:list -->

<!-- wp:paragraph -->
<p>There are two places you can install this. The best option is the <a href="https://www.powershellgallery.com/packages/Cody.PureStorage.FlashArray.VMwar">PowerShell gallery</a>! This allows you to use <a href="https://docs.microsoft.com/en-us/powershell/module/powershellget/install-module?view=powershell-6">install-module</a> to automatically install the module. </p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p>It requires PowerCLI... </p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":6278,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large"><img src="https://www.codyhosterman.com/wp-content/uploads/2020/01/image-2.png" alt="" class="wp-image-6278"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>...and the <a href="https://www.powershellgallery.com/packages/PureStoragePowerShellSDK/">PureStorage PowerShell SDK</a> to be installed, the Pure Storage PowerShell SDK will be automatically installed when you install this module if it is not already. </p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":6277,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large"><img src="https://www.codyhosterman.com/wp-content/uploads/2020/01/image-1.png" alt="" class="wp-image-6277"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>The module will help you connect PowerCLI commands (like get-datastore or get-vmhost) to operations you might want to do on the FlashArray. The cmdlets support pipeline input for most variables (datastores, FlashArray connections, ESXi hosts, etc.).</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":6861,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large"><img src="https://www.codyhosterman.com/wp-content/uploads/2020/08/image-5-1024x281.png" alt="" class="wp-image-6861"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>To install:</p>
<!-- /wp:paragraph -->

<!-- wp:preformatted -->
<pre class="wp-block-preformatted">install-module PureStorage.FlashArray.VMware</pre>
<!-- /wp:preformatted -->

<!-- wp:paragraph -->
<p>To load the module:</p>
<!-- /wp:paragraph -->

<!-- wp:preformatted -->
<pre class="wp-block-preformatted">import-module PureStorage.FlashArray.VMware</pre>
<!-- /wp:preformatted -->

<!-- wp:paragraph -->
<p>To update:</p>
<!-- /wp:paragraph -->

<!-- wp:preformatted -->
<pre class="wp-block-preformatted">update-module PureStorage.FlashArray.VMware</pre>
<!-- /wp:preformatted -->

<!-- wp:paragraph -->
<p>For all available commands, use<em> get-command</em>:</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":6859,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large"><img src="https://www.codyhosterman.com/wp-content/uploads/2020/08/image-4-1024x980.png" alt="" class="wp-image-6859"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>For specifics, use <em>get-help</em> plus the function you want.</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":6281,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large"><img src="https://www.codyhosterman.com/wp-content/uploads/2020/01/image-4-955x1024.png" alt="" class="wp-image-6281"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p><strong>Comment on Versioning</strong></p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p>Versions numbering w.x.y.z (for example 1.3.0.0)</p>
<!-- /wp:paragraph -->

<!-- wp:list -->
<ul><li>W is iterated for large updates</li><li>X is iterated for new cmdlets</li><li>Y is iterated for new functions to existing cmdlets</li><li>Z is iterated for bug fixes</li></ul>
<!-- /wp:list -->

<h2>&nbsp;</h2>
<p></p>
<p><!--EndFragment--></p>

<!-- wp:paragraph -->
<p></p>
<!-- /wp:paragraph -->
