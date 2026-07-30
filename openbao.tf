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
        tlsDisable = false
      }

      injector = {
        enabled         = true
        replicas        = local.is_ha ? 2 : 1
        externalBaoAddr = "https://openbao-internal.openbao.svc:8200"
        agentImage = {
          tag = local.versions.openbao
        }
        webhook = {
          failurePolicy = "Fail"
          namespaceSelector = {
            matchLabels = {
              "openbao.asol.io/injection" = "enabled"
            }
          }
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
          path = "/v1/sys/health?standbyok=true&uninitcode=204"
        }
        extraEnvironmentVars = {
          BAO_CACERT          = "/openbao/tls/ca.crt"
          BAO_TLS_SERVER_NAME = "openbao-internal"
        }
        ingress = {
          enabled = false
        }
        volumes = [
          {
            name = "tls"
            secret = {
              secretName  = var.openbao_tls_secret_name
              defaultMode = 288
            }
          }
        ]
        volumeMounts = [
          {
            name      = "tls"
            mountPath = "/openbao/tls"
            readOnly  = true
          }
        ]
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

              listener "tcp" {
                tls_disable = 0
                tls_cert_file = "/openbao/tls/tls.crt"
                tls_key_file = "/openbao/tls/tls.key"
                address = "[::]:8200"
                cluster_address = "[::]:8201"
              }

              storage "raft" {
                path = "/openbao/data"

                retry_join {
                  leader_api_addr = "https://openbao-0.openbao-internal:8200"
                  leader_tls_servername = "openbao-internal"
                  leader_client_cert_file = "/openbao/tls/tls.crt"
                  leader_client_key_file = "/openbao/tls/tls.key"
                  leader_ca_cert_file = "/openbao/tls/ca.crt"
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

resource "kubernetes_manifest" "openbao_ingress_route_tcp" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"
    metadata = {
      name      = "openbao"
      namespace = kubernetes_namespace_v1.openbao.metadata[0].name
      labels    = local.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "HostSNI(`${var.openbao_hostname}`)"
          services = [
            {
              name = "openbao-active"
              port = 8200
            }
          ]
        }
      ]
      tls = {
        passthrough = true
      }
    }
  }

  depends_on = [helm_release.openbao]
}
