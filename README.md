# Check-Reserved-IP
A script to check and record if a reserved IP address is in use.

I found several of our sites having issues with running out of IP addresses and large amounts of reserved IP addresses. But there is no record, no log file, no event viewer information that provides us
with information on how often a reserved Ip is in use. This script creates a way for us to check if an IP gets used.

This script logs the information to a general file and a IP specific file. The later is automatically deleted when the script is run again IF the reservation is deleted. The general file is not managed by the script.

Kevin W Gagel
