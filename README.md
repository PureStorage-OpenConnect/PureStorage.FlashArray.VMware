<!-- wp:paragraph -->
<p>To help our customers I have written a module that includes a lot of the common operations people might need to “connect” PowerCLI to our PowerShell SDK.</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p>The module is called <a href="https://www.powershellgallery.com/packages/PureStorage.FlashArray.VMware/">PureStorage.FlashArray.VMware</a>.<span id="more-4949"></span></p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p>The module is designed into four separate modules that are included when you install the main one:</p>
<!-- /wp:paragraph -->

<!-- wp:list -->
<ul><li>PureStorage.FlashArray.VMware.Configuration --this does connection management, host configuration, and generic initial setup.</li><li>PureStorage.FlashArray.VMware.VMFS--this offers VMFS-related cmdlets</li><li>PureStorage.FlashArray.VMware.VVol--this offers VVol-related cmdlets</li><li>PureStorage.FlashArray.VMware.RDM--this offers RDM-related cmdlets</li></ul>
<!-- /wp:list -->

<!-- wp:paragraph -->
<p>There are two places you can download this. The best option is the <a href="https://www.powershellgallery.com/packages/Cody.PureStorage.FlashArray.VMwar">PowerShell gallery</a>! This allows you to use <a href="https://docs.microsoft.com/en-us/powershell/module/powershellget/install-module?view=powershell-6">install-module</a> to automatically install the module. It requires PowerCLI and the <a href="https://www.powershellgallery.com/packages/PureStoragePowerShellSDK/">PureStorage PowerShell SDK</a> to be installed, the Pure Storage PowerShell SDK will be automatically installed when you do install-module if it is not already.</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":5644} -->
<figure class="wp-block-image"><img src="https://www.codyhosterman.com/wp-content/uploads/2019/06/image.png" alt="" class="wp-image-5644"/></figure>
<!-- /wp:image -->

<!-- wp:image {"id":5645} -->
<figure class="wp-block-image"><img src="https://www.codyhosterman.com/wp-content/uploads/2019/06/image-1.png" alt="" class="wp-image-5645"/></figure>
<!-- /wp:image -->

<!-- wp:paragraph -->
<p>The module will help you connect PowerCLI commands (like get-datastore or get-vmhost) to operations you might want to do on the FlashArray. The cmdlets support pipeline input for most variables (datastores, FlashArray connections, ESXi hosts, etc.).</p>
<!-- /wp:paragraph -->

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
<p>Use either get-help or get-command to see the details:</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p> </p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":5774} -->
<figure class="wp-block-image"><img src="https://www.codyhosterman.com/wp-content/uploads/2019/07/image-2-1024x294.png" alt="" class="wp-image-5774"/></figure>
<!-- /wp:image -->

<!-- wp:image {"id":5775} -->
<figure class="wp-block-image"><img src="https://www.codyhosterman.com/wp-content/uploads/2019/07/image-3-1024x585.png" alt="" class="wp-image-5775"/></figure>
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

<h2>Latest version 1.2.1.0 (July 13th, 2019)</h2>
<p>Cmdlets:</p>
<p><a class="tag" title="Search for new-pfaConnection" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaConnection%22">new-pfaConnection</a> <a class="tag" title="Search for get-pfaDatastore" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaDatastore%22">get-pfaDatastore</a> <a class="tag" title="Search for get-pfaConnectionOfDatastore" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaConnectionOfDatastore%22">get-pfaConnectionOfDatastore</a> <a class="tag" title="Search for new-pfaRestSession" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaRestSession%22">new-pfaRestSession</a> <a class="tag" title="Search for remove-pfaRestSession" href="https://www.powershellgallery.com/packages?q=Functions%3A%22remove-pfaRestSession%22">remove-pfaRestSession</a> <a class="tag" title="Search for new-pfaHostFromVmHost" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaHostFromVmHost%22">new-pfaHostFromVmHost</a> <a class="tag" title="Search for get-pfaHostFromVmHost" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaHostFromVmHost%22">get-pfaHostFromVmHost</a> <a class="tag" title="Search for get-pfaHostGroupfromVcCluster" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaHostGroupfromVcCluster%22">get-pfaHostGroupfromVcCluster</a><a class="tag" title="Search for new-pfaHostGroupfromVcCluster" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaHostGroupfromVcCluster%22">new-pfaHostGroupfromVcCluster</a> <a class="tag" title="Search for set-vmHostPfaiSCSI" href="https://www.powershellgallery.com/packages?q=Functions%3A%22set-vmHostPfaiSCSI%22">set-vmHostPfaiSCSI</a> <a class="tag" title="Search for set-clusterPfaiSCSI" href="https://www.powershellgallery.com/packages?q=Functions%3A%22set-clusterPfaiSCSI%22">set-clusterPfaiSCSI</a> <a class="tag" title="Search for new-pfaVolRdm" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaVolRdm%22">new-pfaVolRdm</a> <a class="tag" title="Search for get-pfaVolfromRDM" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaVolfromRDM%22">get-pfaVolfromRDM</a> <a class="tag" title="Search for get-pfaConnectionlfromRDM" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaConnectionlfromRDM%22">get-pfaConnectionlfromRDM</a> <a class="tag" title="Search for new-pfaVolRdmSnapshot" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaVolRdmSnapshot%22">new-pfaVolRdmSnapshot</a> <a class="tag" title="Search for get-pfaVolRDMSnapshot" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaVolRDMSnapshot%22">get-pfaVolRDMSnapshot</a> <a class="tag" title="Search for copy-pfaSnapshotToRDM" href="https://www.powershellgallery.com/packages?q=Functions%3A%22copy-pfaSnapshotToRDM%22">copy-pfaSnapshotToRDM</a> <a class="tag" title="Search for set-pfaVolRDMCapacity" href="https://www.powershellgallery.com/packages?q=Functions%3A%22set-pfaVolRDMCapacity%22">set-pfaVolRDMCapacity</a> <a class="tag" title="Search for remove-pfaVolRDM" href="https://www.powershellgallery.com/packages?q=Functions%3A%22remove-pfaVolRDM%22">remove-pfaVolRDM</a> <a class="tag" title="Search for convert-pfaVolRDMtoVvol" href="https://www.powershellgallery.com/packages?q=Functions%3A%22convert-pfaVolRDMtoVvol%22">convert-pfaVolRDMtoVvol</a> <a class="tag" title="Search for get-pfaVolfromVMFS" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaVolfromVMFS%22">get-pfaVolfromVMFS</a> <a class="tag" title="Search for new-pfaVolVmfs" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaVolVmfs%22">new-pfaVolVmfs</a> <a class="tag" title="Search for add-pfaVolVmfsToCluster" href="https://www.powershellgallery.com/packages?q=Functions%3A%22add-pfaVolVmfsToCluster%22">add-pfaVolVmfsToCluster</a> <a class="tag" title="Search for set-pfaVolVmfsCapacity" href="https://www.powershellgallery.com/packages?q=Functions%3A%22set-pfaVolVmfsCapacity%22">set-pfaVolVmfsCapacity</a> <a class="tag" title="Search for get-pfaVolVmfsSnapshot" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaVolVmfsSnapshot%22">get-pfaVolVmfsSnapshot</a> <a class="tag" title="Search for new-pfaVolVmfsSnapshot" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaVolVmfsSnapshot%22">new-pfaVolVmfsSnapshot</a> <a class="tag" title="Search for new-pfaVolVmfsFromSnapshot" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaVolVmfsFromSnapshot%22">new-pfaVolVmfsFromSnapshot</a> <a class="tag" title="Search for update-pfaVvolVmVolumeGroup" href="https://www.powershellgallery.com/packages?q=Functions%3A%22update-pfaVvolVmVolumeGroup%22">update-pfaVvolVmVolumeGroup</a> <a class="tag" title="Search for get-vvolUuidFromHardDisk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-vvolUuidFromHardDisk%22">get-vvolUuidFromHardDisk</a> <a class="tag" title="Search for get-pfaVolumeNameFromVvolUuid" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaVolumeNameFromVvolUuid%22">get-pfaVolumeNameFromVvolUuid</a> <a class="tag" title="Search for get-pfaSnapshotsFromVvolHardDisk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-pfaSnapshotsFromVvolHardDisk%22">get-pfaSnapshotsFromVvolHardDisk</a> <a class="tag" title="Search for copy-pfaVvolVmdkToNewVvolVmdk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22copy-pfaVvolVmdkToNewVvolVmdk%22">copy-pfaVvolVmdkToNewVvolVmdk</a> <a class="tag" title="Search for copy-pfaSnapshotToExistingVvolVmdk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22copy-pfaSnapshotToExistingVvolVmdk%22">copy-pfaSnapshotToExistingVvolVmdk</a><a class="tag" title="Search for copy-pfaSnapshotToNewVvolVmdk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22copy-pfaSnapshotToNewVvolVmdk%22">copy-pfaSnapshotToNewVvolVmdk</a> <a class="tag" title="Search for copy-pfaVvolVmdkToExistingVvolVmdk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22copy-pfaVvolVmdkToExistingVvolVmdk%22">copy-pfaVvolVmdkToExistingVvolVmdk</a> <a class="tag" title="Search for new-pfaSnapshotOfVvolVmdk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22new-pfaSnapshotOfVvolVmdk%22">new-pfaSnapshotOfVvolVmdk</a><a class="tag" title="Search for get-vmdkFromWindowsDisk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-vmdkFromWindowsDisk%22">get-vmdkFromWindowsDisk, </a><a class="tag" title="Search for New-PfaVasaProvider" href="https://www.powershellgallery.com/packages?q=Functions%3A%22New-PfaVasaProvider%22">New-PfaVasaProvider</a><a class="tag" title="Search for get-vmdkFromWindowsDisk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-vmdkFromWindowsDisk%22"> </a><a class="tag" title="Search for Get-PfaVasaProvider" href="https://www.powershellgallery.com/packages?q=Functions%3A%22Get-PfaVasaProvider%22">Get-PfaVasaProvider</a><a class="tag" title="Search for get-vmdkFromWindowsDisk" href="https://www.powershellgallery.com/packages?q=Functions%3A%22get-vmdkFromWindowsDisk%22"> </a><a class="tag" title="Search for Remove-PfaVasaProvider" href="https://www.powershellgallery.com/packages?q=Functions%3A%22Remove-PfaVasaProvider%22">Remove-PfaVasaProvider</a><a class="tag" title="Search for Install-PfavSpherePlugin" href="https://www.powershellgallery.com/packages?q=Functions%3A%22Install-PfavSpherePlugin%22">Install-PfavSpherePlugin</a><a class="tag" title="Search for Remove-PfaVasaProvider" href="https://www.powershellgallery.com/packages?q=Functions%3A%22Remove-PfaVasaProvider%22"> </a><a class="tag" title="Search for Get-PfavSpherePlugin" href="https://www.powershellgallery.com/packages?q=Functions%3A%22Get-PfavSpherePlugin%22">Get-PfavSpherePlugin</a></p>
