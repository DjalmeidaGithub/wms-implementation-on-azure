# WMS Hybrid Architecture Design

## High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            AZURE CLOUD INFRASTRUCTURE                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────────────────┐ │
│  │   FRONT DOOR    │  │  TRAFFIC MANAGER │  │     APPLICATION GATEWAY     │ │
│  │   Global LB     │  │   DNS-based LB   │  │      WAF + SSL Term        │ │
│  │  + CDN + WAF    │  │                  │  │                             │ │
│  └─────────────────┘  └──────────────────┘  └─────────────────────────────┘ │
│           │                      │                           │               │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        PRIMARY REGION (East US 2)                       │ │
│  │  ┌─────────────────────────────────────────────────────────────────────│ │
│  │  │                       VIRTUAL NETWORK                              │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────────────────│ │
│  │  │  │     AKS      │  │     VMSS     │  │      DATABASES              │ │
│  │  │  │ Kubernetes   │  │   Legacy     │  │                             │ │
│  │  │  │ Microservices│  │  Windows     │  │  ┌─────────┐  ┌────────────┐ │ │
│  │  │  │              │  │  Services    │  │  │ SQL DB  │  │  CosmosDB  │ │ │
│  │  │  │ ┌──────────┐ │  │              │  │  │ Primary │  │ Real-time  │ │ │
│  │  │  │ │Inventory │ │  │ ┌──────────┐ │  │  │ + Pools │  │  + Scale   │ │ │
│  │  │  │ │ Service  │ │  │ │WMS Legacy│ │  │  └─────────┘  └────────────┘ │ │
│  │  │  │ └──────────┘ │  │ │Services  │ │  │                             │ │
│  │  │  │ ┌──────────┐ │  │ └──────────┘ │  │  ┌─────────────────────────┐ │ │
│  │  │  │ │ Order    │ │  │ ┌──────────┐ │  │  │      REDIS CACHE        │ │ │
│  │  │  │ │ Service  │ │  │ │EDI/B2B   │ │  │  │  Standard + Enterprise  │ │ │
│  │  │  │ └──────────┘ │  │ │Gateway   │ │  │  │    Session + Data       │ │ │
│  │  │  │ ┌──────────┐ │  │ └──────────┘ │  │  └─────────────────────────┘ │ │
│  │  │  │ │ Picking  │ │  └──────────────┘  └─────────────────────────────│ │
│  │  │  │ │ Service  │ │                                                   │ │
│  │  │  │ └──────────┘ │  ┌─────────────────────────────────────────────┐ │ │
│  │  │  │ ┌──────────┐ │  │              SECURITY LAYER                 │ │ │
│  │  │  │ │Shipping  │ │  │                                             │ │ │
│  │  │  │ │ Service  │ │  │  ┌──────────┐  ┌──────────────────────────┐ │ │ │
│  │  │  │ └──────────┘ │  │  │   AAD    │  │       KEY VAULT          │ │ │ │
│  │  │  └──────────────┘  │  │Identity  │  │   Secrets + Certificates │ │ │ │
│  │  └───────────────────────│   RBAC   │  │      + HSM Keys          │ │ │ │
│  └─────────────────────────────│        │  └──────────────────────────┘ │ │ │
│                               └──────────┘                              │ │ │
│  ┌─────────────────────────────────────────────────────────────────────┐ │ │
│  │                      MONITORING & OBSERVABILITY                     │ │ │
│  │  ┌────────────────┐  ┌─────────────┐  ┌────────────────────────────┐ │ │ │
│  │  │  LOG ANALYTICS │  │ APP INSIGHTS│  │       AZURE MONITOR        │ │ │ │
│  │  │   Centralized  │  │  APM + RUM  │  │   Metrics + Alerts +       │ │ │ │
│  │  │    Logging     │  │             │  │      Dashboards            │ │ │ │
│  │  └────────────────┘  └─────────────┘  └────────────────────────────┘ │ │ │
│  └─────────────────────────────────────────────────────────────────────┘ │ │
│                                                                         │ │
│  ┌─────────────────────────────────────────────────────────────────────┐ │ │
│  │                       DATA & ANALYTICS                              │ │ │
│  │  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────────────┐ │ │ │
│  │  │    BLOB     │  │DATA FACTORY  │  │        POWER BI              │ │ │ │
│  │  │  STORAGE    │  │ ETL Pipeline │  │   Dashboards + Reports       │ │ │ │
│  │  │Hot/Cool/Arc │  │              │  │                              │ │ │ │
│  │  └─────────────┘  └──────────────┘  └──────────────────────────────┘ │ │ │
│  └─────────────────────────────────────────────────────────────────────┘ │ │
└───────────────────────────────────────────────────────────────────────────│ │
                                                                            │ │
┌─────────────────────────────────────────────────────────────────────────┐ │ │
│                       SECONDARY REGION (West US 2)                      │ │ │
│                            DISASTER RECOVERY                             │ │ │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │ │ │
│  │  SQL FAILOVER   │  │   REDIS GEO     │  │     COSMOS DB GEO      │ │ │ │
│  │     GROUP       │  │  REPLICATION    │  │     REPLICATION        │ │ │ │
│  │   (Read-only)   │  │                 │  │                        │ │ │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────┘ │ │ │
└─────────────────────────────────────────────────────────────────────────┘ │ │
                                    ▲                                      │ │
                                    │                                      │ │
┌─────────────────────────────────────────────────────────────────────────┐ │ │
│                           HYBRID CONNECTIVITY                           │ │ │
│                                                                         │ │ │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │ │ │
│  │  VPN GATEWAY    │  │  EXPRESSROUTE   │  │    DATA FACTORY         │ │ │ │
│  │   Site-to-Site  │  │   Dedicated     │  │  Self-hosted IR         │ │ │ │
│  │   IPSec + BGP   │  │   Connection    │  │                         │ │ │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────┘ │ │ │
└─────────────────────────────────────────────────────────────────────────┘ │ │
                    │                   │                   │               │ │
┌─────────────────────────────────────────────────────────────────────────┐ │ │
│                         ON-PREMISES INFRASTRUCTURE                       │ │ │
│                                                                         │ │ │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │ │ │
│  │  LEGACY WMS     │  │   SQL SERVER    │  │      WAREHOUSE          │ │ │ │
│  │   SYSTEMS       │  │    DATABASE     │  │      HARDWARE           │ │ │ │
│  │                 │  │                 │  │                         │ │ │ │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │  ┌─────────────────────┐ │ │ │
│  │ │  WMS Core   │ │  │ │   Master    │ │  │  │ Barcode Scanners    │ │ │ │
│  │ │  Services   │ │  │ │  Database   │ │  │  │ RFID Readers        │ │ │ │
│  │ └─────────────┘ │  │ └─────────────┘ │  │  │ Label Printers      │ │ │ │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │  │ Conveyor Systems    │ │ │ │
│  │ │   WCS       │ │  │ │  Reporting  │ │  │  │ Voice Picking       │ │ │ │
│  │ │ Integration │ │  │ │   Database  │ │  │  │ Dock Door Sensors   │ │ │ │
│  │ └─────────────┘ │  │ └─────────────┘ │  │  └─────────────────────┘ │ │ │
│  │ ┌─────────────┐ │  └─────────────────┘  └─────────────────────────┘ │ │ │
│  │ │    EDI      │ │                                                   │ │ │
│  │ │  Gateway    │ │                                                   │ │ │
│  │ └─────────────┘ │                                                   │ │ │
│  └─────────────────┘                                                   │ │ │
└─────────────────────────────────────────────────────────────────────────┘ │ │
                                                                            └─┘
```

## Component Architecture Details

### 1. Load Balancing & Traffic Distribution

#### Azure Front Door (Global)
- **Global load balancing** with anycast networking
- **CDN integration** for static content acceleration
- **Web Application Firewall** with OWASP rule sets
- **SSL termination** and certificate management
- **Health probe monitoring** across regions
- **Caching rules** for API responses and static assets

#### Traffic Manager (DNS-based)
- **Performance routing** based on latency
- **Geographic routing** for compliance requirements
- **Failover routing** for disaster recovery
- **Weighted routing** for blue-green deployments

#### Application Gateway (Regional)
- **Layer 7 load balancing** with cookie affinity
- **SSL offloading** with Key Vault integration
- **WAF protection** against common threats
- **Auto-scaling** based on request volume
- **Backend health monitoring**

### 2. Compute Layer Architecture

#### Azure Kubernetes Service (AKS)
```yaml
Cluster Configuration:
- Version: 1.28+
- Node Pools:
  - System Pool: 2-10 nodes (Standard_D4s_v3)
  - WMS Pool: 2-20 nodes (Standard_D8s_v3)
- Network: Azure CNI with Calico policy
- Identity: System-assigned managed identity
- Monitoring: Azure Monitor for containers
- Security: Azure AD integration + RBAC

Microservices Architecture:
├── Inventory Service (3 replicas)
├── Order Service (3 replicas)
├── Picking Service (2 replicas)
├── Shipping Service (2 replicas)
└── Reporting Service (1 replica)
```

#### Virtual Machine Scale Set (Legacy)
```yaml
Configuration:
- OS: Windows Server 2022 Datacenter
- Size: Standard_D4s_v3
- Instances: 2-10 (auto-scaling)
- Storage: Premium SSD
- Network: Internal load balancer
- Updates: Automatic OS upgrades
- Monitoring: Azure Monitor Agent

Legacy Services:
├── WMS Core Services (.NET Framework)
├── EDI Processing Services
├── Label Printing Services
├── Warehouse Control System (WCS) Integration
└── Crystal Reports Services
```

### 3. Data Architecture

#### Primary Database Layer
```sql
Azure SQL Database Configuration:
├── Server: Primary (East US 2)
├── Database: WMS_Primary (P2 tier)
├── Elastic Pool: Tenant databases (Standard)
├── Backup: 35-day retention + LTR
├── Security: TDE + Always Encrypted
├── Monitoring: Query insights + alerts
└── Scaling: Auto-scale based on DTU

Failover Group (DR):
├── Primary: East US 2
├── Secondary: West US 2 (Read-only)
├── Failover: Automatic (1-hour grace period)
└── Applications: Connection string redirection
```

#### Real-time Data Layer
```json
CosmosDB Configuration:
{
  "account": "wms-cosmos-eus2",
  "consistencyLevel": "Session",
  "multiRegionWrites": false,
  "geoReplication": [
    {"region": "East US 2", "priority": 0},
    {"region": "West US 2", "priority": 1}
  ],
  "containers": [
    {
      "name": "inventory-tracking",
      "partitionKey": "/warehouseId",
      "throughput": "800-8000 RU/s (autoscale)"
    },
    {
      "name": "order-tracking",
      "partitionKey": "/orderId",
      "throughput": "600-6000 RU/s (autoscale)",
      "ttl": 2592000
    }
  ]
}
```

### 4. Caching Architecture

#### Redis Cache Layers
```yaml
Primary Redis (Premium P3):
- Capacity: 13 GB memory
- Features: Persistence, clustering, geo-replication
- Use Cases: Session state, API responses
- Backup: RDB snapshots to storage

Redis Enterprise:
- Modules: RedisJSON, RedisTimeSeries, RediSearch
- Clustering: Multi-shard configuration
- Use Cases: Real-time analytics, search
- Performance: Sub-millisecond latency
```

#### CDN Strategy
```yaml
Azure CDN (Microsoft):
- Origin: Storage account static content
- Caching Rules:
  - Static assets (CSS, JS, images): 7 days
  - API responses: 5 minutes
  - Dynamic content: No cache
- Compression: Enabled for text files
- HTTPS: Enforced with redirect rules
```

### 5. Security Architecture

#### Identity & Access Management
```yaml
Azure Active Directory Integration:
├── SSO Configuration
├── Multi-factor Authentication
├── Conditional Access Policies
├── B2B Guest Access (partners/vendors)
└── Device-based Access Controls

RBAC Roles:
├── WMS Administrators (Full access)
├── WMS Operators (Operational access)
├── WMS Read-only (Reporting access)
├── SQL Administrators (Database access)
└── Custom WMS Operator Role
```

#### Network Security
```yaml
Network Segmentation:
├── Gateway Subnet (10.0.1.0/27)
├── AKS Subnet (10.0.10.0/24)
├── VMSS Subnet (10.0.20.0/24)
├── Database Subnet (10.0.30.0/24)
├── Private Endpoints (10.0.40.0/24)
└── App Gateway Subnet (10.0.50.0/24)

Security Controls:
├── Network Security Groups (NSGs)
├── Azure Firewall Premium
├── DDoS Protection Standard
├── Private Endpoints for PaaS
├── Just-in-Time VM Access
└── Azure Bastion for Management
```

#### Data Protection
```yaml
Encryption Strategy:
├── Data at Rest:
│   ├── SQL TDE with customer-managed keys
│   ├── Storage encryption with Key Vault keys
│   ├── CosmosDB automatic encryption
│   └── VM disk encryption (BitLocker/dm-crypt)
├── Data in Transit:
│   ├── TLS 1.2+ for all connections
│   ├── VPN IPSec encryption
│   ├── Certificate-based authentication
│   └── Service-to-service encrypted channels
└── Key Management:
    ├── Azure Key Vault Premium (HSM)
    ├── Automatic key rotation
    ├── Separate keys per environment
    └── Access policies with just-in-time
```

### 6. Monitoring & Observability

#### Application Performance Monitoring
```yaml
Application Insights:
├── End-to-end request tracing
├── Custom telemetry for WMS operations
├── Real user monitoring (RUM)
├── Synthetic availability tests
├── Performance counters
└── Exception tracking with stack traces

Custom Metrics:
├── Order processing rate (orders/hour)
├── Pick path efficiency (time/pick)
├── Inventory accuracy percentage
├── Shipping carrier performance
└── User session duration
```

#### Infrastructure Monitoring
```yaml
Azure Monitor Stack:
├── Platform Metrics:
│   ├── VM/VMSS CPU, memory, disk I/O
│   ├── AKS pod metrics and resource usage
│   ├── Database DTU and query performance
│   └── Network throughput and latency
├── Custom Logs:
│   ├── WMS application logs
│   ├── Security audit logs
│   ├── Performance logs
│   └── Integration point logs
└── Alerting:
    ├── Critical: Page oncall team
    ├── Warning: Email operations team
    ├── Info: Log for analysis
    └── Automated remediation where possible
```

### 7. Hybrid Connectivity

#### VPN Gateway Configuration
```yaml
Gateway Type: VPN
VPN Type: Route-based (BGP enabled)
SKU: VpnGw2 (up to 1.25 Gbps)
Active-Active: Disabled
BGP ASN: 65515 (Azure side)

On-premises Requirements:
├── Public IP address
├── VPN device supporting BGP
├── ASN: 65001 (on-premises)
├── Pre-shared key (stored in Key Vault)
└── Route advertisements for internal subnets
```

#### ExpressRoute (Optional)
```yaml
Circuit Configuration:
├── Provider: Partner/Direct connection
├── Bandwidth: 1 Gbps minimum
├── Peering: Private peering enabled
├── Redundancy: Dual circuits for HA
├── SLA: 99.95% uptime guarantee
└── BGP Communities: For traffic engineering
```

#### Data Integration
```yaml
Azure Data Factory:
├── Self-hosted Integration Runtime
├── Hybrid data movement pipelines
├── Real-time and batch processing
├── Data transformation with mapping flows
├── Monitoring and alerting integration
└── Git integration for CI/CD
```

### 8. Disaster Recovery Architecture

#### Recovery Objectives
```yaml
RTO (Recovery Time Objective):
├── Critical: < 1 hour (Tier 1 services)
├── Important: < 4 hours (Tier 2 services)
├── Standard: < 8 hours (Tier 3 services)
└── Low Priority: < 24 hours (Reporting/Analytics)

RPO (Recovery Point Objective):
├── Critical: < 15 minutes (Real-time data)
├── Important: < 1 hour (Transactional data)
├── Standard: < 4 hours (Configuration data)
└── Low Priority: < 24 hours (Historical data)
```

#### Failover Strategy
```yaml
Automated Failover:
├── SQL Failover Groups (automatic)
├── CosmosDB geo-replication (manual trigger)
├── Traffic Manager health checks
├── AKS cross-region deployment (GitOps)
└── Storage account geo-redundancy

Manual Processes:
├── Application configuration updates
├── DNS record modifications
├── Certificate renewal and binding
├── User communication and training
└── Post-failover validation testing
```

## Integration Patterns

### 1. API Gateway Pattern
```yaml
Implementation: Azure API Management
Features:
├── Rate limiting and throttling
├── Authentication and authorization
├── Request/response transformation
├── Caching for frequently accessed data
├── Analytics and monitoring
└── Developer portal for API documentation
```

### 2. Event-Driven Architecture
```yaml
Implementation: Azure Service Bus + Event Grid
Patterns:
├── Publish/Subscribe for inventory updates
├── Request/Reply for synchronous operations
├── Competing Consumers for order processing
├── Message routing based on content
└── Dead letter queues for error handling
```

### 3. Database Synchronization
```yaml
Implementation: Azure Data Factory + SQL Data Sync
Strategies:
├── Real-time: Change Data Capture (CDC)
├── Near real-time: Service Bus messaging
├── Batch: Scheduled ETL processes
├── Conflict resolution: Last-writer-wins
└── Schema evolution: Version compatibility
```

### 4. Microservices Communication
```yaml
Synchronous:
├── HTTP/HTTPS REST APIs
├── GraphQL for flexible queries
├── gRPC for high-performance calls
└── Circuit breaker pattern

Asynchronous:
├── Service Bus queues/topics
├── Event Grid for event routing
├── Azure Relay for hybrid scenarios
└── SignalR for real-time notifications
```

## Cost Optimization Strategies

### 1. Compute Optimization
```yaml
Strategies:
├── Auto-scaling: Scale down during off-hours
├── Spot Instances: 90% savings for dev/test
├── Reserved Instances: 30-60% savings for production
├── Right-sizing: Regular analysis and adjustment
├── Azure Hybrid Benefit: Windows Server licenses
└── Dev/Test pricing: Visual Studio subscribers
```

### 2. Storage Optimization
```yaml
Lifecycle Management:
├── Hot → Cool: After 30 days
├── Cool → Archive: After 90 days
├── Deletion: After 7 years (compliance)
├── Snapshot retention: 90 days
└── Backup retention: 35 days standard
```

### 3. Database Optimization
```yaml
Cost Controls:
├── Elastic pools: Shared DTU for tenants
├── Auto-pause: Serverless for dev databases
├── Read replicas: Offload reporting queries
├── Query optimization: Reduce DTU consumption
└── Archival: Move old data to cheaper storage
```

## Security Controls Summary

### Compliance Framework
```yaml
Standards Addressed:
├── SOC 2 Type II
├── PCI DSS (if handling payment data)
├── GDPR (for EU operations)
├── HIPAA (if handling health data)
├── ISO 27001
└── Azure Security Benchmark
```

### Security Monitoring
```yaml
Azure Security Center:
├── Secure Score monitoring
├── Vulnerability assessments
├── Just-in-time VM access
├── Adaptive network hardening
├── File integrity monitoring
└── Threat intelligence integration

Azure Sentinel (Optional):
├── SIEM capabilities
├── Security playbooks
├── Threat hunting queries
├── User behavior analytics
└── Integration with 3rd party tools
```

This architecture provides a comprehensive, scalable, and secure foundation for modern warehouse management operations with seamless hybrid connectivity and robust disaster recovery capabilities.
