# XDC Node Hosting Providers

A curated list of verified hosting providers for running XDC Network nodes.

## Quick Comparison

| Provider | Cheapest Plan | Recommended Plan | Data Centers | Best For |
|----------|--------------|------------------|--------------|----------|
| [Hetzner](#hetzner) | €4.51/mo | €17.66/mo | EU, US | Budget, EU users |
| [Contabo](#contabo) | €4.99/mo | €12.99/mo | EU, US, Asia | Best value |
| [DigitalOcean](#digitalocean) | $24/mo | $48/mo | Global | Beginners |
| [Vultr](#vultr) | $20/mo | $40/mo | Global | Flexibility |
| [OVHcloud](#ovhcloud) | €7/mo | €22/mo | Global, EU focus | EU compliance |
| [AWS](#amazon-web-services) | ~$85/mo | ~$140/mo | Global | Enterprise |

---

## Hetzner

![Hetzner Logo](https://img.shields.io/badge/Hetzner-D91122?style=flat-square&logo=hetzner&logoColor=white)

German cloud provider with excellent price-performance ratio.

### Pricing

| Plan | vCPUs | RAM | Storage | Price | XDC Suitability |
|------|-------|-----|---------|-------|-----------------|
| CX11 | 1 | 2 GB | 20 GB SSD | €4.51/mo | ⚠️ Devnet only |
| CPX11 | 2 | 4 GB | 40 GB NVMe | €6.69/mo | ✅ Testnet |
| CPX21 | 4 | 8 GB | 80 GB NVMe | €13.10/mo | ✅ Mainnet |
| CPX31 | 8 | 16 GB | 160 GB NVMe | €26.76/mo | ✅✅ Mainnet + Archive |
| CPX41 | 16 | 32 GB | 240 GB NVMe | €59.44/mo | ✅✅ Enterprise |

### Recommended Specs

- **Minimum**: CPX21 (4 vCPUs, 8GB RAM, 80GB NVMe)
- **Mainnet**: CPX31 (8 vCPUs, 16GB RAM, 160GB NVMe)
- **Archive Node**: CPX41 (16 vCPUs, 32GB RAM, 240GB+ NVMe)

### Data Centers

- Nuremberg (Germany)
- Falkenstein (Germany)
- Helsinki (Finland)
- Hillsboro, OR (USA)
- Ashburn, VA (USA)

### Setup Notes

```bash
# Hetzner Cloud CLI installation
curl -fsSL https://raw.githubusercontent.com/hetznercloud/cli/master/install.sh | bash

# Create server
hcloud server create --name xdc-node --type cpx31 --image ubuntu-22.04 --location nbg1

# Quick deploy with cloud-init
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/install.sh | sudo bash
```

### Pros
- Excellent price-performance
- German data protection (GDPR compliant)
- Fast NVMe storage
- No ingress/egress fees

### Cons
- Limited US presence
- No managed Kubernetes (for this use case)

**[➡️ Get Started with Hetzner](https://www.hetzner.com/cloud)** *(affiliate link placeholder)*

---

## Contabo

![Contabo Logo](https://img.shields.io/badge/Contabo-3B4252?style=flat-square)

Budget-friendly German provider with generous resource allocations.

### Pricing

| Plan | vCPUs | RAM | Storage | Price | XDC Suitability |
|------|-------|-----|---------|-------|-----------------|
| Cloud VPS S | 4 | 8 GB | 200 GB SSD | €4.99/mo | ✅ Mainnet |
| Cloud VPS M | 6 | 16 GB | 400 GB SSD | €8.99/mo | ✅✅ Mainnet |
| Cloud VPS L | 8 | 30 GB | 800 GB SSD | €12.99/mo | ✅✅ Mainnet + Archive |
| Cloud VPS XL | 10 | 60 GB | 1.6 TB SSD | €21.99/mo | ✅✅ Enterprise |

### Recommended Specs

- **Mainnet**: Cloud VPS M (6 vCPUs, 16GB RAM, 400GB SSD)
- **Archive Node**: Cloud VPS L (8 vCPUs, 30GB RAM, 800GB SSD)

### Data Centers

- Germany (Munich, Nuremberg)
| - United Kingdom (London)
- United States (St. Louis, MO; New York, NY)
- Singapore
- Japan (Tokyo)
- Australia (Sydney)

### Setup Notes

```bash
# Contabo instances come with ample storage
# Default setup works well for mainnet

# Use standard install
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/install.sh | sudo bash
```

### Pros
- Best price-to-performance ratio
- Large storage allocations
- Multiple global locations
- No traffic limits

### Cons
- Setup fee for first month
- Slightly higher latency in some regions
- Less enterprise features

**[➡️ Get Started with Contabo](https://contabo.com)** *(affiliate link placeholder)*

---

## DigitalOcean

![DigitalOcean Logo](https://img.shields.io/badge/DigitalOcean-0080FF?style=flat-square&logo=digitalocean&logoColor=white)

Developer-friendly cloud platform with simple pricing.

### Pricing

| Plan | vCPUs | RAM | Storage | Price | XDC Suitability |
|------|-------|-----|---------|-------|-----------------|
| Basic 2GB | 1 | 2 GB | 50 GB SSD | $12/mo | ⚠️ Devnet only |
| Basic 4GB | 2 | 4 GB | 80 GB SSD | $24/mo | ✅ Testnet |
| Basic 8GB | 4 | 8 GB | 160 GB SSD | $48/mo | ✅ Mainnet |
| Basic 16GB | 4 | 16 GB | 200 GB SSD | $96/mo | ✅✅ Mainnet |
| Basic 32GB | 8 | 32 GB | 400 GB SSD | $192/mo | ✅✅ Archive |

### Recommended Specs

- **Minimum**: Basic 8GB (4 vCPUs, 8GB RAM, 160GB SSD)
- **Mainnet**: Basic 16GB (4 vCPUs, 16GB RAM, 200GB SSD + Volume)

### Data Centers

- New York (NYC1, NYC3)
- San Francisco (SFO3)
- Amsterdam (AMS3)
- Singapore (SGP1)
- London (LON1)
- Frankfurt (FRA1)
- Toronto (TOR1)
- Bangalore (BLR1)
- Sydney (SYD1)

### Setup Notes

```bash
# Using doctl
doctl compute droplet create xdc-node \
  --region nyc3 \
  --size s-4vcpu-8gb \
  --image ubuntu-22-04-x64 \
  --ssh-keys <your-key-id>

# Or use the 1-Click App from Marketplace
doctl compute droplet create xdc-node \
  --region nyc3 \
  --size s-4vcpu-8gb \
  --image xdc-node-20-04 \
  --ssh-keys <your-key-id>
```

### Pros
- Simple, predictable pricing
- Excellent documentation
- 1-Click Apps marketplace
- Great community

### Cons
- Higher cost per resource
- Limited storage on droplets
- Bandwidth limits (5TB/mo)

**[➡️ Get Started with DigitalOcean](https://www.digitalocean.com)** *(affiliate link placeholder - $200 credit for 60 days)*

---

## Vultr

![Vultr Logo](https://img.shields.io/badge/Vultr-0066cc?style=flat-square&logo=vultr&logoColor=white)

Flexible cloud provider with high-performance options.

### Pricing

| Plan | vCPUs | RAM | Storage | Price | XDC Suitability |
|------|-------|-----|---------|-------|-----------------|
| Cloud 1GB | 1 | 1 GB | 25 GB SSD | $5/mo | ❌ Too small |
| Cloud 2GB | 1 | 2 GB | 50 GB SSD | $10/mo | ⚠️ Devnet |
| Cloud 4GB | 2 | 4 GB | 80 GB SSD | $20/mo | ✅ Testnet |
| Cloud 8GB | 4 | 8 GB | 160 GB SSD | $40/mo | ✅ Mainnet |
| Cloud 16GB | 4 | 16 GB | 320 GB SSD | $80/mo | ✅✅ Mainnet |

### Recommended Specs

- **Mainnet**: Cloud 16GB (4 vCPUs, 16GB RAM, 320GB SSD)

### Data Centers

25+ locations worldwide including:
- North America: 9 locations
- Europe: 8 locations
- Asia: 6 locations
- Australia: 2 locations

### Setup Notes

```bash
# Deploy via Vultr API
curl -X POST https://api.vultr.com/v2/instances \
  -H "Authorization: Bearer $VULTR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "region": "ewr",
    "plan": "vc2-4c-8gb",
    "os_id": 1743,
    "label": "xdc-node"
  }'
```

### Pros
- Huge global network
- NVMe storage options
- Competitive pricing
- Hourly billing

### Cons
- Support costs extra
- Smaller ecosystem than AWS/GCP

**[➡️ Get Started with Vultr](https://www.vultr.com)** *(affiliate link placeholder - $100 credit)*

---

## OVHcloud

![OVHcloud Logo](https://img.shields.io/badge/OVHcloud-000E9C?style=flat-square&logo=ovh&logoColor=white)

European cloud provider with strong data sovereignty focus.

### Pricing

| Plan | vCPUs | RAM | Storage | Price | XDC Suitability |
|------|-------|-----|---------|-------|-----------------|
| C2-7 | 1 | 2 GB | 25 GB SSD | €7/mo | ⚠️ Devnet |
| B2-7 | 2 | 4 GB | 50 GB SSD | €13/mo | ✅ Testnet |
| B2-15 | 4 | 8 GB | 100 GB SSD | €22/mo | ✅ Mainnet |
| B2-30 | 8 | 16 GB | 200 GB SSD | €45/mo | ✅✅ Mainnet |
| B2-60 | 16 | 32 GB | 400 GB SSD | €91/mo | ✅✅ Archive |

### Recommended Specs

- **Mainnet**: B2-30 (8 vCPUs, 16GB RAM, 200GB SSD)

### Data Centers

- France (Gravelines, Roubaix, Strasbourg)
- Canada (Beauharnois)
- Germany (Frankfurt)
- Poland (Warsaw)
- United Kingdom (London)
- Australia (Sydney)
- Singapore
- India (Mumbai)

### Setup Notes

```bash
# OVHcloud offers anti-DDoS protection included
# Standard setup works well

curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/install.sh | sudo bash
```

### Pros
- GDPR compliant (EU company)
- Anti-DDoS included
- Good EU network
- Competitive pricing

### Cons
- Smaller US presence
- Complex control panel
- Support can be slow

**[➡️ Get Started with OVHcloud](https://www.ovhcloud.com)** *(affiliate link placeholder)*

---

## Amazon Web Services

![AWS Logo](https://img.shields.io/badge/AWS-FF9900?style=flat-square&logo=amazonaws&logoColor=white)

Enterprise-grade cloud platform with maximum flexibility.

### Pricing (on-demand, us-east-1)

| Instance | vCPUs | RAM | Storage | Est. Monthly | XDC Suitability |
|----------|-------|-----|---------|--------------|-----------------|
| t3.medium | 2 | 4 GB | EBS only | ~$35/mo | ⚠️ Testnet |
| t3.large | 2 | 8 GB | EBS only | ~$60/mo | ✅ Mainnet |
| t3.xlarge | 4 | 16 GB | EBS only | ~$120/mo | ✅✅ Mainnet |
| m5.large | 2 | 8 GB | EBS only | ~$70/mo | ✅ Mainnet |
| m5.xlarge | 4 | 16 GB | EBS only | ~$140/mo | ✅✅ Mainnet |

**Note:** Storage costs extra (~$0.10/GB/month for gp3)

### Recommended Specs

- **Mainnet**: t3.xlarge (4 vCPUs, 16GB RAM) + 500GB gp3 volume (~$140/mo total)

### Data Centers

30+ regions worldwide including:
- US East (N. Virginia, Ohio)
- US West (N. California, Oregon)
- Europe (Ireland, London, Frankfurt, Paris, Stockholm)
- Asia Pacific (Singapore, Sydney, Tokyo, Mumbai, Seoul)
- South America (São Paulo)
- Middle East (Bahrain, UAE)

### Setup Notes

```bash
# Use the CloudFormation template
aws cloudformation create-stack \
  --stack-name xdc-node \
  --template-url https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/cloud/aws/cloudformation.yaml \
  --parameters ParameterKey=InstanceType,ParameterValue=t3.xlarge

# Or use the AMI directly
aws ec2 run-instances \
  --image-id ami-xxxxxxxxxxxxxxxxx \
  --instance-type t3.xlarge
```

### Pros
- Massive global infrastructure
- Extensive services ecosystem
- Enterprise support options
- Reserved instance discounts

### Cons
- Complex pricing
- Higher costs
- Steep learning curve
- Egress fees

**[➡️ Get Started with AWS](https://aws.amazon.com)** *(affiliate link placeholder)*

---

## Quick Start by Provider

### One-Liner Deployments

```bash
# Hetzner
hcloud server create --name xdc-node --type cpx31 --image ubuntu-22.04

# DigitalOcean
doctl compute droplet create xdc-node --region nyc3 --size s-4vcpu-8gb --image ubuntu-22-04-x64

# Vultr
curl -X POST "https://api.vultr.com/v2/instances" \
  -H "Authorization: Bearer $VULTR_API_KEY" \
  -d '{"region":"ewr","plan":"vc2-4c-8gb","os_id":1743}'

# AWS
aws ec2 run-instances --image-id ami-xxx --instance-type t3.xlarge
```

Then run the installer on all:
```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/install.sh | sudo bash
```

---

## Provider Comparison Matrix

| Feature | Hetzner | Contabo | DigitalOcean | Vultr | OVHcloud | AWS |
|---------|---------|---------|--------------|-------|----------|-----|
| **Price** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Performance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Global Network** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Ease of Use** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Support** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Enterprise Features** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## Notes

### Affiliate Links

The links in this document may contain affiliate codes. Using these links helps support the XDC Node Setup project at no additional cost to you.

### Verification

Providers listed here have been verified to work with XDC Node Setup. Requirements for verification:
- Successfully runs XDC Node Setup
- Meets minimum specs (4GB RAM, 100GB storage)
- Stable network connectivity
- Reasonable pricing

### Updates

This list is maintained by the XDC Node Setup community. To add a provider:
1. Test the provider with XDC Node Setup
2. Document pricing and specs
3. Submit a PR to update this file

### Disclaimer

Prices and specs are subject to change. Always verify current pricing on the provider's website. Performance may vary based on location and network conditions.

---

## Related Commands

Open this documentation from the CLI:
```bash
xdc marketplace
```

This will open `https://github.com/AnilChinchawale/XDC-Node-Setup/blob/main/docs/HOSTING-PROVIDERS.md` in your browser.
