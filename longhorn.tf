resource "helm_release" "longhorn" {
  name       = "longhorn"
  namespace  = kubernetes_namespace_v1.longhorn.metadata[0].name
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = local.versions.longhorn_chart

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1200
  wait            = true
  wait_for_jobs   = true

  values = [
    yamlencode({
      persistence = {
        createStorageClass       = true
        defaultClass             = true
        defaultFsType            = "ext4"
        defaultClassReplicaCount = local.longhorn_replica_count
        defaultDataLocality      = local.is_ha ? "best-effort" : "disabled"
        reclaimPolicy            = "Retain"
        volumeBindingMode        = "Immediate"
      }

      defaultSettings = {
        defaultDataPath                         = "/mnt/data/longhorn"
        defaultReplicaCount                     = tostring(local.longhorn_replica_count)
        replicaAutoBalance                      = local.is_ha ? "best-effort" : "disabled"
        storageOverProvisioningPercentage       = "100"
        storageMinimalAvailablePercentage       = "5"
        storageReservedPercentageForDefaultDisk = "70"
        upgradeChecker                          = false
      }

      longhornUI = {
        replicas = local.is_ha ? 2 : 1
      }

      ingress = {
        enabled = false
      }
    })
  ]
}
