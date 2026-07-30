resource "kubernetes_network_policy_v1" "object_storage_ingress" {
  metadata {
    name      = "object-storage-ingress"
    namespace = kubernetes_namespace_v1.object_storage.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = local.namespaces.object_storage
          }
        }
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = local.namespaces.registry
          }
        }
      }

      ports {
        port     = "8333"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "openbao_ingress" {
  metadata {
    name      = "openbao-ingress"
    namespace = kubernetes_namespace_v1.openbao.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "openbao"
        component                = "server"
      }
    }
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = local.namespaces.openbao
          }
        }
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }

      ports {
        port     = "8200"
        protocol = "TCP"
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "openbao.asol.io/injection" = "enabled"
          }
        }
      }

      ports {
        port     = "8200"
        protocol = "TCP"
      }
    }
  }
}
