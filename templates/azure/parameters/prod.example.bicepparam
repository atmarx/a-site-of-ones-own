// Example only. deploy.ps1 supplies production values without persisting them.
using '../main.bicep'

param location = 'eastus'
param namePrefix = 'rwh'
param environment = 'prod'
param adminUsername = 'webadmin'

// Replace with an OpenSSH public key, never a private PEM key.
param sshPublicKey = 'ssh-ed25519 REPLACE_WITH_PUBLIC_KEY'

// Replace this documentation-only value with trusted public NAT egress
// addresses. deploy.ps1 rejects this placeholder, private ranges, and 0.0.0.0/0.
param adminSourceCidrs = [
  '203.0.113.10/32'
]

param owner = 'Research Web Hosting'
param dataClassification = 'Public'
param vmSize = 'Standard_D2as_v7'
param osDiskSizeGB = 32
param osDiskSku = 'StandardSSD_LRS'
param dataDiskSizeGB = 64
param dataDiskSku = 'StandardSSD_LRS'
param enableDeletionLocks = true

param tags = {
  CostCenter: 'REPLACE_WITH_COST_CENTER'
  Service: 'ResearchWebHosting'
}
