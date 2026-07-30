locals {
  is_ha = var.deployment_profile == "ha"

  versions = {
    k3s                         = "v1.36.2+k3s1"
    longhorn_chart              = "1.12.0"
    seaweedfs_chart             = "4.40.0"
    seaweedfs                   = "4.40"
    harbor_chart                = "1.19.1"
    harbor                      = "v2.15.2"
    harbor_redis                = "v2.15.1"
    openbao_chart               = "0.28.6"
    openbao                     = "2.6.1"
    azure_pipelines_agent       = "3.238.0"
    azure_pipelines_agent_image = "2022.2-3.238.0"
    sonarqube_azdo_extension    = "8.2.3.2750"
    sonar_scanner_cli           = "8.1.0.6389"
    sonar_scanner_dotnet        = "11.2.1.137242"
  }

  longhorn_replica_count  = local.is_ha ? 3 : 1
  seaweed_master_replicas = local.is_ha ? 3 : 1
  seaweed_volume_replicas = local.is_ha ? 3 : 1
  seaweed_s3_replicas     = local.is_ha ? 2 : 1
  seaweed_replication     = local.is_ha ? "001" : "000"
  openbao_replicas        = local.is_ha ? 3 : 1

  block_storage_class = "longhorn"
  seaweed_s3_endpoint = "http://seaweedfs-s3.object-storage.svc.cluster.local:8333"

  namespaces = {
    longhorn        = "longhorn-system"
    object_storage  = "object-storage"
    registry        = "registry"
    openbao         = "openbao"
    azure_pipelines = "azure-pipelines"
  }

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "platform.asol.io/stack"       = "internal-developer-platform"
  }
}
