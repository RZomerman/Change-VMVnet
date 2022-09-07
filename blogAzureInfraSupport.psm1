

Function hasPublicIP {
    Param (
        [parameter()]
        $ResourceGroupName,
        [parameter()]
        $NICs
    )   
    $set=$false
    ForEach ($nic in $NICs)  {
        If ((Get-AzNetworkInterface -Name $nic -ResourceGroupName $ResourceGroupName).IpConfigurations.PublicIpAddress) {
            $set=$true
        }
    }
    return $set
}

Function PublicIPAddress ([array]$PublicIPAddresses, [string]$LogFile, [string]$Zone){
    write-host (" Checking " + $PublicIPAddresses.Count + " public IP's")
    $NewPublicIPs=[System.Collections.ArrayList]@()

    foreach ($PublicIP in $PublicIPAddresses){
        write-host ("Scanning "+ $PublicIP.PublicIPAddress.id)
        $IPObject=Get-AzResource -ResourceId $PublicIP.PublicIPAddress.id
        $IpAddressConfig=Get-AzPublicIpAddress -Name $IPObject.Name -ResourceGroupName $IPObject.ResourceGroupName 

        if ($IpAddressConfig.sku.Name -eq 'basic' -or $IpAddressConfig.sku.Tier -ne 'Regional' -or $IpAddressConfig.zones.count -ne 3) {
            Writelog ("IP Address is of " + $IpAddressConfig.sku.Name + " type in the " + $IpAddressConfig.sku.Tier + " - deploying new IP address with correct configuration") -LogFile $LogFile

            #Exporting configuration of Public IP address
            [string]$ExportFile=($workfolder + '\' + $IPObject.ResourceGroupName  + '-' + $IpAddressConfig.Name + '.json')
            $Description = "  -Exporting the Public IP JSON Deployment file: $ExportFile "
            $Command = {Export-AzResourceGroup -ResourceGroupName $ResourceGroupName -Resource $IpAddressConfig.id -IncludeParameterDefaultValue -IncludeComments -Force -Path $ExportFile }
            RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"

            $Command=""

            #if DNSSettings where added - will copy and remove from old IP (if DNS based VPN's are used)
            If ( $IpAddressConfig.DnsSettings) {
                Writelog ("DNS Name on IP: " +  $IpAddressConfig.DnsSettings)  -LogFile $LogFile
                $IPDNSConfig=$IpAddressConfig.DnsSettings.DomainNameLabel
                $IpAddressConfig.DnsSettings.DomainNameLabel=$null
                Writelog ("Removing DNS Name from IP")  -LogFile $LogFile
                Set-AzPublicIpAddress -PublicIpAddress $IpAddressConfig
            }
            #setting new name
            $IpAddressNewName=$IpAddressConfig.Name + "_REDUNDANT"
            writelog "Requiring new Public IP address with zone (redundant) configuration for GW deployment"  -LogFile $LogFile

            $ResourceGroupNameForCommand=$IpAddressConfig.ResourceGroupName
            $Location=$IpAddressConfig.Location
            $Command="New-AzPublicIpAddress -Name $IpAddressNewName -ResourceGroupName $ResourceGroupNameForCommand -Location $Location -Sku Standard -Tier Regional -AllocationMethod Static -IpAddressVersion IPv4 -Zone $zone"
            #if DNSSettings where added - will copy and remove from old IP (if DNS based VPN's are used)
            If ( $IpAddressConfig.DnsSettings) {
                Writelog ("DNS Name on IP: " +  $IpAddressConfig.DnsSettings)  -LogFile $LogFile
                $IPDNSConfig=$IpAddressConfig.DnsSettings.DomainNameLabel
                $IpAddressConfig.DnsSettings.DomainNameLabel=$null
                Writelog ("Removing DNS Name from IP")  -LogFile $LogFile
                Set-AzPublicIpAddress -PublicIpAddress $IpAddressConfig
                $Command = $Command + " -DomainNameLabel $IPDNSConfig" 
            }
            If ($IpAddressConfig.Tag){
                writelog "Tags have been found on the original IP - setting same on new IP" -LogFile $LogFile

                $newtag=""
                $TagsOnIP=$IpAddressConfig.Tag
                #open the new tag to add
                $newtag="@{"
                $TagsOnIP.GetEnumerator() | ForEach-Object{
                    $message = '{0}="{1}";' -f $_.key, $_.value
                    $newtag=$newtag + $message
                }
                #removing last semicolon
                $newtag=$newtag.Substring(0,$newtag.Length-1)
                #closing newtag value
                $newtag=$newtag +"}"

                #@{key0="value0";key1=$null;key2="value2"}
                $Command=$Command + " -tag $newtag"
            }

            write-host "2"
            
            $ConfigToAdd=($ResourceGroupNameForCommand + "\"+ $IpAddressNewName)
            write-host "Adding: " $ConfigToAdd
            [void]$NewPublicIPs.add($ConfigToAdd)  
            
            $Command = [Scriptblock]::Create($Command)
            $Description = "  -Creating new Public IP"
            writelog "Deploying new Public IP address with correct information"  -LogFile $LogFile
            Write-host $Command
            RunLog-Command -Description $Description -Command $Command -LogFile $LogFile -Color "Green"
        }
    }
 
    return $NewPublicIPs
}

Function GetPublicIPAddresses([array]$PublicIPAddresses, [string]$LogFile){
    write-host (" Checking " + $PublicIPAddresses.Count + " public IP's")
    [array]$NewPublicIPIDs=@()
    foreach ($PublicIP in $PublicIPAddresses){
        #ResourceGroup\IPName
        $PublicIP=$PublicIP.split("\")
        $IpAddressConfig=Get-AzPublicIpAddress -ResourceGroupName $PublicIP[0] -Name $PublicIP[1]
        $IPAddress=$IpAddressConfig.IpAddress
        Write-host "*************************************************************"
        writelog ("  New Public IP address for VPN: " + $IPAddress)  -LogFile $LogFile -color Yellow
        write-host "  - please update your on-premises VPN device" -ForegroundColor Yellow
        Write-host "*************************************************************"
        $IPAddressID=$IPObject.Id
        $NewPublicIPIDs += $IPAddressID
    } 
    return $NewPublicIPIDs
}
#Functions
Function RunLog-Command([string]$Description, [ScriptBlock]$Command, [string]$LogFile, [string]$Color){
    If (!($Color)) {$Color="Yellow"}
    Try{
        $Output = $Description+'  ... '
        Write-Host $Output -ForegroundColor $Color
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S] ") + $Output) | Out-File -FilePath $LogFile -Append -Force
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S] ") + $Command) | Out-File -FilePath $LogFile -Append -Force
        $Result = Invoke-Command -ScriptBlock $Command 
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        $Output = 'Error '+$ErrorMessage
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S] ") + $Output) | Out-File -FilePath $LogFile -Append -Force
        $Result = ""
    }
    Finally {
        if ($ErrorMessage -eq $null) {
            $Output = "[Completed]  $Description  ... "} else {$Output = "[Failed]  $Description  ... "
        }
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S] ") + $Output) | Out-File -FilePath $LogFile -Append -Force
    }
    Return $Result
}


Function WriteLog([string]$Description, [string]$LogFile, [string]$Color){
    If (!($Color)) {$Color="Yellow"}
    Try{
        $Output = $Description+'  ... '
        Write-Host $Output -ForegroundColor $Color
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S] ") + $Output) | Out-File -FilePath $LogFile -Append -Force
        #$Result = Invoke-Command -ScriptBlock $Command 
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        $Output = 'Error '+$ErrorMessage
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S] ") + $Output) | Out-File -FilePath $LogFile -Append -Force
        $Result = ""
    }
    Finally {
        if ($ErrorMessage -eq $null) {
            $Output = "[Completed]  $Description  ... "} else {$Output = "[Failed]  $Description  ... "
        }
        ((Get-Date -UFormat "[%d-%m-%Y %H:%M:%S] ") + $Output) | Out-File -FilePath $LogFile -Append -Force
    }
    Return $Result
}
    
    
Function LogintoAzure(){
    $Error_WrongCredentials = $True
    $AzureAccount = $null
    while ($Error_WrongCredentials) {
        Try {
            Write-Host "Info : Please, Enter the credentials of an Admin account of Azure" -ForegroundColor Cyan
            #$AzureCredentials = Get-Credential -Message "Please, Enter the credentials of an Admin account of your subscription"      
            $AzureAccount = Add-AzAccount

            if ($AzureAccount.Context.Tenant -eq $null) 
                        {
                        $Error_WrongCredentials = $True
                        $Output = " Warning : The Credentials for [" + $AzureAccount.Context.Account.id +"] are not valid or the user does not have Azure subscriptions "
                        Write-Host $Output -BackgroundColor Red -ForegroundColor Yellow
                        } 
                        else
                        {$Error_WrongCredentials = $false ; return $AzureAccount}
            }

        Catch {
            $Output = " Warning : The Credentials for [" + $AzureAccount.Context.Account.id +"] are not valid or the user does not have Azure subscriptions "
            Write-Host $Output -BackgroundColor Red -ForegroundColor Yellow
            Generate-LogVerbose -Output $logFile -Message  $Output 
            }

        Finally {
                }
    }
    return $AzureAccount

}
    
Function Select-Subscription ($SubscriptionName, $AzureAccount){
            Select-AzSubscription -SubscriptionName $SubscriptionName -TenantId $AzureAccount.Context.Tenant.TenantId
}


Function LoadModule{
    param (
        [parameter(Mandatory = $true)][string] $name
    )
    $retVal = $true
    if (!(Get-Module -Name $name)){
        $retVal = Get-Module -ListAvailable | where { $_.Name -eq $name }
        if ($retVal) {
            try {
                Import-Module $name -ErrorAction SilentlyContinue
            }
            catch {
                $retVal = $false
            }
        }
    }
    return $retVal
}

Function StopAZVM ($VMObject, $LogFile){  
    $VMstate = (Get-AzVM -ResourceGroupName $VMObject.ResourceGroupName -Name $VMObject.Name -Status).Statuses[1].code
    $Description = "   >Stopping the VM "
    if ($VMstate -ne 'PowerState/deallocated' -and $VMstate -ne 'PowerState/Stopped')
    {   
        $Command = { $VmObject | Stop-AzVM -Force | Out-Null}
        RunLog-Command -Description $Description -Command $Command -LogFile $LogFile
        return $true
    }else{
        $Description =  "  >VM in Stopped/deallocated state already"
        RunLog-Command -Description $Description -Command $Command -LogFile $LogFile
        return $false
    }
}