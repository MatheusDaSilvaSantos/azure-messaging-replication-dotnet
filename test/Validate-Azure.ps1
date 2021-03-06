# This script is meand to be run as the validation stage of the 
# build process and under an existing Azure PowerShell context.
# This may be provided by the AzurePowerShell task in Azure Pipelines

exit  0

$ErrorActionPreference = "Stop"

function Get-EventHubConnectionString  ([String] $NamespaceName, [String] $EventHubName, [bool] $UseSAS = $true) {
    if ( $UseSAS ) {
        $EventHubNamespace = $(Get-AzResource -resourcetype "Microsoft.EventHub/namespaces" -name $NamespaceName.Split('.')[0])
        $EventHubKeyInfo = $(Get-AzEventHubKey -ResourceGroupName $EventHubNamespace.ResourceGroupName -NamespaceName $EventHubNamespace.Name -EventHubName $EventHubName -AuthorizationRuleName "testapp" -ErrorAction SilentlyContinue)
        if ( -Not $EventHubKeyInfo ) {
            $null = New-AzEventHubAuthorizationRule -ResourceGroupName $EventHubNamespace.ResourceGroupName -NamespaceName $EventHubNamespace.Name -EventHubName $EventHubName -Name "testapp" -Rights "Send", "Listen"
            $EventHubKeyInfo = $(Get-AzEventHubKey -ResourceGroupName $EventHubNamespace.ResourceGroupName -NamespaceName $EventHubNamespace.Name -EventHubName $EventHubName -AuthorizationRuleName "testapp")
        }
        return $EventHubKeyInfo.PrimaryConnectionString
    }
    else {
        return "Endpoint=sb://" + $NamespaceName + "." + $NamespaceDomain + ";EntityPath=" + $EventHubName + ";Authentication='Managed Identity';"    
    }
}

function Get-ServiceBusConnectionString  ([String] $NamespaceName, [String] $QueueName, [bool] $UseSAS = $true) {
    if ( $UseSAS ) {
        $ServiceBusNamespace = $(Get-AzResource -resourcetype "Microsoft.ServiceBus/namespaces" -name $NamespaceName.Split('.')[0])
        $ServiceBusKeyInfo = $(Get-AzServiceBusKey -ResourceGroupName $ServiceBusNamespace.ResourceGroupName -NamespaceName $ServiceBusNamespace.Name -Queue $QueueName -AuthorizationRuleName "testapp" -ErrorAction SilentlyContinue)
        if ( -Not $ServiceBusKeyInfo ) {
            $null = New-AzServiceBusAuthorizationRule -ResourceGroupName $ServiceBusNamespace.ResourceGroupName -NamespaceName $ServiceBusNamespace.Name -Queue $QueueName -Name "testapp" -Rights "Send", "Listen"
            $ServiceBusKeyInfo = $(Get-AzServiceBusKey -ResourceGroupName $ServiceBusNamespace.ResourceGroupName -NamespaceName $ServiceBusNamespace.Name -Queue $QueueName -AuthorizationRuleName "testapp")
        }
        return $ServiceBusKeyInfo.PrimaryConnectionString
    }
    else {
        return "Endpoint=sb://" + $NamespaceName + "." + $NamespaceDomain + ";EntityPath=" + $QueueName + ";Authentication='Managed Identity';"    
    }
}

function Test-EventHubsConfigApp([String] $Location, [String] $RGName) {
    
    Write-Host " - Deploy Event Hubs"
    & "$PSScriptRoot\..\functions\config\EventHubToEventHubCopy\Deploy-Resources.ps1" -ResourceGroupName $RGName -Location $Location -NamespaceName $RGName 
    
    Write-Host " - Build Project"
    & "$PSScriptRoot\..\functions\config\EventHubToEventHubCopy\Build-FunctionApp.ps1" 
    
    Write-Host " - Configure App"
    & "$PSScriptRoot\..\functions\config\EventHubToEventHubCopy\Configure-Function.ps1" -TaskName EventHubAToEventHubB -FunctionAppName $RGName -SourceNamespacename $RGName -SourceEventHubName eventHubA -TargetNamespaceName $RGname -TargetEventHubName eventHubB
    
    Write-Host " - Deploy Function"
    & "$PSScriptRoot\..\functions\config\EventHubToEventHubCopy\Deploy-FunctionApp.ps1" -FunctionAppName $RGName

    Write-Host " - Run Test"
    pushd "$PSScriptRoot\EventHubCopyValidation" > /dev/null
    & ".\bin\Debug\netcoreapp3.1\EventHubCopyValidation.exe" -t "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName eventHubA -UseSAS $true)" -s "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName eventHubB -UseSAS $true)" -et eventHubA -es eventHubB -cg '\$Default' 2>&1 >> "$PSScriptRoot\run.log"
    $result = $LastExitCode 
    popd > /dev/null
    return $result
}

function Test-EventHubsCodeApp([String] $Location, [String] $RGName) {
    Write-Host " - Deploy Event Hubs"
    & "$PSScriptRoot\..\functions\code\EventHubToEventHubCopy\Deploy-Resources.ps1" -ResourceGroupName $RGName -Location $Location -NamespaceName $RGName 
    
    Write-Host " - Configure App"
    & "$PSScriptRoot\..\functions\code\EventHubToEventHubCopy\Configure-Function.ps1" -TaskName Eh1toEh2 -FunctionAppName $RGName -SourceNamespacename $RGName -SourceEventHubName eh1 -TargetNamespaceName $RGname -TargetEventHubName eh2
    
    Write-Host " - Deploy Function"
    & "$PSScriptRoot\..\functions\code\EventHubToEventHubCopy\Deploy-FunctionApp.ps1" -FunctionAppName $RGName

    Write-Host " - Run Test"
    pushd "$PSScriptRoot\EventHubCopyValidation" > /dev/null
    & ".\bin\Debug\netcoreapp3.1\EventHubCopyValidation.exe" -t "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName "eh1" -UseSAS $true)" -s "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName "eh2" -UseSAS $true)" -et eh1 -es eh2 -cg '\$Default' 2>&1 >> "$PSScriptRoot\run.log"
    $result = $LastExitCode 
    popd > /dev/null

    return $result
}

function Test-EventHubsMergeCodeApp([String] $Location, [String] $RGName) {
    Write-Host " - Deploy Event Hubs"
    & "$PSScriptRoot\..\functions\code\EventHubToEventHubMerge\Deploy-Resources.ps1" -ResourceGroupName $RGName -Location $Location -NamespaceName $RGName 
    
    Write-Host " - Configure App"
    & "$PSScriptRoot\..\functions\code\EventHubToEventHubMerge\Configure-Function.ps1" -TaskName Eh1toEh2 -FunctionAppName $RGName -SourceNamespacename $RGName -SourceEventHubName eh1 -TargetNamespaceName $RGname -TargetEventHubName eh2
    & "$PSScriptRoot\..\functions\code\EventHubToEventHubMerge\Configure-Function.ps1" -TaskName Eh2toEh1 -FunctionAppName $RGName -SourceNamespacename $RGName -SourceEventHubName eh2 -TargetNamespaceName $RGname -TargetEventHubName eh1
    
    Write-Host " - Deploy Function"
    & "$PSScriptRoot\..\functions\code\EventHubToEventHubMerge\Deploy-FunctionApp.ps1" -FunctionAppName $RGName

    Write-Host " - Run Test"
    pushd "$PSScriptRoot\EventHubCopyValidation" > /dev/null
    & ".\bin\Debug\netcoreapp3.1\EventHubCopyValidation.exe" -t "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName "eh1" -UseSAS $true)" -s "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName "eh2" -UseSAS $true)" -et eh1 -es eh2 -cg '\$Default' 2>&1 >> "$PSScriptRoot\run.log"
    $result = $LastExitCode 
    if ( $result -ne 0 )
    {
        return $result
    }
    & ".\bin\Debug\netcoreapp3.1\EventHubCopyValidation.exe" -t "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName "eh2" -UseSAS $true)" -s "$(Get-EventHubConnectionString -NamespaceName $RGName -EventHubName "eh1" -UseSAS $true)" -et eh2 -es eh1 -cg '\$Default' 2>&1 >> "$PSScriptRoot\run.log"
    $result = $LastExitCode 
    popd > /dev/null

    return $result
}


function Test-ServiceBusConfigApp([String] $Location, [String] $RGName) {
    
    Write-Host " - Deploy Service Bus"
    & "$PSScriptRoot\..\functions\config\ServiceBusToServiceBusCopy\Deploy-Resources.ps1" -ResourceGroupName $RGName -Location $Location -NamespaceName $RGName 
    
    Write-Host " - Build Project"
    & "$PSScriptRoot\..\functions\config\ServiceBusToServiceBusCopy\Build-FunctionApp.ps1" 
    
    Write-Host " - Configure App"
    & "$PSScriptRoot\..\functions\config\ServiceBusToServiceBusCopy\Configure-Function.ps1" -TaskName QueueAToQueueB -FunctionAppName $RGName -SourceNamespacename $RGName -SourceQueueName queueA -TargetNamespaceName $RGname -TargetQueueName queueB
    
    Write-Host " - Deploy Function"
    & "$PSScriptRoot\..\functions\config\ServiceBusToServiceBusCopy\Deploy-FunctionApp.ps1" -FunctionAppName $RGName

    Write-Host " - Run Test"
    pushd "$PSScriptRoot\ServiceBusCopyValidation" > /dev/null
    & ".\bin\Debug\netcoreapp3.1\ServiceBusCopyValidation.exe" -t "$(Get-ServiceBusConnectionString -NamespaceName $RGName -QueueName queueA -UseSAS $true)" -s "$(Get-ServiceBusConnectionString -NamespaceName $RGName -QueueName queueB -UseSAS $true)" -qt queueA -qs queueB 2>&1 >> "$PSScriptRoot\run.log"
    $result = $LastExitCode 
    popd > /dev/null
    return $result
}

function Test-ServiceBusCodeApp([String] $Location, [String] $RGName) {
    Write-Host " - Deploy Service Bus"
    & "$PSScriptRoot\..\functions\code\ServiceBusToServiceBusCopy\Deploy-Resources.ps1" -ResourceGroupName $RGName -Location $Location -NamespaceName $RGName 
    
    Write-Host " - Configure App"
    & "$PSScriptRoot\..\functions\code\ServiceBusToServiceBusCopy\Configure-Function.ps1" -TaskName QueueAToQueueB -FunctionAppName $RGName -SourceNamespacename $RGName -SourceQueueName queueA -TargetNamespaceName $RGname -TargetQueueName queueB
    
    Write-Host " - Deploy Function"
    & "$PSScriptRoot\..\functions\code\ServiceBusToServiceBusCopy\Deploy-FunctionApp.ps1" -FunctionAppName $RGName

    Write-Host " - Run Test"
    pushd "$PSScriptRoot\ServiceBusCopyValidation" > /dev/null
    & ".\bin\Debug\netcoreapp3.1\ServiceBusCopyValidation.exe" -t "$(Get-ServiceBusConnectionString -NamespaceName $RGName -QueueName queueA -UseSAS $true)" -s "$(Get-ServiceBusConnectionString -NamespaceName $RGName -QueueName queueB -UseSAS $true)" -qt queueA -qs queueB 2>&1 >> "$PSScriptRoot\run.log"
    $result = $LastExitCode 
    popd > /dev/null

    return $result
}

Write-Host "Building Test projects"
pushd "$PSScriptRoot\EventHubCopyValidation" > /dev/null
dotnet build "EventHubCopyValidation.csproj" -c Debug 2>&1 > build.log
popd > /dev/null

pushd "$PSScriptRoot\ServiceBusCopyValidation" > /dev/null
dotnet build "ServiceBusCopyValidation.csproj" -c Debug 2>&1 > build.log
popd > /dev/null

Write-Host "Event Hub Scenario Code/Consumption"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsConsumptionPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-EventHubsCodeApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    exit $result
}

Write-Host "Event Hub Scenario Code/Premium"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsPremiumPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-EventHubsCodeApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    Write-Host "result $result"
    exit $result
}

Write-Host "Event Hub Merge Scenario Code/Consumption"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsConsumptionPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-EventHubsMergeCodeApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    exit $result
}

Write-Host "Event Hub Merge Scenario Code/Premium"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsPremiumPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-EventHubsMergeCodeApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    Write-Host "result $result"
    exit $result
}

Write-Host "Event Hub Scenario Config/Consumption"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsConsumptionPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-EventHubsConfigApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    Write-Host "result $result"
    exit $result
}

Write-Host "Event Hub Scenario Config Premium/Consumption"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsPremiumPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-EventHubsConfigApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    exit $result
}

Write-Host "Service Bus Scenario Config/Consumption"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsConsumptionPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-ServiceBusConfigApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    Write-Host "result $result"
    exit $result
}

Write-Host "Service Bus Scenario Config Premium/Consumption"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsPremiumPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-ServiceBusConfigApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    exit $result
}

Write-Host "Service Bus Scenario Code/Consumption"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsConsumptionPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-ServiceBusCodeApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force

if ( $result -ne 0) {
    exit $result
}

Write-Host "Service Bus Scenario Code/Premium"
$RGName = "msgrepl$(Get-Date -UFormat '%s')"
$Location = "westeurope"
Write-Host " - Create App Host"
& "$PSScriptRoot\..\templates\Deploy-FunctionsPremiumPlan.ps1" -ResourceGroupName $RGName -Location $Location
$result = Test-ServiceBusCodeApp -Location $Location -RGName $RGName
Write-Host " - Undeploy App"
$null = Remove-AzResourceGroup -Name $RGname -Force


exit $result
