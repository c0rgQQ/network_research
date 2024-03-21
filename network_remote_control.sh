#!/bin/bash

# 1) update package lists
sudo apt-get update
sudo apt-get upgrade

# 2) check and install required applications if not already installed
required_apps=("sshpass" "nmap" "whois")

for app in "${required_apps[@]}"; do
    if ! dpkg -l | grep -qE "^ii\s+$app\s"; then
        sudo apt-get install -y "$app"
    fi
done

# 3) check if there is an existing anonymous network connection (tor, vpn, proxy). If none, alert the user and exit the script
if ifconfig -a | grep -qE "tun[0-9]+|tap[0-9]+|wg[0-9]+"; then  # check for VPN Connection (tun, tap, or wg interfaces)
    echo "Connected to a VPN."
elif [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
    echo "Using a proxy."
elif pgrep -x "tor" >/dev/null; then
    echo "Connected to the Tor network."
else
    echo "Not connected to a VPN, using a proxy, or connected to the Tor network."
    exit 1  
fi

# 4) upon connecting to an anonymous network, display the spoofed country name 
spoofip=$(ifconfig -a | grep -A 1 -E "tun[0-9]+|tap[0-9]+|wg[0-9]+" | grep inet | awk '{print $2}')
spoofcountry=$(whois "$spoofip" | grep -i country)
echo "$spoofcountry"

# 5) user will specify the address/URL to whois from remote server later by saving it as a variable first
echo 'Provide an address or URL to whois from the remote server:'
read ipurl

# 6) connect to the remote server via ssh using sshpass
echo 'Provide the IP address of the remote server to ssh into:'
read ipaddr

echo 'Provide the SSH username:'
read remoteuser

ssh_port=""

scan_for_ssh_ports() {   # scan for open SSH ports
    echo "Scanning $ipaddr for open SSH ports"
    open_ports=$(nmap -p 0-65535 --open "$ipaddr" | grep 'open' | grep -w 'ssh')
    
    if [ ! -z "$open_ports" ]; then
        echo "Open SSH ports found:"
        echo "$open_ports"
        ssh_port=$(echo "$open_ports" | awk '{print $1}' | cut -d'/' -f1)
    else
        echo "No open SSH ports found on $ipaddr."
        read -p "Do you want to rescan the server (yes/no)? " rescan
        if [ "$rescan" = "yes" ]; then
            scan_for_ssh_ports
        else
            echo "Exiting"
            exit 
        fi
    fi
}

scan_for_ssh_ports # call the function to scan for open ports

if [ -z "$ssh_port" ]; then
    scan_for_ssh_ports
    exit
fi

ssh -p "$ssh_port" "$remoteuser"@"$ipaddr" <<EOF

# 7) display the details of the remote server (country, IP, uptime)
if [[ "$ipaddr" == 10.* || "$ipaddr" == 192.168.* || "$ipaddr" == 172.[16-31].* ]]; then
  echo "IP Address (eth0): $ipaddr"
else
  echo "IP Address (eth0): $ipaddr"
  whois_result=$(whois "$ipaddr" | grep -i "Country")
  echo "$whois_result"
fi

echo "Server Uptime:"
uptime

# 8) have the remote server perform a whois on the given address/URL and save the whois data to a file
whois "$ipurl" > ipurl.txt
EOF

# 9) collect the file from the remote computer via ftp
# define log file path and saving the log on the local machine
log_file="$HOME/logfile.txt"

# create a log and audit your data collection
log_message() {
  local message="$1"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $message" >> "$log_file"
}

# file Details
remote_filepath="~/ipurl.txt"
local_filepath="$HOME/ipurl.txt"

# connect to FTP server and download the file
ftp -n "$ipaddr" <<EOF
user "$remoteuser" "$remotepasswd"
binary
get "$remote_filepath" "$local_filepath"
quit
EOF

# logging the FTP operation
log_message "FTP transfer of $remote_filepath completed."
