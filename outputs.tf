output "component_versions" {
  description = "배포 및 호환성 검증에 사용한 고정 버전"
  value       = local.versions
}

output "service_urls" {
  description = "외부에서 접근할 플랫폼 URL"
  value = {
    harbor  = "https://${var.harbor_hostname}"
    openbao = "https://${var.openbao_hostname}"
  }
}

output "namespaces" {
  description = "플랫폼 컴포넌트별 Kubernetes namespace"
  value       = local.namespaces
}

output "seaweedfs_internal_s3_endpoint" {
  description = "클러스터 내부 전용 SeaweedFS S3 endpoint"
  value       = local.seaweed_s3_endpoint
}
