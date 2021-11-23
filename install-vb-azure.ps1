###########################################################################
# Deploy Veeam Backup for MS Azure v3.0 from the Marketplace via PowerShell
###########################################################################
<#
Handy sources:

Find images in the Marketplace:
    https://docs.microsoft.com/en-us/azure/virtual-machines/windows/cli-ps-findimage
Create VM example:
    https://github.com/Azure/azure-docs-powershell-samples/blob/master/virtual-machine/create-vm-detailed/create-windows-vm-detailed.ps1
Create VM from a VMPlan:
    https://docs.microsoft.com/en-us/powershell/module/az.compute/new-azvm?view=azps-6.6.0
    https://docs.microsoft.com/en-us/azure/virtual-machines/windows/cli-ps-findimage#create-a-new-vm-from-a-vhd-with-purchase-plan-information
#>

# Install the Azure PowerShell module
if ($PSVersionTable.PSEdition -eq 'Desktop' -and (Get-Module -Name AzureRM -ListAvailable)) {
    Write-Warning -Message ('Az module not installed. Having both the AzureRM and ' +
      'Az modules installed at the same time is not supported.')
} else {
    Install-Module -Name Az -AllowClobber -Scope CurrentUser
}

###########################################################################
# VARIABLES
###########################################################################

# AZURE VARIABLES
$ResourceGroupName = "rg-vba"
$storageAccount = "storagevba"
$containerName = "containervba"
$LocationName = "norwayeast" # Set Azure Region via: Get-AzLocation | select Location

# VM VARIABLES
$VMName = "vba"
$VMLocalAdminUser = "vba-admin"
$VMLocalAdminSecurePassword = ConvertTo-SecureString Veeam!123! -AsPlainText -Force
$ComputerName = "VBA"
$VMName = "VBA"
$VMSize = "Standard_B2s"

$NetworkName = "VBA-net"
$NICName = "VBA-NIC"
$SubnetName = "VBA-Subnet"
$PublicIPAddressName = "VBA-PublicIP"
$SubnetAddressPrefix = "10.0.0.0/24"
$VnetAddressPrefix = "10.0.0.0/16"

# MARKETPLACE VM VARIABLES
$publisherName="veeam"
$offerName="azure_backup"
$skuName="veeambackupazure"
$version = "3.0.0"

<#
# List images from Veeam in the marketplace
#Get-AzVMImageOffer -Location $LocationName -PublisherName $publisherName | Select Offer

# Check the SKU
#Get-AzVMImageSku -Location $LocationName -PublisherName $publisherName -Offer $offerName | Select Skus

# For the SKU, list the versions of the image
#Get-AzVMImage -Location $LocationName -PublisherName $publisherName -Offer $offerName -Sku $skuName | Select Version
#>

###########################################################################
# SCRIPT START
###########################################################################

# Connect to Azure (Interactive for demo)
# https://docs.microsoft.com/en-us/powershell/azure/authenticate-azureps?view=azps-6.6.0
Connect-AzAccount

# Set the subscription to use if needed
#Select-AzureSubscription -Current -SubscriptionName ""

# Create Resource Group or use existing
$checkgroup = Get-AzResourceGroup -Name $resourceGroup

if ($checkgroup.ProvisioningState -eq "Succeeded") {
    Write-Host -ForegroundColor Green "Resource group $ResourceGroupName exists, continue ..."
    }
else {
    New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
    }

# Create Storage Account or use existing
$checkstorage = Get-AzStorageAccount -ResourceGroupName $resourceGroup
if ($checkstorage -eq $null) {
    Write-Host -ForegroundColor Green "Creating storage account: $storageAccount ..."
    $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
        -Name $storageAccount `
        -SkuName Standard_LRS `
        -Location $LocationName `
}
else {
        Write-Host -ForegroundColor Green "Storage account $storageAccount already exists, continue ..."
}

# Create Storage container or use existing
$storage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccount
$ctx = $storage.Context
$checkContainer = get-AZStorageContainer -Context $ctx -Name $containerName
if ($checkContainer -eq $null) {
    Write-Host -ForegroundColor Green "Creating storage container: $containerName ..."
    New-AzStorageContainer -Name $containerName -Context $ctx -Permission blob
}
else {
        Write-Host -ForegroundColor Green "Storage container $containerName already exists, continue ..."
}

# Create networking
$SingleSubnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix
$Vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $SingleSubnet
$PIP = New-AzPublicIpAddress -Name $PublicIPAddressName -ResourceGroupName $ResourceGroupName -Location $LocationName -AllocationMethod Dynamic
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $Vnet.Subnets[0].Id -PublicIpAddressId $PIP.Id

# Accept purchase plan terms
$agreementTerms=Get-AzMarketplaceterms -Publisher "$publisherName" -Product $offerName -Name $skuName
Set-AzMarketplaceTerms -Publisher $publisherName -Product $offerName -Name $skuName -Terms $agreementTerms -Accept

# Create VM config
$Credential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword);

$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $NIC.Id
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $ComputerName -Credential $Credential
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $version
$vmConfig = Set-AzVMPlan -VM $vmConfig -Publisher $publisherName -Product $offerName -Name $skuName

# Deploy VM
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig -Verbose