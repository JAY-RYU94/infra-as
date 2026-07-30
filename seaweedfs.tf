resource "helm_release" "seaweedfs" {
  name       = "seaweedfs"
  namespace  = kubernetes_namespace_v1.object_storage.metadata[0].name
  repository = "https://seaweedfs.github.io/seaweedfs/helm"
  chart      = "seaweedfs"
  version    = local.versions.seaweedfs_chart

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1200
  wait            = true
  wait_for_jobs   = true

  values = [
    yamlencode({
      image = {
        tag = local.versions.seaweedfs
      }

      global = {
        seaweedfs = {
          imagePullPolicy      = "IfNotPresent"
          enableSecurity       = false
          enableReplication    = local.is_ha
          replicationPlacement = local.seaweed_replication
          monitoring = {
            enabled = false
          }
        }
      }

      master = {
        replicas           = local.seaweed_master_replicas
        defaultReplication = local.seaweed_replication
        volumeSizeLimitMB  = 30000
        data = {
          type         = "persistentVolumeClaim"
          size         = "5Gi"
          storageClass = local.block_storage_class
        }
        logs = {
          type = "emptyDir"
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            memory = "1Gi"
          }
        }
      }

      volume = {
        replicas = local.seaweed_volume_replicas
        dataDirs = [
          {
            name         = "data"
            type         = "persistentVolumeClaim"
            size         = var.object_data_volume_size
            storageClass = var.object_data_storage_class
            maxVolumes   = 0
          }
        ]
        logs = {
          type = "emptyDir"
        }
        resources = {
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
          limits = {
            memory = "2Gi"
          }
        }
      }

      filer = {
        replicas                = 1
        defaultReplicaPlacement = local.seaweed_replication
        encryptVolumeData       = true
        data = {
          type         = "persistentVolumeClaim"
          size         = "10Gi"
          storageClass = local.block_storage_class
        }
        logs = {
          type = "emptyDir"
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            memory = "1Gi"
          }
        }
      }

      s3 = {
        enabled    = true
        replicas   = local.seaweed_s3_replicas
        enableAuth = true
        createBuckets = [
          {
            name          = var.harbor_bucket_name
            anonymousRead = false
          }
        ]
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled = false
        }
        logs = {
          type = "emptyDir"
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            memory = "1Gi"
          }
        }
      }
    })
  ]

  set_wo = [
    {
      name  = "s3.credentials.admin.accessKey"
      value = var.seaweedfs_s3_access_key
    },
    {
      name  = "s3.credentials.admin.secretKey"
      value = var.seaweedfs_s3_secret_key
    }
  ]
  set_wo_revision = var.bootstrap_secret_revision

  depends_on = [helm_release.longhorn]
}
