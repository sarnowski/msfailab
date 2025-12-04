---
name: reconnaissance
description: Learn OSINT, passive/active reconnaissance, network mapping, service enumeration, and vulnerability scanning to gather intelligence before exploitation.
---
# Reconnaissance

## When to Use This Skill

- Starting a new engagement or assessment
- Mapping the attack surface of a target organization
- Discovering hosts, services, and potential entry points
- Gathering intelligence before exploitation attempts
- Performing subdomain enumeration or infrastructure discovery

---

## Concepts

### Intelligence Gathering Lifecycle

1. **Define scope** — Clarify target boundaries, rules of engagement
2. **Passive collection** — OSINT without touching target infrastructure
3. **Active enumeration** — Direct interaction with target systems
4. **Analysis** — Correlate findings, identify attack vectors
5. **Documentation** — Record in workspace database for exploitation phase

### Passive vs Active Trade-offs

| Approach | Detection Risk | Data Freshness | Depth |
|----------|---------------|----------------|-------|
| Passive | None | May be stale | Limited |
| Semi-passive | Low | Recent | Moderate |
| Active | Detectable | Real-time | Complete |

Start passive, progress to active only when necessary and authorized.

---

## Passive Reconnaissance (OSINT)

### Search Engine Intelligence

**Google Dorking** — Advanced operators for targeted discovery:

```
site:target.com                     # Limit to domain
site:target.com filetype:pdf        # Find documents
site:target.com inurl:admin         # Admin panels
site:target.com intitle:"index of"  # Directory listings
site:target.com ext:sql | ext:db    # Database files
site:target.com intext:password     # Credential leaks
"target.com" filetype:xls           # Spreadsheets mentioning target
```

**Google Hacking Database (GHDB)** — Reference exploit-db.com/google-hacking-database for categorized dorks covering:
- Vulnerable servers, login pages, sensitive directories
- Files containing passwords, usernames, or keys
- Network/vulnerability data, web server detection

### Infrastructure Intelligence

**WHOIS/Reverse WHOIS**:
```bash
whois target.com                     # Basic registration
whois -h whois.arin.net target.com  # ARIN for IP blocks
# Reverse WHOIS via ViewDNS, DomainTools for related domains
```

**DNS Enumeration**:
```bash
# Zone transfer attempt (often blocked but worth trying)
dig axfr @ns1.target.com target.com
host -t axfr target.com ns1.target.com

# Standard records
dig target.com ANY +noall +answer
dig target.com MX +short
dig target.com NS +short
dig target.com TXT +short

# DNSRecon comprehensive enumeration
dnsrecon -d target.com -t std,brt,axfr -D /usr/share/wordlists/subdomains-top1million-5000.txt

# DNSenum with Google scraping and brute force
dnsenum --enum -f /usr/share/wordlists/subdomains.txt target.com
```

**Certificate Transparency**:
```bash
# Query crt.sh for SSL certificates (reveals subdomains)
curl -s "https://crt.sh/?q=%25.target.com&output=json" | jq -r '.[].name_value' | sort -u

# CTFR tool
ctfr -d target.com -o ctfr_output.txt
```

**BGP/ASN Mapping**:
```bash
# Find ASN for organization
whois -h whois.cymru.com " -v target.com"
# Enumerate IP ranges owned by ASN
whois -h whois.radb.net -- '-i origin AS12345'
```

### Platform Intelligence

**Shodan** — Internet-wide device scanner:
```
# Basic searches
hostname:target.com
org:"Target Organization"
net:192.168.0.0/16
ssl.cert.subject.cn:target.com

# Service-specific
port:22 org:"Target"              # SSH servers
port:3389 org:"Target"            # RDP
product:nginx org:"Target"        # Web servers
vuln:CVE-2021-44228 org:"Target"  # Log4j vulnerable

# CLI usage
shodan search --fields ip_str,port,org "hostname:target.com"
shodan host 192.168.1.1
```

**Censys** — Certificate and host search:
```
# Search syntax
services.http.response.html_title:"Target"
services.tls.certificates.leaf.subject.common_name:*.target.com
autonomous_system.name:"Target Organization"
```

### Social Intelligence

**LinkedIn Reconnaissance**:
- Employee enumeration for usernames, email patterns
- Technology stack from job postings
- Organizational structure, key personnel
- Tools: linkedin2username, CrossLinked

**Email Harvesting**:
```bash
# theHarvester multi-source enumeration
theHarvester -d target.com -b google,bing,linkedin,dnsdumpster,crtsh -l 500

# Hunter.io API (requires key)
theHarvester -d target.com -b hunter
```

### Code/Document Intelligence

**GitHub Dorking**:
```
"target.com" password
"target.com" api_key
"target.com" secret
org:targetorg filename:.env
org:targetorg extension:pem private
```

**Metadata Extraction**:
```bash
# Download documents from target
metagoofil -d target.com -t pdf,doc,xls -l 100 -n 25 -o ./meta

# Extract metadata
exiftool *.pdf | grep -i "author\|creator\|email"
```

---

## Active Reconnaissance

### Host Discovery

**Metasploit db_nmap Integration**:
```
msf6 > db_nmap -sn -PE -PP -PM -PS21,22,23,25,80,443,3389 192.168.1.0/24
msf6 > hosts
```

**Nmap Host Discovery**:
```bash
# ICMP echo, timestamp, netmask
nmap -sn -PE -PP -PM 192.168.1.0/24

# TCP SYN to common ports (stealthier)
nmap -sn -PS21,22,25,80,443,3389,8080 192.168.1.0/24

# ARP scan (local network only, very reliable)
nmap -sn -PR 192.168.1.0/24
arp-scan -l

# Combine methods
nmap -sn -PE -PS80,443 -PA3389 -PU40125 192.168.1.0/24
```

### Port Scanning

**Metasploit Modules**:
```
msf6 > use auxiliary/scanner/portscan/tcp
msf6 auxiliary(tcp) > set RHOSTS 192.168.1.0/24
msf6 auxiliary(tcp) > set PORTS 1-1024,3306,3389,5432,5900,8080,8443
msf6 auxiliary(tcp) > set THREADS 50
msf6 auxiliary(tcp) > run

# SYN scanner (requires root)
msf6 > use auxiliary/scanner/portscan/syn
```

**Nmap Port Scanning**:
```bash
# SYN scan (default, fast, stealthy)
nmap -sS -p- --min-rate 1000 -T4 192.168.1.10

# Full TCP connect (no root required)
nmap -sT -p- 192.168.1.10

# UDP scan (slow, essential for DNS/SNMP/DHCP)
nmap -sU --top-ports 100 192.168.1.10

# Version detection with scripts
nmap -sV -sC -p22,80,443,3306 192.168.1.10

# Comprehensive scan
nmap -sS -sV -sC -O -p- --min-rate 5000 -oA full_scan 192.168.1.10
```

**Masscan High-Speed Scanning**:
```bash
# Fast discovery of common ports across large ranges
masscan 10.0.0.0/8 -p21,22,23,25,80,443,445,3389,8080 --rate 10000 -oL masscan_out.txt

# All TCP ports on smaller range
masscan 192.168.1.0/24 -p1-65535 --rate 100000 --open-only -oG masscan.gnmap

# Parse and feed to nmap for service detection
awk '/open/{print $4}' masscan_out.txt | sort -u > live_hosts.txt
nmap -sV -sC -iL live_hosts.txt
```

### Service Enumeration

**Metasploit Auxiliary Scanners** (organized by service):

```
# SMB
msf6 > use auxiliary/scanner/smb/smb_version
msf6 > use auxiliary/scanner/smb/smb_enumshares
msf6 > use auxiliary/scanner/smb/smb_enumusers

# SSH
msf6 > use auxiliary/scanner/ssh/ssh_version
msf6 > use auxiliary/scanner/ssh/ssh_enumusers

# HTTP
msf6 > use auxiliary/scanner/http/http_version
msf6 > use auxiliary/scanner/http/title
msf6 > use auxiliary/scanner/http/dir_scanner

# Database
msf6 > use auxiliary/scanner/mysql/mysql_version
msf6 > use auxiliary/scanner/mssql/mssql_ping
msf6 > use auxiliary/scanner/postgres/postgres_version

# SNMP
msf6 > use auxiliary/scanner/snmp/snmp_enum

# Discovery sweep (comprehensive)
msf6 > use auxiliary/scanner/discovery/udp_sweep
```

**Nmap NSE Scripts**:
```bash
# Banner grabbing and version detection
nmap -sV --version-intensity 5 -p- target

# Default scripts (safe, useful info)
nmap -sC target

# Specific script categories
nmap --script=default,safe,vuln target
nmap --script=smb-enum-shares,smb-enum-users target
nmap --script=http-enum,http-headers,http-methods target

# Vulnerability scanning
nmap --script=vuln target
nmap --script=smb-vuln-ms17-010 target
```

### Subdomain Enumeration

**Amass** (most comprehensive):
```bash
# Passive only (no direct target contact)
amass enum -passive -d target.com -o amass_passive.txt

# Active with brute force
amass enum -active -brute -d target.com -o amass_active.txt

# Intel gathering (find related domains)
amass intel -org "Target Organization"
amass intel -asn 12345
```

**Subfinder** (fast, passive):
```bash
subfinder -d target.com -all -o subfinder.txt
```

**Combined Workflow**:
```bash
# Run multiple tools
subfinder -d target.com -silent > subs.txt
amass enum -passive -d target.com >> subs.txt
cat subs.txt | sort -u > all_subs.txt

# Resolve and probe for live hosts
cat all_subs.txt | httpx -silent -o live_hosts.txt
```

### Web Reconnaissance

**Directory/Content Discovery**:
```bash
# Gobuster
gobuster dir -u http://target.com -w /usr/share/wordlists/dirb/common.txt -t 50

# Feroxbuster (recursive, fast)
feroxbuster -u http://target.com -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt

# Ffuf (flexible fuzzing)
ffuf -u http://target.com/FUZZ -w wordlist.txt -mc 200,301,302,403
```

**Technology Fingerprinting**:
```bash
# WhatWeb
whatweb -v target.com

# Wappalyzer CLI
wappalyzer http://target.com
```

---

## Metasploit Database Integration

### Importing External Results

```
msf6 > db_import /path/to/nmap_scan.xml
msf6 > db_import /path/to/nessus_scan.nessus
msf6 > db_import /path/to/masscan.xml
```

### Database Queries

```
msf6 > hosts                           # All discovered hosts
msf6 > hosts -c address,os_name,name   # Specific columns
msf6 > hosts -S windows                # Search filter
msf6 > hosts -R                        # Set RHOSTS from hosts

msf6 > services                        # All services
msf6 > services -p 445                 # By port
msf6 > services -s http                # By service name
msf6 > services -c port,name,info -S ssh

msf6 > vulns                           # Discovered vulnerabilities
msf6 > creds                           # Harvested credentials
msf6 > notes                           # Assessment notes
```

---

## Evasion During Reconnaissance

### Scan Timing and Rate Control

```bash
# Nmap timing templates
nmap -T0 target  # Paranoid (IDS evasion, very slow)
nmap -T1 target  # Sneaky
nmap -T2 target  # Polite
nmap -T3 target  # Normal (default)
nmap -T4 target  # Aggressive

# Custom timing
nmap --scan-delay 1s --max-retries 2 target
nmap --max-rate 100 target  # Limit packets/second
```

### Packet Manipulation

```bash
# Fragment packets to evade IDS
nmap -f target
nmap --mtu 24 target

# Append random data
nmap --data-length 50 target

# Bad checksums (detect stateful inspection)
nmap --badsum target
```

### Decoys and Spoofing

```bash
# Decoy scan (blend with fake sources)
nmap -D RND:10 target                    # 10 random decoys
nmap -D 192.168.1.5,192.168.1.6,ME target  # Specific decoys

# Source port manipulation (bypass poorly configured firewalls)
nmap --source-port 53 target   # DNS
nmap --source-port 80 target   # HTTP
nmap -g 53 target              # Short form

# Idle scan (completely anonymous via zombie)
nmap -sI zombie_host:port target
```

### Source Obfuscation

```bash
# ProxyChains for routing through proxies
proxychains nmap -sT -Pn target

# Tor routing
proxychains -f /etc/proxychains4.conf nmap -sT -Pn target
```

### OSINT Stealth

- Use VPN or cloud instances for searches
- Avoid repeated queries from same IP
- Prefer passive sources over direct enumeration
- Cache results to reduce repeat queries
- Be aware that Shodan/Censys queries may be logged

---

## Workflows

### External Penetration Test Reconnaissance

1. **Passive OSINT** (no target interaction):
   ```bash
   theHarvester -d target.com -b all -l 500 -f theharvester_out
   amass enum -passive -d target.com -o amass.txt
   # Query Shodan, Censys, crt.sh
   ```

2. **DNS enumeration**:
   ```bash
   dnsrecon -d target.com -t std,brt,axfr
   ```

3. **Subdomain discovery and resolution**:
   ```bash
   subfinder -d target.com | httpx -silent | tee live_hosts.txt
   ```

4. **Port scanning discovered hosts**:
   ```
   msf6 > db_nmap -sS -sV -sC -p- --min-rate 5000 -iL live_hosts.txt
   ```

5. **Service enumeration and vuln scanning**:
   ```
   msf6 > services -c port,name,info
   msf6 > vulns
   ```

### Internal Network Discovery

1. **Host discovery**:
   ```
   msf6 > db_nmap -sn -PE -PS22,80,445 192.168.0.0/16
   ```

2. **Quick port scan**:
   ```
   msf6 > db_nmap -sS -p21,22,23,25,80,443,445,3306,3389,5432 192.168.0.0/16 --min-rate 10000
   ```

3. **Service enumeration on discovered hosts**:
   ```
   msf6 > hosts -R
   msf6 > use auxiliary/scanner/smb/smb_version
   msf6 > run
   msf6 > use auxiliary/scanner/smb/smb_ms17_010
   msf6 > run
   ```

4. **UDP services** (SNMP, DNS, DHCP):
   ```
   msf6 > use auxiliary/scanner/discovery/udp_sweep
   msf6 > set RHOSTS 192.168.0.0/24
   msf6 > run
   ```

### Red Team OSINT Workflow

1. **Organization intelligence**:
   - LinkedIn employee enumeration
   - Org chart from job postings
   - Technology stack from careers page
   - Document metadata extraction

2. **Infrastructure mapping** (passive only):
   ```bash
   amass intel -org "Target Corp"
   shodan search 'org:"Target Corp"' --fields ip_str,port,product
   ```

3. **Credential hunting**:
   - GitHub dorking for leaked secrets
   - Breach database searches (haveibeenpwned API)
   - Pastebin monitoring

4. **Build target profile** for phishing/social engineering

### Web Application Reconnaissance

1. **Technology fingerprinting**:
   ```bash
   whatweb -a 3 target.com
   ```

2. **Content discovery**:
   ```bash
   feroxbuster -u https://target.com -w /usr/share/seclists/Discovery/Web-Content/raft-large-directories.txt -x php,asp,aspx,jsp
   ```

3. **Virtual host enumeration**:
   ```bash
   ffuf -u http://target.com -H "Host: FUZZ.target.com" -w subdomains.txt -mc 200,301,302
   ```

4. **Parameter discovery**:
   ```bash
   arjun -u https://target.com/page
   ```

5. **Import to Metasploit**:
   ```
   msf6 > db_nmap -sV -sC -p80,443 target.com
   msf6 > use auxiliary/scanner/http/http_version
   msf6 > use auxiliary/scanner/http/robots_txt
   ```
