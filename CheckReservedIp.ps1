<#
.SYNOPSIS
    Checks active Dhcp scopes for reservations and records IP activity state.
.DESCRIPTION
    Checks active Dhcp scopes for reservations and records IP activity state.
.NOTES
    This script assumes only Dhcp v4 is in use.
    
    Setup on a schedule, at a frequency that satisfies you an Ip address reservation is not needed. The scheduled task should start in a specific directory where the data will be stored.
.EXAMPLE
    CheckReservedIp.ps1 -Verbose
    This example assumes the script is running on the Dhcp server in an isolated folder. It will retrieve all the scopes, their reserved Ip Addresses and state, log results.

    The use of the -Verbose parameter provides information about what the script is doing as it processes each command.
#>
#June 9, 2023 - removed online checks, relying on Dhcp servers Lease state. This only works by checking it on a schedule and recording results.




[CmdletBinding()]
param ()

#Setup variables
Write-Verbose "Setting up variables."
$ReservationDetails = New-Object System.Collections.ArrayList

#Get the active scopes
Write-Verbose "Getting active scopes from the Dhcp server."
$Scopes = Get-DhcpServerv4Scope | Where-Object { $_.State -eq 'Active' } | Select-Object -Property ScopeId

#Get the reservations
Write-Verbose "Getting the reserved Ip addresses for each scope and its status."
$Scopes | ForEach-Object {
    $Reservation = Get-DhcpServerv4Reservation -ScopeId $_.ScopeId | Select-Object -Property IPAddress, ScopeId, Name, Description
    $Reservation | ForEach-Object {
        $DetailedReservedIP = [PSCustomObject][ordered]@{
            Date           = 'UNKNOWN'
            Time           = 'UNKNOWN'
            Name           = $_.Name
            Description    = $_.Description
            IPAddress      = $_.IPAddress
            ScopeId        = $_.ScopeId
            Online         = 'UNKNOWN'
            LastOnlineDate = 'UNKNOWN'
            LastOnlineTime = 'UNKNOWN'
            AddressState   = 'UNKNOWN'
        }
        $DetailedReservedIP.AddressState = Get-DhcpServerv4Lease -IPAddress $DetailedReservedIP.IPAddress | Select-Object -ExpandProperty AddressState
        [void]$ReservationDetails.Add($DetailedReservedIP)
    }
}

#Get Lease status (active/inactive)
$ReservationDetails | ForEach-Object {
    
}

#Delete any individual *-Results.csv file that is no longer a reserved Ip Address.
Write-Verbose "Checking for unneeded *-Results.csv files due to the Ip Address being no longer reserved."
$ResultFiles = Get-Item -Path ".\*-Results.csv" | Select-Object -ExpandProperty Name
$ResultFiles | ForEach-Object {
    #Reduce the file name down to the IP address
    $Ip = ($_).Substring(0, ($_.IndexOf("-")))
    #Iterate through $Reservation to see if the IP is in it
    $StillReserved = $false
    $ReservationDetails | ForEach-Object {
        if ($IP -eq $_.IPAddress) {
            $StillReserved = $true
        }
    }
    #Delete the *-Results.csv file if the reservation is no longer present
    if ($StillReserved -eq $false) {
        Write-Verbose "Found $Ip is no longer reserved, removing $_ file (history is kept in CheckReservedIp-Results.csv)."
        Remove-Item -Path ".\$_"
    }
}

<# #Ping each reserved Ip record if Online or TimedOut
Notes: Test-NetConnection has no -count parameter, does not throw ugly error message and takes a bit of time to finish - unreliable due to f/w
Test-Connection has -count parameter and can run faster than Test-NetConnection when it is set to 1 - unreliable due to f/w
Either one does not assure the device at the IP will be detected if it has a firewall that has ICMP set to drop
Get-NetNeighbor will retrieve what is in cache but only works for devices on the same network segment
Nmap will retrieve a MAC address but on my w/s it always returns the same MAC and is therefor unsuitable, it also takes around 30 seconds for each ip scan
The Dhcp scope leases indicate if a reserved IP is "(active)" or "(inactive)" - this is only reliable if you are recording this state #>
Write-Verbose "Checking reserved Ip address state."
$ReservationDetails | ForEach-Object {
    Write-Verbose "Checking $($_.IPAddress) to see if it is online."
    if ($_.AddressState -eq 'ActiveReservation') {
        $_.Online = $true
        $_.Date = $(Get-Date -Format 'yyyy/MM/dd')
        $_.Time = $(Get-Date -Format 'HH:mm:ss')
    }
}

<# IPAddress-Results.csv files are to allow a quick overview of usage for a specifc reservation. They're meant for
use on a server that has only text view capabilities (no Excel or word processer etc.) It become readily apparent if an IP is used or not by following
the right hand columns. When IP reservation is removed its file is also removed automaticall the next time the script runs.
CheckReservedIp-Results-All.csv is keeping track of all reserved IPs and only grows. This file is usefull for Excel filtering and proving an IP no longer needs
to be reserved and is never automatically deleted. #>
#Save online activity for each reserved Ip address
Write-Verbose "Saving online activity for each reserved Ip address."
$ReservationDetails | ForEach-Object {
    if ($_.Online -eq $true) {
        $_.LastOnlineDate = $_.Date
        $_.LastOnlineTime = $_.Time
    }
    $_ | Export-Csv -Path "$($_.IPAddress)-Results.csv" -Append -NoTypeInformation -Delimiter ','
    $_ | Export-Csv -Path "CheckReservedIp-Results-All.csv" -Append -NoTypeInformation -Delimiter ','
}

$ReservationDetails