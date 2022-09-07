# Change-VMVnet

This script changes the VNET configuration for a VM - simple VM's only - 
download both files and put them in a directory on your computer - or upload them directly into Azure PowerShell CloudShell

>invoke-webrequest -uri https://raw.githubusercontent.com/RZomerman/Change-VMVnet/main/Change-VMVnet.ps1 -outfile Change-VMVnet.ps1
>invoke-webrequest -uri https://raw.githubusercontent.com/RZomerman/Change-VMVnet/main/blogAzureInfraSupport.psm1 -outfile blogAzureInfraSupport.psm1

next; 
run the script with the following parameters
> ./Change-VMVnet.ps1 -vmname vm1 -ResourceGroup RSGname -TargetSubnet subnet -targetvnet vnet_uae
 
 optionally you can add the vnet resource group (if not in same location as VM)
 > ./Change-VMVnet.ps1 -vmname vm1 -ResourceGroup RSGname -TargetSubnet subnet -targetvnet vnet_uae -TargetVnetResourceGroup Networking
  
  by default - VM's with Public IP's will be skipped - but you can override this with a -Force parameter (this will remove the Public IP)
 > ./Change-VMVnet.ps1 -vmname vm1 -ResourceGroup RSGname -TargetSubnet subnet -targetvnet vnet_uae -TargetVnetResourceGroup Networking -Force
