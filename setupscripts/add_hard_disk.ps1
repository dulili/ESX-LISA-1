###############################################################################
##
## Description:
##   This script will add hard disk to VM
##
###############################################################################
##
## Revision:
## v1.0.0 - xuli - 01/16/2017 - Draft script for add hard disk.
## v1.0.1 - ruqin - 07/11/2018 - Add a IDE hard disk support
## v1.1.0 - boyang - 08/06/2018 - Fix a return value can't be converted by Invoke-Expression
###############################################################################
<#
.Synopsis
    This script will add hard disk to VM.

.Description
    The script will create .vmdk file, and attach to VM directlly.
    The .xml entry to specify this startup script would be:
    <setupScript>SetupScripts\add_hard_disk.ps1</setupScript>

   The scripts will always pass the vmName, hvServer, and a
   string of testParams from the test definition separated by
   semicolons. The testParams for this script identify DiskType, CapacityGB,
   StorageFormat.

   Where
        DiskType - IDE or SCSI
        StorageFormat - The format of new hard disk, can be (Thin, Thick,
        EagerZeroedThick)
        CapacityGB - Capacity of the new virtual disk in gigabytes

    A typical XML definition for this test case would look similar
    to the following:

    <test>
        <testName>HotAdd_SCSI_Dynamic</testName>
        <testID>ESX-STOR-001</testID>
        <setupScript>SetupScripts\add_hard_disk.ps1</setupScript>
        <testScript>stor_lis_disk.sh</testScript>
        <files>remote-scripts/stor_lis_disk.sh,remote-scripts/utils.sh,
        remote-scripts/stor_utils.sh </files>
        <cleanupScript>SetupScripts\remove_hard_disk.ps1</cleanupScript>
        <timeout>18000</timeout>
        <testparams>
            <param>DiskType=SCSI</param>
            <param>StorageFormat=Thin</param>
            <param>CapacityGB=3</param>
        </testparams>
        <onError>Continue</onError>
    </test>

.Parameter vmName
    Name of the VM to add disk.

.Parameter hvServer
    Name of the ESXi server hosting the VM.

.Parameter testParams
    Test data for this test case

.Example
    setupScripts\add_hard_disk
#>
param ([String] $vmName, [String] $hvServer, [String] $testParams)


# Source the tcutils.ps1 file
. .\setupscripts\tcutils.ps1


############################################################################
#
# Main entry point for script
#
############################################################################


# Check input arguments
if ($vmName -eq $null -or $vmName.Length -eq 0) {
    Write-Host "Error: VM name is null"
    return $False
}

if ($testParams -eq $null -or $testParams.Length -lt 3) {
    Write-Host "Error: No testParams provided"
    Write-Host "Script Add_hard_disk.ps1 requires these test params"
    return $False
}


# Parse the testParams string
$params = $testParams.TrimEnd(";").Split(";")
$diskType = $null
$storageFormat = $null
$capacityGB = $null


#
# Support to add more disks for same size, e.g. DiskType0,StorageFormat0,
# DiskType1,StorageFormat1,CapacityGB
#
[int]$max = 0
$setIndex = $null
foreach ($p in $params) {
    $fields = $p.Split("=")
    $value = $fields[0].Trim()
    switch -wildcard ($value) {
        "DiskType?" { $setIndex = $value.substring(8) }
        "StorageFormat?" { $setIndex = $value.substring(13) }
        default {}  # unknown param - just ignore it
    }

    if ([int]$setIndex -gt $max -and $null -ne $setIndex) {
        $max = [int]$setIndex
    }
}

for ($pair = 0; $pair -le $max; $pair++) {
    foreach ($p in $params) {
        $fields = $p.Split("=")
        $value = $fields[1].Trim()
        switch ( $fields[0].Trim() ) {
            "DiskType$pair" { $diskType = $value }
            "StorageFormat$pair" { $storageFormat = $value }
            "DiskType" { $diskType = $value }
            "StorageFormat" { $storageFormat = $value }
            "CapacityGB" { $capacityGB = $value }
            default {}  # unknown param - just ignore it
        }
    }

    if (@("Thin", "Thick", "EagerZeroedThick") -notcontains $storageFormat) {
        LogPrint "Error: Unknown StorageFormat type: $storageFormat"
        return $False
    }

    if (@("IDE", "SCSI") -notcontains $diskType) {
        LogPrint "Error: Unknown StorageFormat type: $diskType"
        return $False
    }

    if ($diskType -eq "SCSI") {
        $vmObj = Get-VMHost -Name $hvServer | Get-VM -Name $vmName
        New-HardDisk -CapacityGB $capacityGB -VM $vmObj -StorageFormat $storageFormat -ErrorAction SilentlyContinue | Out-null
        if (-not $?) {
            Throw "Error : Cannot add new hard disk to the VM $vmName"
            return $False
        }
        else {
            LogPrint "INFO: Add disk done."
            return $True
        }
    }

    if ($diskType -eq "IDE") {
        if (AddIDEHardDisk -vmName $vmName -hvServer $hvServer -capacityGB $CapacityGB) {
            LogPrint "INFO: Add disk done."
            return $True
        }
        else {
            Throw "Error : Cannot add new hard disk to the VM $vmName"
            return $False
        }
    }

}
