#!/bin/bash

if [ -z "$1" ]; then
    echo "Please provide a target IP address as an argument"
    exit 1
else
    TARGET_IP="$1"
fi

NMAP_OUTPUT_DIR=nmap_scan
mkdir -p "$NMAP_OUTPUT_DIR"

echo "$TARGET_IP" > "$NMAP_OUTPUT_DIR/target_ip.txt"

NMAP_OUTPUT_FILE="$NMAP_OUTPUT_DIR/nmap_scan.txt"

nmap -sC -sV -oN "$NMAP_OUTPUT_FILE" "$TARGET_IP"

if grep -q "OS:" "$NMAP_OUTPUT_FILE"; then
    OPERATING_SYSTEM=$(grep "OS:" "$NMAP_OUTPUT_FILE" | cut -d ":" -f 2)
    echo "Operating system: $OPERATING_SYSTEM"
else
    echo "Operating system information not found"
fi

if grep -q "21/tcp.*ftp.*Anonymous" "$NMAP_OUTPUT_FILE"; then
    echo "FTP port is open and anonymous login is available"

    if ! nc -w 5 "$TARGET_IP" 21 < <(echo -e "USER anonymous\nPASS\nls\nquit\n"); then
        echo "Failed to log in to the FTP server"
        exit 1
    fi

    if nc -w 5 "$TARGET_IP" 21 < <(echo -e "USER anonymous\nPASS\nCWD /\nMKD test\nRMD test\nquit\n") | grep -q "226 Transfer complete"; then
        echo "FTP server allows write access"
    else
        echo "FTP server does not allow write access"
    fi

    if nc -w 5 "$TARGET_IP" 21 < <(echo -e "USER anonymous\nPASS\nSITE CHMOD 777 /\nSTOR test.txt\nDELE test.txt\nquit\n") | grep -q "226 Transfer complete"; then
        echo "FTP server allows anonymous upload"
    else
        echo "FTP server does not allow anonymous upload"
    fi
else
    echo "FTP port is not open or anonymous login is not available"
fi

if grep -q "139/tcp.*netbios-ssn" "$NMAP_OUTPUT_FILE" || grep -q "445/tcp.*microsoft-ds" "$NMAP_OUTPUT_FILE"; then
    echo "Samba port is open"

    if ! enum4linux "$TARGET_IP"; then
        echo "Failed to run Enum4linux"
        exit 1
    fi
else
    echo "Samba port is not open"
fi

if grep -q "80/tcp.*http" "$NMAP_OUTPUT_FILE" || grep -q "443/tcp.*https" "$NMAP_OUTPUT_FILE"; then
    echo "Website port is open"

    WEBSITE_OUTPUT_FILE="$NMAP_OUTPUT_DIR/website.html"
    if ! nc -w 5 "$TARGET_IP" 80 < /dev/null > "$WEBSITE_OUTPUT_FILE" 2>&1; then
        echo "Failed to retrieve website"
        rm "$WEBSITE_OUTPUT_FILE"
        exit 1
    fi

    echo "Website saved to $WEBSITE_OUTPUT_FILE"

    if ! nikto -h "http://$TARGET_IP" -output "$NMAP_OUTPUT_DIR/nikto_scan.txt"; then
        echo "Failed to run Nikto"
        exit 1
    fi

    echo "Nikto scan saved to $NMAP_OUTPUT_DIR/nikto_scan.txt"
else
    echo "Website port is not open"
fi

if [ -z "$2" ]; then
    WORDLIST=/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
else
    WORDLIST="$2"
fi

if ! gobuster dir -u "http://$TARGET_IP" -w "$WORDLIST"; then
    echo "Failed to run Gobuster"
    exit 1
fi
