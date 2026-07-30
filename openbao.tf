resource "helm_release" "openbao" {
  name       = "openbao"
  namespace  = kubernetes_namespace_v1.openbao.metadata[0].name
  repository = "https://openbao.github.io/openbao-helm"
  chart      = "openbao"
  version    = local.versions.openbao_chart

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1200
  wait            = true

  values = [
    yamlencode({
      global = {
        tlsDisable = true
      }

      injector = {
        enabled  = true
        replicas = local.is_ha ? 2 : 1
        agentImage = {
          tag = local.versions.openbao
        }
        webhook = {
          failurePolicy = "Ignore"
        }
      }

      server = {
        image = {
          tag = local.versions.openbao
        }
        updateStrategyType = "OnDelete"
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            memory = "2Gi"
          }
        }
        readinessProbe = {
          path = "/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"
        }
        ingress = {
          enabled          = true
          ingressClassName = var.ingress_class_name
          activeService    = true
          annotations = {
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
            "traefik.ingress.kubernetes.io/router.tls"         = "true"
          }
          hosts = [
            {
              host  = var.openbao_hostname
              paths = ["/"]
            }
          ]
          tls = [
            {
              secretName = var.openbao_tls_secret_name
              hosts      = [var.openbao_hostname]
            }
          ]
        }
        dataStorage = {
          enabled      = true
          size         = "10Gi"
          storageClass = local.block_storage_class
          accessMode   = "ReadWriteOnce"
        }
        auditStorage = {
          enabled      = true
          size         = "10Gi"
          storageClass = local.block_storage_class
          accessMode   = "ReadWriteOnce"
        }
        persistentVolumeClaimRetentionPolicy = {
          whenDeleted = "Retain"
          whenScaled  = "Retain"
        }
        standalone = {
          enabled = false
        }
        ha = {
          enabled  = true
          replicas = local.openbao_replicas
          raft = {
            enabled   = true
            setNodeId = true
            config    = <<-EOT
              ui = true
              disable_mlock = true

              listener "tcp" {
                tls_disable = 1
                address = "[::]:8200"
                cluster_address = "[::]:8201"
              }

              storage "raft" {
                path = "/openbao/data"

                retry_join {
                  leader_api_addr = "http://openbao-0.openbao-internal:8200"
                }
              }

              service_registration "kubernetes" {}
            EOT
          }
          disruptionBudget = {
            enabled = local.is_ha
          }
        }
      }

      ui = {
        enabled     = true
        serviceType = "ClusterIP"
      }
    })
  ]

  depends_on = [helm_release.longhorn]
}
