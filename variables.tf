variable "kubeconfig_path" {
  description = "k3s kubeconfig 파일 경로"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "사용할 kubeconfig context. null이면 현재 context를 사용합니다."
  type        = string
  default     = null
}

variable "deployment_profile" {
  description = "single은 현재 단일 노드, ha는 3개 이상의 스토리지 노드를 위한 확장 프로필입니다."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "ha"], var.deployment_profile)
    error_message = "deployment_profile은 single 또는 ha여야 합니다."
  }
}

variable "ingress_class_name" {
  description = "k3s IngressClass 이름"
  type        = string
  default     = "traefik"
}

variable "harbor_hostname" {
  description = "Harbor 외부 FQDN"
  type        = string
}

variable "harbor_tls_secret_name" {
  description = "registry 네임스페이스에 미리 생성한 Harbor TLS Secret 이름"
  type        = string
}

variable "openbao_hostname" {
  description = "OpenBao 외부 FQDN"
  type        = string
}

variable "openbao_tls_secret_name" {
  description = "openbao 네임스페이스에 미리 생성한 OpenBao TLS Secret 이름"
  type        = string
}

variable "harbor_bucket_name" {
  description = "SeaweedFS에 생성할 Harbor 전용 S3 버킷"
  type        = string
  default     = "harbor-registry"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.harbor_bucket_name))
    error_message = "harbor_bucket_name은 유효한 S3 버킷 이름이어야 합니다."
  }
}

variable "object_data_storage_class" {
  description = "SeaweedFS Volume Server 데이터용 StorageClass. 기본 local-path는 /mnt/data/local-path를 사용합니다."
  type        = string
  default     = "local-path"
}

variable "object_data_volume_size" {
  description = "SeaweedFS Volume Server Pod 하나당 데이터 PVC 크기"
  type        = string
  default     = "100Gi"
}

variable "harbor_admin_password" {
  description = "Harbor admin 초기 비밀번호. TF_VAR_harbor_admin_password 환경변수로 전달합니다."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(var.harbor_admin_password) >= 16
    error_message = "Harbor admin 비밀번호는 16자 이상이어야 합니다."
  }
}

variable "harbor_secret_key" {
  description = "Harbor 내부 암호화 키. 정확히 16자의 영숫자를 환경변수로 전달합니다."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9]{16}$", var.harbor_secret_key))
    error_message = "harbor_secret_key는 정확히 16자의 영숫자여야 합니다."
  }
}

variable "seaweedfs_s3_access_key" {
  description = "Harbor가 사용할 SeaweedFS S3 Access Key"
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9]{16,32}$", var.seaweedfs_s3_access_key))
    error_message = "SeaweedFS Access Key는 16~32자의 영숫자여야 합니다."
  }
}

variable "seaweedfs_s3_secret_key" {
  description = "Harbor가 사용할 SeaweedFS S3 Secret Key"
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(var.seaweedfs_s3_secret_key) >= 32
    error_message = "SeaweedFS Secret Key는 32자 이상이어야 합니다."
  }
}

variable "bootstrap_secret_revision" {
  description = "Harbor 또는 S3 자격 증명을 회전할 때 증가시키는 revision"
  type        = number
  default     = 1
}

variable "azure_pipelines_agent_enabled" {
  description = "Linux Azure Pipelines Agent Pod 생성 여부"
  type        = bool
  default     = true
}

variable "azure_pipelines_agent_image" {
  description = "images/azure-pipelines-agent로 빌드해 Harbor 등에 push한 고정 태그 이미지"
  type        = string
}

variable "azure_pipelines_url" {
  description = "Azure DevOps Server collection URL"
  type        = string
}

variable "azure_pipelines_pool" {
  description = "Linux Agent를 등록할 Azure DevOps Agent Pool"
  type        = string
  default     = "linux-k3s"
}

variable "azure_pipelines_pat_secret_name" {
  description = "azure-pipelines 네임스페이스에 미리 생성한 PAT Secret 이름. 키 이름은 pat입니다."
  type        = string
  default     = "azure-pipelines-agent-pat"
}

variable "azure_pipelines_image_pull_secret_name" {
  description = "Agent 이미지 pull용 Secret 이름. 공개/노드 인증 레지스트리면 null"
  type        = string
  default     = null
}

variable "azure_pipelines_work_volume_size" {
  description = "Agent 작업공간과 Python/패키지 캐시 PVC 크기"
  type        = string
  default     = "50Gi"
}

variable "azure_pipelines_work_storage_class" {
  description = "Agent별 작업공간 PVC StorageClass"
  type        = string
  default     = "longhorn"
}

variable "azure_pipelines_agent_replicas" {
  description = "동시에 실행할 Linux Pipeline Agent 수"
  type        = number
  default     = 1

  validation {
    condition     = var.azure_pipelines_agent_replicas >= 1
    error_message = "azure_pipelines_agent_replicas는 1 이상이어야 합니다."
  }
}

variable "azure_pipelines_agent_resources" {
  description = "Azure Pipelines Agent 컨테이너의 Kubernetes requests/limits"
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = {
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
    limits = {
      cpu    = "4"
      memory = "8Gi"
    }
  }
}
