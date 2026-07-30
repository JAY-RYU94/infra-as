resource "helm_release" "harbor" {
  name       = "harbor"
  namespace  = kubernetes_namespace_v1.registry.metadata[0].name
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = local.versions.harbor_chart

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1200
  wait            = true
  wait_for_jobs   = true

  values = [
    yamlencode({
      externalURL = "https://${var.harbor_hostname}"

      expose = {
        type = "ingress"
        tls = {
          enabled    = true
          certSource = "secret"
          secret = {
            secretName = var.harbor_tls_secret_name
          }
        }
        ingress = {
          className = var.ingress_class_name
          hosts = {
            core = var.harbor_hostname
          }
          annotations = {
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
            "traefik.ingress.kubernetes.io/router.tls"         = "true"
          }
        }
      }

      persistence = {
        enabled        = true
        resourcePolicy = "keep"
        persistentVolumeClaim = {
          jobservice = {
            jobLog = {
              storageClass = local.block_storage_class
              size         = "5Gi"
            }
          }
          database = {
            storageClass = local.block_storage_class
            size         = "10Gi"
          }
          redis = {
            storageClass = local.block_storage_class
            size         = "5Gi"
          }
          trivy = {
            storageClass = local.block_storage_class
            size         = "10Gi"
          }
        }
        imageChartStorage = {
          type            = "s3"
          disableredirect = true
          s3 = {
            region         = "us-east-1"
            bucket         = var.harbor_bucket_name
            regionendpoint = local.seaweed_s3_endpoint
            secure         = false
            skipverify     = false
            v4auth         = true
            chunksize      = "5242880"
            rootdirectory  = "/harbor"
          }
        }
      }

      updateStrategy = {
        type = "Recreate"
      }

      internalTLS = {
        enabled = true
      }

      metrics = {
        enabled = true
      }

      trivy = {
        enabled       = true
        vulnType      = "os,library"
        severity      = "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL"
        ignoreUnfixed = false
        image = {
          tag = local.versions.harbor
        }
      }

      nginx = {
        image = {
          tag = local.versions.harbor
        }
      }
      portal = {
        image = {
          tag = local.versions.harbor
        }
      }
      core = {
        image = {
          tag = local.versions.harbor
        }
      }
      jobservice = {
        image = {
          tag = local.versions.harbor
        }
      }
      registry = {
        registry = {
          image = {
            tag = local.versions.harbor
          }
        }
        controller = {
          image = {
            tag = local.versions.harbor
          }
        }
      }
      database = {
        internal = {
          image = {
            tag = local.versions.harbor
          }
        }
      }
      redis = {
        internal = {
          image = {
            tag = local.versions.harbor_redis
          }
        }
      }
      exporter = {
        image = {
          tag = local.versions.harbor
        }
      }
    })
  ]

  set_wo = [
    {
      name  = "harborAdminPassword"
      value = var.harbor_admin_password
    },
    {
      name  = "secretKey"
      value = var.harbor_secret_key
    },
    {
      name  = "persistence.imageChartStorage.s3.accesskey"
      value = var.seaweedfs_s3_access_key
    },
    {
      name  = "persistence.imageChartStorage.s3.secretkey"
      value = var.seaweedfs_s3_secret_key
    }
  ]
  set_wo_revision = var.bootstrap_secret_revision

  depends_on = [helm_release.seaweedfs]
}
