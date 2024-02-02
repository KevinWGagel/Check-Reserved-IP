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
The Dhcp scope leases indicate if a reserved IP is "(active)" or "(inactive)" - this is only reliable if you are recording this state but itself is not
reliable either because it only indicates active or inactive if the client using that IP is requesting an IP address. In otherwords if you assign a static IP
then whatever status dhcp has will remain that way until you delete the reservation or boot a client with that mac address with the nic configured as dhcp. #>
Write-Verbose "Checking 'reserved' Ips to see if they're online."
$ReservationDetails | ForEach-Object {
    if (Test-Connection -ComputerName $($_.IPAddress) -count 1 -Quiet){
        $_.Online = $true
        Write-Verbose "Found $($_.IPAddress) online."
    }
    else {
        $_.Online = $false
        Write-Verbose "$($_.IPAddress) was not detected online."
    }
    $_.Date = $(Get-Date -Format 'yyyy/MM/dd')
    $_.Time = $(Get-Date -Format 'HH:mm:ss')
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
# SIG # Begin signature block
# MIIM0gYJKoZIhvcNAQcCoIIMwzCCDL8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAfdrsJkX/61db1
# Egkqegp5wXFLhGaimo5fj268ZDbC5aCCCoAwggTEMIIDrKADAgECAhMiAABmAQrH
# XA+xCw44AAAAAGYBMA0GCSqGSIb3DQEBCwUAMGAxEjAQBgoJkiaJk/IsZAEZFgJj
# YTEWMBQGCgmSJomT8ixkARkWBmNhbmZvcjEyMDAGA1UEAxMpQ2FuZm9yIEVudGVy
# cHJpc2UgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDEwHhcNMjMwODMwMTgyODQ3WhcN
# MjQwODI5MTgyODQ3WjBxMRIwEAYKCZImiZPyLGQBGRYCY2ExFjAUBgoJkiaJk/Is
# ZAEZFgZjYW5mb3IxFDASBgNVBAsTC0RvbWFpbkFkbWluMQ4wDAYDVQQLEwVVc2Vy
# czEdMBsGA1UEAxMUR2FnZWwsIEtldmluIChBZG1pbikwgZ8wDQYJKoZIhvcNAQEB
# BQADgY0AMIGJAoGBAK7BxA2yHqHJ1+hGuX2fNkrgPlOwv88BLxzaFie84HeMHNLb
# qj/+0EafYAvxP5jDZ7AkFCgZZHcWRrTbH3rFwsG0828MhiTI6qfI8jbHubWtDOUq
# hQ+gAMptBZMQyw5JltRs05fWRiFZMd124nN0GXAoR8/dzSz9PK1wEs9YOp+BAgMB
# AAGjggHoMIIB5DAlBgkrBgEEAYI3FAIEGB4WAEMAbwBkAGUAUwBpAGcAbgBpAG4A
# ZzATBgNVHSUEDDAKBggrBgEFBQcDAzALBgNVHQ8EBAMCB4AwHQYDVR0OBBYEFE2z
# Wh40wYj5yMErbacIdFlZmO+FMB8GA1UdIwQYMBaAFHcLaBd2fD+I7Nq+mdjxt7KV
# xATAMDgGA1UdHwQxMC8wLaAroCmGJ2h0dHA6Ly9wa2kuY2FuZm9yLmNhL3BraS9D
# QU5GT1ItRUNBLmNybDCBngYIKwYBBQUHAQEEgZEwgY4wZAYIKwYBBQUHMAKGWGh0
# dHA6Ly9wa2kuY2FuZm9yLmNhL3BraS9DQU5GT1ItRUNBQ2FuZm9yJTIwRW50ZXJw
# cmlzZSUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5JTIwMS5jcnQwJgYIKwYBBQUH
# MAGGGmh0dHA6Ly9vY3NwLmNhbmZvci5jYS9vY3NwMC4GA1UdEQQnMCWgIwYKKwYB
# BAGCNxQCA6AVDBN1NTk4NzQzYUBjYW5mb3IuY29tME4GCSsGAQQBgjcZAgRBMD+g
# PQYKKwYBBAGCNxkCAaAvBC1TLTEtNS0yMS0xNzkxOTI2OC0xMzIzOTg2NTI5LTc2
# OTI2NjA0Mi0yNjcyMTQwDQYJKoZIhvcNAQELBQADggEBAFvEPdorYYZke59kfyKb
# TmoGGm+ha/+NNFDxrzH9RTQKTKXvUeDIrk/i8jOWjlNIZRauqL/0DHN+2gQBcGoH
# fxNrktF6AhdB1qrtDuHk8CRISz7Smpm07qJ0bn4rDzkWoMk9UAjjV1FoDVr+kERZ
# 6R0xaOEmEteaV4RH9LzorF1ZSiTvepx1Sy3ur+46h7osyZBXyMm/oACSo3qVaNFd
# 1IvU6UlN2zYAXwS2NPkN3C1GSijM86wFTMIi6q8+9T7DIC+v/cOmmmGoHUy/0JKb
# J5t1pFY4s5EAvmQEOLJ1OL4u22Soaz02cPg/qwlAxhOxCoUtr6h2oEyl372C7bsA
# dBQwggW0MIIDnKADAgECAhNhAAAAAo7Kl/uMVF9UAAAAAAACMA0GCSqGSIb3DQEB
# CwUAMCwxKjAoBgNVBAMTIUNhbmZvciBSb290IENlcnRpZmljYXRlIEF1dGhvcml0
# eTAeFw0xOTAxMjQxNjM4NTFaFw0yOTAxMjQxNjQ4NTFaMGAxEjAQBgoJkiaJk/Is
# ZAEZFgJjYTEWMBQGCgmSJomT8ixkARkWBmNhbmZvcjEyMDAGA1UEAxMpQ2FuZm9y
# IEVudGVycHJpc2UgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDEwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQCnv/kcYLt0OmjZ4Wlqf2i7o7EL530crW/6FGy6
# kNURozJuQflgLzTcTmYkkkAE3RjtpC9cmQRpVjgx8mBHrUsJe5Utz0XAmyXzpAMQ
# dsWWgosphVZyIpi7sHy/7r974F416KXOHIYifRERrV/TvtcXJP0zVBUXOZntfJqd
# KA+aGLXiI8QjlSWQSfV33HOMPsy3MV4pQplzzahCQ4P7HrvyjY1c+2vW+uiUK+Tb
# Ltv2z6m2CDMizrhpPvRkyKkXGazCKhKg4jLxTaJNUtAxonGLp1LY8ve3FtPG9qsI
# E2vacV5ClP6MTwiPwFIa2NpV9J8TODYGfj+XKJB0zRJeYs0VAgMBAAGjggGZMIIB
# lTAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUdwtoF3Z8P4js2r6Z2PG3spXE
# BMAwYAYDVR0gBFkwVzBVBiIqhkiG9xQBvkCTeoGRbIO9Q4HrIYGNWILNeoaYq3WH
# hqkwMC8wLQYIKwYBBQUHAgEWIWh0dHA6Ly9wa2kuY2FuZm9yLmNhL3BraS9jcHMu
# aHRtbDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBQpHItc+Jnw3fA71m+V0j7BkDV74jA5
# BgNVHR8EMjAwMC6gLKAqhihodHRwOi8vcGtpLmNhbmZvci5jYS9wa2kvQ0FORk9S
# LVJPT1QuY3JsMGsGCCsGAQUFBwEBBF8wXTBbBggrBgEFBQcwAoZPaHR0cDovL3Br
# aS5jYW5mb3IuY2EvcGtpL0NBTkZPUi1ST09UQ2FuZm9yJTIwUm9vdCUyMENlcnRp
# ZmljYXRlJTIwQXV0aG9yaXR5LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAsx9+VRA+
# YKzvCDRuaQyhZAg9qFn/5MOul2vcq1W4GAlG0KYAeIu5f3tHfGNos+wH5o5j/8ee
# F/2HCKloxa8mfl7hEd6VIZ44TVSODG713WvCg4hOyyGnkiJ5UIqVg2gerc9mnYbG
# rTmSwez5fcX/H46neMntOhkCW8esJHKUeh1MnOym/560uFCZv8Pzd4o+6vS1/kV8
# oIMoLV5wm9E/bZZ+/NgXygvBxGAZKlJAlAmOqTYALZIbriJwZpUlhFTAOFMktJCS
# P4r4UJR/oBXuqYY8aYysRJsSol2zr51lug4jfBxWu0PaVeOy6b2rr+z0fNEqDZqh
# Bh0dPlOLi1XAvdP2d3gSr38S9H7qina8cgRfyYRK5jieZ4MERdqJ/NVtuqlcPXhE
# MAvURjIJV5HFE/Oi7wrnIkZO/h1smg/AQO6P1kTi72ip3U+P8VfR9c2eTlWlBdxA
# nvTfy1lGKXOGhyc7jLlGPAtN3k1Xttcl0N9gU6ip2g1KgsS7AlcwhpbXCapbN31q
# k0ZGcL29VoTIZcXBP8qkV7AbXVx2vt1D4+FGXu2TpaFgKp830Bo4WMS+FLXf/z4+
# CHH8iFeLFzDMriM1Yd9oMmNAc7KyOhSRuyvKneb5n0LotL3RNLF1ONfht2OUA+0U
# V2glb1ITETDNSkm9Byi+tEG3O7Qt5YpfiX0xggGoMIIBpAIBATB3MGAxEjAQBgoJ
# kiaJk/IsZAEZFgJjYTEWMBQGCgmSJomT8ixkARkWBmNhbmZvcjEyMDAGA1UEAxMp
# Q2FuZm9yIEVudGVycHJpc2UgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDECEyIAAGYB
# CsdcD7ELDjgAAAAAZgEwDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEK
# MAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3
# AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgzH/cqU/cQdL64FLA
# R7Pew5DOycj/1Xbz7SvAL/dLwL4wDQYJKoZIhvcNAQEBBQAEgYBWfwaT0XOWDaNi
# MtLalQ0vDgEDmzoqQ7iNmdnzvYhgbU2lmjscSw1/oWER/L1bXYToQxWVimFkO4H/
# ERJZtZdCVkbb2qXlJg5EXrdIK7X1OQLLqWPHz5A3tl+phQDPZMENamxPplrPPK9Q
# hirAjFyNBl4TiJ2adpINJ/QbNg/caw==
# SIG # End signature block
