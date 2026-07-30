resource "kubernetes_namespace_v1" "longhorn" {
  metadata {
    name = local.namespaces.longhorn
    labels = merge(local.common_labels, {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    })
  }
}

resource "kubernetes_namespace_v1" "object_storage" {
  metadata {
    name = local.namespaces.object_storage
    labels = merge(local.common_labels, {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    })
  }
}

resource "kubernetes_namespace_v1" "registry" {
  metadata {
    name = local.namespaces.registry
    labels = merge(local.common_labels, {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    })
  }
}

resource "kubernetes_namespace_v1" "openbao" {
  metadata {
    name = local.namespaces.openbao
    labels = merge(local.common_labels, {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    })
  }
}

resource "kubernetes_namespace_v1" "azure_pipelines" {
  metadata {
    name = local.namespaces.azure_pipelines
    labels = merge(local.common_labels, {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    })
  }
}
