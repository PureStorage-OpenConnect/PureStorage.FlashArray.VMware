<!-- wp:heading -->
<h2>Pure Storage VMware PowerShell Module Help Info</h2>
<!-- /wp:heading -->
<p><!--StartFragment--></p>

<!-- wp:paragraph -->
<p>To help our customers I have written a module that includes a lot of the common operations people might need to “connect” PowerCLI to our PowerShell SDK.</p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p><strong>Latest version 1.4.1.4 (May 5th, 2020)</strong></p>
<!-- /wp:paragraph -->

<!-- wp:paragraph -->
<p>The module is called <a href="https://www.powershellgallery.com/packages/PureStorage.FlashArray.VMware/">PureStorage.FlashArray.VMware</a>.</p>
<!-- /wp:paragraph -->

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

<!-- wp:image {"id":6305,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large"><img src="https://www.codyhosterman.com/wp-content/uploads/2020/01/image-15-1024x370.png" alt="" class="wp-image-6305"/></figure>
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
<p>For all available commands, use<em> get-command</em>:</p>
<!-- /wp:paragraph -->

<!-- wp:image {"id":6306,"sizeSlug":"large"} -->
<figure class="wp-block-image size-large"><img src="https://www.codyhosterman.com/wp-content/uploads/2020/01/image-16-1024x985.png" alt="" class="wp-image-6306"/></figure>
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
