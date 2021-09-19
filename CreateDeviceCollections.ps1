<#
V2020.02.07 by merlinfrombelgium
- Fixed some typos and grammar
- Fixed WMI queries to 'select distinct' instead of just 'select'. This returned an array of ProductIDs, where only one is wanted.
- Removed @initParams from CM module import as it was never initialized.
- Added Sort-Object before Out-GridView to make list of Manufacturers and Models easier to read.

V2020.01.27
Updated Script to Create "Operational" Folder and then move newly created Collections there.
Borrowed Code from Benoit Lecours
Made script pull addtional info dynamic, you shouldn't have to make any environmental chanages for script to work.
Script now also creates an "All Workstation" Collection and uses that as the limiting collection, unless one with that name already exist, then uses that.
    Change the Limiting Collection info by updating: $LimitingCollection
You can easily modify the Collection Prefix now by changing these below:
    $ModelColPrefix = "ModelCol"
    $ManufacturerColPreFix = "ManufacturerCol"

v2020.01.15 - Initial Release
Script "Scans" the Site Server's WMI for Device Manufacturer and Model info, then prompts for you to pick & choose what collections you'd like created.

REQUIREMENTS: 
    Run Script from Machine that has the Console Installed
    Run with account that has rights to perform actions in ConfigMgr
    HP: Hardware Inventory includes Baseboard: Product
    Lenovo: Hardware Inventory includes ComputerSystemProduct: Name & Version
    please follow this post to enable the additional info for Hardware Inventory: https://www.recastsoftware.com/blog/enable-product-in-win32-baseboard-for-hardware-inventory

References & Additional Credits:
Borrowed code for making Operational Folder and moving Collections from: https://gallery.technet.microsoft.com/Set-of-Operational-SCCM-19fa8178 (Benoit Lecours)


KNOWN BUGS (Unknown how to fix)
If you re-run the script after you've already run it, and you only select one model from the options, you'll get some odd output.  Guessing the previous run's variables aren't cleared and causing this, but just haven't tracked it down.

DESIRED CHANGES
- Use CIM rather than WIM and PowerShell cmdlets for ConfigMgr (see https://github.com/saladproblems/CCM-Core)
- Optimize code for performance
- Create Functions and implement proper code formatting (params, description, help)

#>

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" 
}

#Get SiteCode
$SiteCode = Get-PSDrive -PSProvider CMSITE
$ProviderMachineName = (Get-PSDrive -PSProvider CMSITE).Root
Set-location $SiteCode":"

#Create Default Folder "Operational"
$CollectionFolder = @{Name ="Operational"; ObjectType =5000; ParentContainerNodeId =0}
if ((Get-CimInstance -Namespace "root\sms\site_$($SiteCode.Name)" -Class "SMS_ObjectContainerNode"-ComputerName $SiteCode.Root).Name -contains "Operational"){}
Else{Set-WmiInstance -Namespace "root\sms\site_$($SiteCode.Name)" -Class "SMS_ObjectContainerNode" -Arguments $CollectionFolder -ComputerName $SiteCode.Root |Out-Null}
$FolderPath =($SiteCode.Name +":\DeviceCollection\" + $CollectionFolder.Name)


#Start Custom Script Vars
$ModelColPrefix = "ModelCol"
$ManufacturerColPreFix = "ManufacturerCol"
$Models = $Null
$Model = $Null
$MachineDatabase = @()
$LimitingCollection = "All Workstations"  #Creates this later if does not exist
$CreateManufacturersCollections = $true
$CreateModelCollections = $true

#Set Schedule to Evaluate Weekly (from the time you run the script)
$Schedule = New-CMSchedule -Start (Get-Date).DateTime -RecurInterval Days -RecurCount 7


#Confirm All Workstation Collection, or create it if needed
$AllWorkstationCollection = Get-CMCollection -Name $LimitingCollection
if ($AllWorkstationCollection -eq $Null)
    {
$CollectionQueryAllWorkstations = @"
select SMS_R_System.Name from  SMS_R_System where SMS_R_System.OperatingSystemNameandVersion like "Microsoft Windows NT Workstation%"
"@     
    
    New-CMDeviceCollection -Name $LimitingCollection -Comment "Collection of all workstation machines" -LimitingCollectionName "All Systems" -RefreshSchedule $Schedule -RefreshType 2 |Out-Null
    Add-CMDeviceCollectionQueryMembershipRule -RuleName "All Workstations" -CollectionName $LimitingCollection -QueryExpression $CollectionQueryAllWorkstations | Out-Null
    $AllWorkstationCollection = Get-CMCollection -Name $LimitingCollection
    Write-Host "Created All Workstations Collection ID: $($AllWorkstationCollection.CollectionID), which will be used as the limiting collections moving forward" -ForegroundColor Green
    }
else {Write-Host "Found All Workstations Collection ID: $($AllWorkstationCollection.CollectionID), which will be used as the limiting collections moving forward" -ForegroundColor Green}


#Start Populating $MachineDatabase Array with the Models you select

#Pick from Manufacturers
$query = @"
select DISTINCT SMS_G_System_COMPUTER_SYSTEM.Manufacturer FROM SMS_G_System_COMPUTER_SYSTEM
"@
$Manufs = (Get-WmiObject -ComputerName $ProviderMachineName -Namespace "ROOT\SMS\site_$SiteCode" -Query $query).Manufacturer | Sort-Object Manufacturer | Out-GridView -title "Select the Manufacturers which have models you wish to create Collections for" -PassThru


#Create Model Collections Area
if ($CreateModelCollections -eq $true)
    {
    #Pick Models from those Manufacturers
    foreach ($Manuf in $Manufs)
        {
        if ($Manuf -match "Len*")
            {

        $query = @"
select DISTINCT SMS_G_System_COMPUTER_SYSTEM_PRODUCT.Version FROM SMS_G_System_COMPUTER_SYSTEM_PRODUCT
"@

        $Models += (Get-WmiObject -ComputerName $ProviderMachineName -Namespace "ROOT\SMS\site_$SiteCode" -Query $query | Where-Object {$_.Version -Match "Leno"}).Version | Sort-Object Version | Out-GridView -title "Select the $Manuf Models you wish to create Collections for" -PassThru
            }

        else
            {
        
        $query = @"
select DISTINCT SMS_G_System_COMPUTER_SYSTEM.Model FROM SMS_G_System_COMPUTER_SYSTEM
where SMS_G_System_COMPUTER_SYSTEM.Manufacturer = "$Manuf"
"@
        $Models += (Get-WmiObject -ComputerName $ProviderMachineName -Namespace "ROOT\SMS\site_$SiteCode" -Query $query).Model | Sort-Object Model | Out-GridView -title "Select the $Manuf Models you wish to create Collections for" -PassThru
            }
        }


#Build the Database Array, going model by model
    foreach ($model in $Models)
        {
        $ProductID = $null
        #Add Manufacturer info to the Model in the Arrary    
        $query = @"
select DISTINCT SMS_G_System_COMPUTER_SYSTEM.Manufacturer FROM SMS_G_System_COMPUTER_SYSTEM where SMS_G_System_COMPUTER_SYSTEM.Model = "$model"
"@
        if ($Model -match "Len*"){$Manufacturer = "Lenovo"}
        else{$Manufacturer = (Get-WmiObject -ComputerName $ProviderMachineName -Namespace "ROOT\SMS\site_$SiteCode" -Query $query).Manufacturer}

        #Add Product Info to the Model in the Arrary
        if ($Model -match "Len*")
        {
        $query = @"
select SMS_G_System_COMPUTER_SYSTEM_PRODUCT.Name FROM SMS_G_System_COMPUTER_SYSTEM_PRODUCT
where SMS_G_System_COMPUTER_SYSTEM_PRODUCT.Version = "$model"
"@
        $ProductID = (Get-WmiObject -ComputerName $ProviderMachineName -Namespace "ROOT\SMS\site_$SiteCode" -Query $query).Name
        }
        Else
        {
        $query = @"
select SMS_G_System_BASEBOARD.Product FROM SMS_G_System_BASEBOARD
LEFT JOIN SMS_G_System_COMPUTER_SYSTEM ON SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_G_System_BASEBOARD.ResourceID
where SMS_G_System_COMPUTER_SYSTEM.Model = "$model"
"@
        $ProductID = (Get-WmiObject -ComputerName $ProviderMachineName -Namespace "ROOT\SMS\site_$SiteCode" -Query $query).Product
        }
        
        
        #Take the Items and place in PS Object    
        $MachineDatabaseObject = New-Object PSObject -Property @{
            Manufacturer     = $Manufacturer
            Model            = $Model
            ProductID        = $ProductID
            }
        #Take the PS Object and append the Database Array    
        $MachineDatabase += $MachineDatabaseObject
        }


    #Start Building Required components to create Collections

    foreach ($Machine in $MachineDatabase)
        {
        $ColModel = $Machine.Model
        $ColProductID = $Machine.ProductID | select -Unique
        $ColManufacturer = $Machine.Manufacturer
        #Standardize Dell & HP Manufacturer Names
        #Set $Collection Name to ModelCol - Manufauturer - Model (or similar variation for HP)
        if ($ColManufacturer -like "De*") {$ColManufacturer = "Dell"}
        if ($ColManufacturer -like "H*") 
            {
            $ColManufacturer = "HP"
            $CollectionName = "$ModelColPrefix - $ColModel - $ColProductID"
            $Comment = "Requires Win32_BaseBoard.Product in Inventory: https://www.recastsoftware.com/blog/enable-product-in-win32-baseboard-for-hardware-inventory"
            }
        elseif ($ColManufacturer -like "Leno*")
            {
            $CollectionName = "$ModelColPrefix - $ColModel - $ColProductID"
            $Comment = "Requires Win32_ComputerSystemProduct.Name & .Version in Inventory: https://www.recastsoftware.com/blog/enable-product-in-win32-baseboard-for-hardware-inventory"
            }
        else 
            {
            $CollectionName = "$ModelColPrefix - $ColManufacturer $ColModel"
            $Comment = "No Comment"
            }


        #Collection Query based on Product ID (HP)
        $CollectionQueryProduct = @"
select SMS_R_System.Name FROM SMS_R_System
INNER JOIN SMS_G_System_BASEBOARD ON SMS_G_System_BASEBOARD.ResourceID = SMS_R_System.ResourceID
WHERE SMS_G_System_BASEBOARD.Product = "$ColProductID"
"@ 
        #Collection Query based on Model (Lenovo)
        $CollectionQueryName = @"
select SMS_R_System.Name FROM SMS_R_System
INNER JOIN SMS_G_System_COMPUTER_SYSTEM_PRODUCT ON SMS_G_System_COMPUTER_SYSTEM_PRODUCT.ResourceID = SMS_R_System.ResourceID
WHERE SMS_G_System_COMPUTER_SYSTEM_PRODUCT.Name = "$ColProductID"
"@   

        #Collection Query based on Model (Dell & Etc)
        $CollectionQueryModel = @"
select SMS_R_System.Name FROM SMS_R_System
INNER JOIN SMS_G_System_COMPUTER_SYSTEM ON SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceID
WHERE SMS_G_System_COMPUTER_SYSTEM.Model = "$ColModel"
"@   
        
        #Create Model Collections
        $CurrentCollectionID = (Get-CMCollection -Name $CollectionName).CollectionID
        if ($CurrentCollectionID -eq $null)
            {
            Write-Host "Creating Collection: $CollectionName" -ForegroundColor Green
            New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $LimitingCollection -RefreshSchedule $Schedule -RefreshType Periodic -Comment $Comment | Out-Null 
            if ($ColManufacturer -like "H*") 
                {
                Write-host "Using Baseboard $ColProductID" -ForegroundColor Green
                Add-CMDeviceCollectionQueryMembershipRule -RuleName "Query $ColModel" -CollectionName $CollectionName -QueryExpression $CollectionQueryProduct | Out-Null
                }
            elseif ($ColManufacturer -like "Len*") 
                {
                Write-host "Using Product $ColProductID" -ForegroundColor Green
                Add-CMDeviceCollectionQueryMembershipRule -RuleName "Query $ColProductID" -CollectionName $CollectionName -QueryExpression $CollectionQueryName | Out-Null
                }
             else
                {
                Write-host "Using Model $ColModel" -ForegroundColor Green
                Add-CMDeviceCollectionQueryMembershipRule -RuleName "Query $ColModel" -CollectionName "$CollectionName" -QueryExpression $CollectionQueryModel | Out-Null
                }
            Write-Host "New Collection Created with Name: $CollectionName & ID: $((Get-CMCollection -Name $CollectionName).CollectionID)" -ForegroundColor Green
            Move-CMObject -FolderPath $FolderPath -InputObject $(Get-CMDeviceCollection -Name $CollectionName)
            Write-host *** Collection $CollectionName moved to $CollectionFolder.Name folder***
            }
        Else{Write-Host "Collection: $CollectionName already exist with ID: $CurrentCollectionID" -ForegroundColor Yellow}
        Write-Host "-----" -ForegroundColor DarkGray
        }

    }

if ($CreateManufacturersCollections -eq $true)
    {
    foreach ($Manuf in $Manufs)
        {
        #Set Manufacturer for use in Query
        $ColManufacturer = $Manuf
        if ($ColManufacturer -like "H*"){$ColManufacturer = "H"}
        if ($ColManufacturer -like "Dell*"){$ColManufacturer = "Dell"}
        else {$ColManufacturer = $Manuf.Substring(0,$Manuf.Length-1)}

    $CollectionQueryManufacturer = @"
select SMS_R_SYSTEM.Name from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_COMPUTER_SYSTEM.Manufacturer like "$($ColManufacturer)%"
"@ 
        
        #Set Manufacturer for use in Collection Name
        $ColManufacturer = $Manuf
        if ($ColManufacturer -like "H*"){$ColManufacturer = "HP"}
        if ($ColManufacturer -like "Dell*"){$ColManufacturer = "Dell"}
        if ($ColManufacturer -like "LEN*"){$ColManufacturer = "Lenovo"}
        
        #Start Creation of ManufacturerCollection
        $CollectionName = "$ManufacturerColPreFix - $ColManufacturer Machines"
        $CurrentCollectionID = (Get-CMCollection -Name $CollectionName).CollectionID
        if ($CurrentCollectionID -eq $null)
            {
            Write-Host "Creating Collection: $CollectionName" -ForegroundColor Green
            New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $LimitingCollection -RefreshSchedule $Schedule -RefreshType Periodic | Out-Null
            Add-CMDeviceCollectionQueryMembershipRule -RuleName "Query $ColManufacturer" -CollectionName "$CollectionName" -QueryExpression $CollectionQueryManufacturer | Out-Null
            Write-Host "New Collection Created with Name: $CollectionName & ID: $((Get-CMCollection -Name $CollectionName).CollectionID)" -ForegroundColor Green
            Move-CMObject -FolderPath $FolderPath -InputObject $(Get-CMDeviceCollection -Name $CollectionName)
            Write-host *** Collection $CollectionName moved to $CollectionFolder.Name folder***
            }
        Else{Write-Host "Collection: $CollectionName already exsit with ID: $CurrentCollectionID" -ForegroundColor Yellow}
        Write-Host "-----" -ForegroundColor DarkGray
        }
    }
