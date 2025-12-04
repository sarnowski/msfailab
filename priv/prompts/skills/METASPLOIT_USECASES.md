---
name: metasploit_usecases
description: Learn about Metasploit use cases including pentesting, red teaming, vulnerability validation, and expert strategies for each scenario.
---
# Metasploit Use Cases and Expert Strategies

This document outlines the primary scenarios where Metasploit Framework is used along with expert strategies for each.

---

## 1. Penetration Testing Engagements

**Scenario:** Authorized security assessments of corporate networks, applications, or infrastructure.

**Expert Strategies:**

- **Phased approach:** Reconnaissance → Vulnerability Analysis → Exploitation → Post-Exploitation → Reporting
- **Database integration:** Use PostgreSQL backend (`db_connect`) to persist discovered hosts, services, and credentials across sessions
- **Workspace isolation:** Create separate workspaces per client/engagement (`workspace -a client_name`)
- **Auxiliary module chaining:** Run discovery modules (`auxiliary/scanner/*`) before exploitation to map the attack surface
- **Credential harvesting:** Use `post/multi/gather/*` modules systematically after initial access

---

## 2. Red Team Operations

**Scenario:** Adversary emulation to test detection and response capabilities.

**Expert Strategies:**

- **Stealth-first mindset:** Adjust Meterpreter sleep intervals, use encrypted channels, avoid noisy scans
- **Custom payloads:** Use `msfvenom` with encoders and custom templates to evade AV/EDR
- **Staged payloads:** Use small stagers (`windows/meterpreter/reverse_https`) that pull larger stages to minimize initial footprint
- **Living off the land:** Combine Metasploit with LOLBins for execution rather than dropping executables
- **Pivoting:** Use `autoroute` and SOCKS proxies to move laterally through compromised hosts into segmented networks
- **Team coordination:** Deploy Armitage team server or integrate with Cobalt Strike for collaborative operations

---

## 3. Vulnerability Validation

**Scenario:** Confirming whether discovered vulnerabilities are actually exploitable.

**Expert Strategies:**

- **Check before exploit:** Use `check` command on modules that support it to validate without triggering payloads
- **Safe payloads:** Start with benign payloads (`generic/shell_bind_tcp`) before escalating
- **Targeted validation:** Search modules by CVE (`search cve:2017-0144`) to match scanner findings
- **Evidence collection:** Capture screenshots, session logs, and system info for documentation

---

## 4. Social Engineering Assessments

**Scenario:** Testing human susceptibility to phishing, pretexting, or malicious file delivery.

**Expert Strategies:**

- **Client-side attacks:** Use `exploit/multi/browser/*` or `exploit/windows/fileformat/*` modules
- **Payload embedding:** Generate weaponized documents with `msfvenom` (macros, HTA, Office exploits)
- **Phishing integration:** Pair with Social Engineering Toolkit (SET) for campaign delivery
- **Multi-handler setup:** Configure `exploit/multi/handler` listeners before sending payloads

---

## 5. Post-Exploitation & Privilege Escalation

**Scenario:** Demonstrating impact after initial access—what an attacker could achieve.

**Expert Strategies:**

- **Local exploit suggester:** Run `post/multi/recon/local_exploit_suggester` to find privesc paths
- **Credential dumping:** Use `hashdump`, `mimikatz` extension, or `post/windows/gather/credentials/*`
- **Persistence:** Deploy backdoors with `post/windows/manage/persistence_exe` or registry-based methods
- **Token manipulation:** Impersonate users with `incognito` for lateral movement
- **Data exfiltration:** Stage sensitive data collection before cleanup

---

## 6. Wireless Network Testing

**Scenario:** Assessing Wi-Fi security and rogue access points.

**Expert Strategies:**

- **Rogue AP attacks:** Use Metasploit with Karma/Mana attacks
- **Credential capture:** Deploy fake captive portals to harvest credentials
- **Integration:** Combine with Aircrack-ng suite for WPA handshake capture, then crack offline

---

## 7. IoT/SCADA/OT Security Testing

**Scenario:** Assessing industrial control systems and embedded devices.

**Expert Strategies:**

- **Protocol-specific modules:** Use auxiliary modules for Modbus, BACnet, SNMP
- **Firmware analysis:** Extract and analyze firmware, then develop custom exploits
- **Network segmentation testing:** Validate OT/IT boundary controls via pivoting

---

## 8. Security Training & CTF Competitions

**Scenario:** Educational environments like Hack The Box, TryHackMe, or corporate training.

**Expert Strategies:**

- **Methodical enumeration:** Always run `db_nmap` first and review results with `hosts` and `services`
- **Module exploration:** Use `search`, `info`, and `show options` to understand modules before use
- **Resource scripts:** Automate repetitive tasks with `.rc` files
- **Documentation:** Keep notes on what worked for learning purposes

---

## 9. Exploit Development & Research

**Scenario:** Discovering new vulnerabilities and creating proof-of-concept exploits.

**Expert Strategies:**

- **Module development:** Write custom modules in Ruby following Metasploit's API
- **Payload customization:** Create custom shellcode for specific targets
- **Fuzzing integration:** Use auxiliary fuzzers to discover new attack vectors
- **Responsible disclosure:** Coordinate with vendors before publishing modules

---

## Universal Expert Practices

| Practice | Description |
|----------|-------------|
| **Workspace management** | Isolate engagements; never mix client data |
| **Session handling** | Background sessions (`background`), track with `sessions -l` |
| **Automation** | Use resource scripts and `db_autopwn` (carefully) |
| **OPSEC** | Rotate listeners, use HTTPS/DNS channels, clean up artifacts |
| **Documentation** | Export findings from database for reporting |

---

## References

- [EC-Council: Metasploit Framework for Penetration Testing](https://www.eccouncil.org/cybersecurity-exchange/penetration-testing/metasploit-framework-for-penetration-testing/)
- [SANS SEC580: Metasploit for Enterprise Penetration Testing](https://www.sans.org/cyber-security-courses/metasploit-enterprise-penetration-testing)
- [Red Team 102: Understanding Metasploit](https://securityboulevard.com/2018/11/red-team-102-understanding-metasploit/)
- [How to Red Team – Metasploit Framework](https://holdmybeersecurity.com/2017/05/30/part-2-how-to-red-team-metasploit-framework/)
- [Metasploit Revealed: Secrets of the Expert Pentester](https://www.oreilly.com/library/view/metasploit-revealed-secrets/9781788624596/)
- [Imperva: What Is Metasploit](https://www.imperva.com/learn/application-security/metasploit/)
- [Red Teaming Tactics with Custom Staged Payloads](https://medium.com/@nickswink7/red-teaming-tactics-unlocking-the-power-of-custom-staged-payloads-w-metasploit-d3db71567572)
