locals {
  azure_agent_labels = {
    "app.kubernetes.io/name"      = "azure-pipelines-agent"
    "app.kubernetes.io/instance"  = "linux"
    "app.kubernetes.io/component" = "ci-agent"
  }
}

resource "kubernetes_service_account_v1" "azure_pipelines_agent" {
  count = var.azure_pipelines_agent_enabled ? 1 : 0

  metadata {
    name      = "azure-pipelines-agent"
    namespace = kubernetes_namespace_v1.azure_pipelines.metadata[0].name
    labels    = merge(local.common_labels, local.azure_agent_labels)
  }

  automount_service_account_token = false
}

resource "kubernetes_service_v1" "azure_pipelines_agent" {
  count = var.azure_pipelines_agent_enabled ? 1 : 0

  metadata {
    name      = "azure-pipelines-agent"
    namespace = kubernetes_namespace_v1.azure_pipelines.metadata[0].name
    labels    = merge(local.common_labels, local.azure_agent_labels)
  }

  spec {
    cluster_ip                  = "None"
    publish_not_ready_addresses = true
    selector                    = local.azure_agent_labels

    port {
      name        = "agent-dns"
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_stateful_set_v1" "azure_pipelines_agent" {
  count = var.azure_pipelines_agent_enabled ? 1 : 0

  metadata {
    name      = "azure-pipelines-agent"
    namespace = kubernetes_namespace_v1.azure_pipelines.metadata[0].name
    labels    = merge(local.common_labels, local.azure_agent_labels)
  }

  spec {
    replicas     = var.azure_pipelines_agent_replicas
    service_name = kubernetes_service_v1.azure_pipelines_agent[0].metadata[0].name

    selector {
      match_labels = local.azure_agent_labels
    }

    template {
      metadata {
        labels = merge(local.common_labels, local.azure_agent_labels)
      }

      spec {
        service_account_name             = kubernetes_service_account_v1.azure_pipelines_agent[0].metadata[0].name
        automount_service_account_token  = false
        termination_grace_period_seconds = 120

        security_context {
          run_as_non_root        = true
          run_as_user            = 10001
          run_as_group           = 10001
          fs_group               = 10001
          fs_group_change_policy = "OnRootMismatch"

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        dynamic "image_pull_secrets" {
          for_each = var.azure_pipelines_image_pull_secret_name == null ? [] : [var.azure_pipelines_image_pull_secret_name]
          content {
            name = image_pull_secrets.value
          }
        }

        container {
          name              = "agent"
          image             = var.azure_pipelines_agent_image
          image_pull_policy = "IfNotPresent"

          env {
            name  = "AZP_URL"
            value = var.azure_pipelines_url
          }
          env {
            name  = "AZP_POOL"
            value = var.azure_pipelines_pool
          }
          env {
            name = "AZP_AGENT_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name  = "AZP_TOKEN_FILE"
            value = "/run/secrets/azure-pipelines/pat"
          }
          env {
            name  = "AZP_WORK"
            value = "/azp/_work"
          }
          env {
            name  = "UV_PYTHON_INSTALL_DIR"
            value = "/azp/_work/.python"
          }
          env {
            name  = "UV_CACHE_DIR"
            value = "/azp/_work/.cache/uv"
          }
          env {
            name  = "NUGET_PACKAGES"
            value = "/azp/_work/.cache/nuget"
          }
          env {
            name  = "SONAR_USER_HOME"
            value = "/azp/_work/.cache/sonar"
          }

          resources {
            requests = var.azure_pipelines_agent_resources.requests
            limits   = var.azure_pipelines_agent_resources.limits
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = false
            run_as_non_root            = true
            run_as_user                = 10001
            run_as_group               = 10001

            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "work"
            mount_path = "/azp/_work"
          }
          volume_mount {
            name       = "pat"
            mount_path = "/run/secrets/azure-pipelines"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "pat"
          secret {
            secret_name  = var.azure_pipelines_pat_secret_name
            default_mode = 288

            items {
              key  = "pat"
              path = "pat"
            }
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }

    volume_claim_template {
      metadata {
        name   = "work"
        labels = merge(local.common_labels, local.azure_agent_labels)
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.azure_pipelines_work_storage_class

        resources {
          requests = {
            storage = var.azure_pipelines_work_volume_size
          }
        }
      }
    }
  }

  depends_on = [helm_release.longhorn]
}
