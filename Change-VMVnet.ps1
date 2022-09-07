[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,Position=2)]
   [string]$VMName,
   [Parameter(Mandatory=$True,Position=3)]
   [string]$TargetVnet,
   [Parameter(Mandatory=$True,Position=1)]
   [string]$ResourceGroup,
   [Parameter(Mandatory=$False,Position=4)]
   [string]$TargetSubnet,
   [Parameter(Mandatory=$False)]
   [string]$TargetVnetResourceGroup,
   [Parameter(Mandatory=$False)]
   [boolean]$Login,
   [Parameter(Mandatory=$False)]
   [boolean]$SelectSubscription,
   [Parameter(Mandatory=$False)]
   [boolean]$Report,
   [Parameter(Mandatory=$False)]
   [boolean]$Force
)


write-host ""
write-host ""
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true
#Cosmetic stuff
write-host ""
write-host ""
write-host "                               _____        __                                " -ForegroundColor Green
write-host "     /\                       |_   _|      / _|                               " -ForegroundColor Yellow
write-host "    /  \    _____   _ _ __ ___  | |  _ __ | |_ _ __ __ _   ___ ___  _ __ ___  " -ForegroundColor Red
write-host "   / /\ \  |_  / | | | '__/ _ \ | | | '_ \|  _| '__/ _' | / __/ _ \| '_ ' _ \ " -ForegroundColor Cyan
write-host "  / ____ \  / /| |_| | | |  __/_| |_| | | | | | | | (_| || (_| (_) | | | | | |" -ForegroundColor DarkCyan
write-host " /_/    \_\/___|\__,_|_|  \___|_____|_| |_|_| |_|  \__,_(_)___\___/|_| |_| |_|" -ForegroundColor Magenta
write-host "     "
write-host " This script reconfigures a VM to a net VNET and subnet" -ForegroundColor "Green"

#Importing the functions module and primary modules for AAD and AD


If (!((Get-Module -name Az.Compute -ListAvailable))){
    Write-host "Az.Compute Module was not found - cannot continue - please install the module using install-module AZ"
    Exit
}

If (Get-Module -name blogAzureInfraSupport ){
    Write-host "Reloading blogAzureInfraSupport module file"
    remove-module blogAzureInfraSupport
}

Import-Module .\blogAzureInfraSupport.psm1 -DisableNameChecking

##Setting Global Paramaters##
$ErrorActionPreference = "Stop"
$date = Get-Date -UFormat "%Y-%m-%d-%H-%M"
$workfolder = Split-Path $script:MyInvocation.MyCommand.Path
$logFile = $workfolder+'\ChangeSize'+$date+'.log'
    Write-Output "  - Steps will be tracked in log file : [ $logFile ]" 

##Login to Azure##
If ($Login) {
    $Description = "  -Connecting to Azure"
    $Command = {LogintoAzure}
    $AzureAccount = RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"
}

#Retrieve info on VM
$vmObject=get-azvm -resourcegroupname $ResourceGroup -Name $VMName

If (!($vmObject)) {
    WriteLog "Target VM does not exist, cannot move" -LogFile $LogFile -Color "Red" 
        exit
}

#Validate if target VNET and subnet exists and there is space on the subnet for the move
    If ($TargetVnetResourceGroup) {
        $VnetRSG=$TargetVnetResourceGroup
    }else{
        $VnetRSG=$ResourceGroup
    }
    $TargetVnetObject=Get-AzVirtualNetwork -ResourceGroupName $VnetRSG -Name $TargetVnet -ErrorAction Continue
    If (!($TargetVnetObject)) {
        Write-Error ("Could not find " + $targetvnet + " please check again")
        exit
    }
    If (!($TargetVnetObject.Location.toUpper() -eq $vmobject.Location.toUpper())) {
        Write-Error ("Target vnet " + $targetvnet + " is not in the same region as the VM")
        exit
    }
    
    #Validating Subnet existence
    If (!(Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $TargetVnetObject -name $TargetSubnet)) {
        Write-Error ("Could not find " + $TargetSubnet + " please check again")
        exit
    }

#Need to get information on the object - this includes - Public IP address configuration and disk information
#Each VM can have one or multiple NIC's which we need to query independently
writelog "  - Retrieving Network Interface information" -logFile $logFile -Color Green
If ($vmObjectNetworkProfile.NetworkInterfaces.id.count -gt 1) {
    Write-Error ("Too many NIC's on this VM - this script only supports single NIC VM's")
    exit
}
    $NICObject=Get-AzNetworkInterface -ResourceId $vmObject.NetworkProfile.NetworkInterfaces.id
    #Checking for public IP's (if so need to create new one)
    If ($NICObject.IpConfigurations[0].publicIpaddress) {
        WriteLog ("  - Public IP on this VM - this script only supports non-public IP VM's") -logFile $logFile -color Yellow
        if (!($force)) {
            Write-Host "specify -force '$true' to continue losing the Public IP"
            exit
        }else{
            WriteLog ("  -  -Force has been appended - continuing") -logFile $logFile -color Yellow
        }
    }

    #building ID for target
    $SubnetConfig=Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $TargetVnetObject -name $TargetSubnet
    

#Exporting the VM object to a JSON file - for backup purposes -- main file and actual deployment file
    write-host ""
    Write-host "Exporting JSON backup for the VM - This allows the VM to be easily re-deployed back to original state in case something goes wrong" -ForegroundColor Yellow
    Write-host "if so, please run new-AzResourceGroupDeployment -Name <deploymentName> -ResourceGroup <ResourceGroup> -TemplateFile .\<filename>" -ForegroundColor Yellow
    write-host ""
    $Filename=($ResourceGroup + "-" + $VMName)
    $Command = {ConvertTo-Json -InputObject $vmObject -Depth 100 | Out-File -FilePath $workfolder'\'$Filename'-Object.json'}
    RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"

    $VMBackupObject=$VMObject
    $VMBackupObject.StorageProfile.OsDisk.CreateOption = 'Attach'
    If ($VMBackupObject.StorageProfile.DataDisks.Count -gt 1) {
        for ($s=1;$s -le $VMBackupObject.StorageProfile.DataDisks.Count ; $s++ ){
            $VMBackupObject.StorageProfile.DataDisks[$s-1].CreateOption = 'Attach'
        }
    }
    $VMBackupObject.OSProfile = $null
    $VMBackupObject.StorageProfile.ImageReference = $null
    $Description = "  - Creating the VM Emergency restore file : EmergencyRestore-$ResourceGroup-$VMName.json "
    $Command = {ConvertTo-Json -InputObject $VMBackupObject -Depth 100 | Out-File -FilePath 'EmergencyRestore-'$workfolder'\'$ResourceGroup-$VMName'.json'}
    RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"

#Exporting object file to be reimported later and for adjustments if required prior to deployment
    [string]$VMExportFile=($workfolder + '\' + $ResourceGroup + '-' + $VMName + '.json')
    $Description = "  - Exporting the VM JSON Deployment file: $VMExportFile "
    $Command = {Export-AzResourceGroup -ResourceGroupName $ResourceGroup -Resource $vmObject.id -IncludeParameterDefaultValue -IncludeComments -Force -Path $VMExportFile }
    RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"


#Shutting down VM to ensure data integrity
writelog "  - Stopping VM for data integrity" -logFile $logFile -Color Green
Stop-AzVM -ResourceGroupName $resourcegroup -Name $VMname -Force | Out-Null


    #Creating a new NIC with new configurations
    $NewIpConfig = New-AzNetworkInterfaceIpConfig -Subnet $SubnetConfig -Name "ipconfig" -Primary
    $NewNicName=($NICObject.name + "z")
    $NewNic = New-AzNetworkInterface -Name $NewNicName -ResourceGroupName $ResourceGroup -Location $vmObject.Location -IpConfiguration $NewIpConfig -Force

    $newnic.DnsSettings = $NICObject.DnsSettings
    $newnic.EnableAcceleratedNetworking = $NICObject.EnableAcceleratedNetworking
    $newnic.EnableIPForwarding = $NICObject.EnableIPForwarding
    $newnic.Tag = $NICObject.Tag

    $newnic2=Set-AzNetworkInterface -NetworkInterface $newnic
    

writelog "  - Setting deployment options" -logFile $logFile -Color Green
#Setting configuration for new deployment
    writelog "   >Setting network configuration" -LogFile $LogFile    
    $vmObject.NetworkProfile.NetworkInterfaces[0].id = $newnic.id

    writelog "   >Setting storage configuration" -LogFile $LogFile
    $VmObject.OSProfile = $null
    $VmObject.StorageProfile.ImageReference = $null
    $VmObject.StorageProfile.OsDisk.CreateOption = 'Attach'
    if ($VmObject.StorageProfile.OsDisk.Image) {
        writelog "   >Resetting reference image" -LogFile $LogFile
        $VmObject.StorageProfile.OsDisk.Image = $null
    }

    If ($VmObject.StorageProfile.DataDisks.Count -gt 1) {
        for ($s=1;$s -le $VmObject.StorageProfile.DataDisks.Count ; $s++ ){
            $VmObject.StorageProfile.DataDisks[$s-1].CreateOption = 'Attach'
            writelog "   >Setting disks to attach" -LogFile $LogFile
        }
    }

    
    If ($VMSize){
        writelog ("   >Setting VMSize to" + $VMSize) -LogFile $LogFile
        $VmObject.HardwareProfile.VmSize = $VMSize
    }

#Redeploying VM
    $VMName=$VmObject.Name 
    $Description = "   -Recreating the Azure VM: (Step 1 : Removing the VM...) "
    $Command = {Remove-AzVM -Name $VmObject.Name -ResourceGroupName $VmObject.ResourceGroupName -Force | Out-null}
    RunLog-Command -Description $Description -Command $Command -LogFile $LogFile
    
    #Write-host "  -Waiting for 5 seconds to backend to sync" -ForegroundColor Yellow
    Start-sleep 5
    
    
    $Description = "   -Recreating the Azure VM: (Step 2 : Deploying the VM...) "
    $Command = {New-AZVM -ResourceGroupName $VmObject.ResourceGroupName -Location $VmObject.Location -VM $VmObject | Out-Null}
    RunLog-Command -Description $Description -Command $Command -LogFile $LogFile
