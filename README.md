# ASOL 내부 플랫폼

Hyper-V의 Ubuntu 24.04 VM 위에 k3s를 구성하고, 내부 Container Registry와
키 관리 시스템, 오브젝트 스토리지, Azure DevOps Server 2022.2용 Linux
Pipeline Agent를 배포하는 OpenTofu/Terraform 구성입니다.

## 구성

| 기능 | 구성요소 | 고정 버전 |
|---|---|---:|
| Kubernetes | k3s | `v1.36.2+k3s1` |
| 블록 스토리지 | Longhorn | chart `1.12.0` |
| 오브젝트/S3 | SeaweedFS | chart/app `4.40.0` / `4.40` |
| Container Registry | Harbor | chart/app `1.19.1` / `v2.15.2` |
| 키·Secret 관리 | OpenBao | chart/app `0.28.6` / `2.6.1` |
| Azure Pipelines Agent | Microsoft Agent | `3.238.0` |
| SonarQube Azure DevOps 확장 | 기존 외부 SonarQube 연동 | `8.2.3.2750` |
| SonarScanner CLI / .NET | Agent 도구 | `8.1.0.6389` / `11.2.1.137242` |
| IaC CLI | OpenTofu | `1.12.5` |

버전 표는 2026-07-31에 확인했습니다. Azure Pipelines Agent는 전체 제품의 최신
버전이 아니라 **Azure DevOps Server 2022.2와 호환되는 최신 3.x 버전**을
의도적으로 사용합니다. IaC는 오픈소스 요구사항을 위해 OpenTofu를 권장하며,
구성은 Terraform CLI와도 호환됩니다.

## 배치 구조

- `longhorn-system`: Kubernetes RWO 블록 스토리지
- `object-storage`: SeaweedFS, Harbor 이미지 레이어용 내부 S3
- `registry`: Harbor
- `openbao`: OpenBao integrated Raft
- `azure-pipelines`: Linux Azure Pipelines Agent StatefulSet

현재 `single` 프로필은 각 저장 구성요소를 1 replica로 실행합니다. `ha`는
Longhorn·SeaweedFS·OpenBao를 3노드 기준으로 확장합니다. 단일 Hyper-V 호스트의
다중 VM은 호스트 장애를 견디지 못한다는 점은 변하지 않습니다.

자세한 VM 및 노드 준비 방법은 [Hyper-V 배치 기준](docs/HYPER-V.md), 기존
SonarQube 연결은 [SonarQube 연동](docs/SONARQUBE.md)을 봅니다.

## 사전 준비

- Ubuntu 노드의 `/var/lib/longhorn`과 `/var/lib/rancher/k3s/storage`가 데이터
  VHDX에 위치해야 합니다.
- DNS에서 Harbor/OpenBao FQDN이 Traefik 진입 IP를 가리켜야 합니다.
- `registry`, `openbao`, `azure-pipelines` namespace에 사용할 TLS/PAT Secret을
  준비합니다.
- Harbor와 SeaweedFS의 초기 자격 증명은 환경변수로 전달합니다.

예제 변수를 복사하되 Secret은 넣지 않습니다.

```bash
cp terraform.tfvars.example terraform.tfvars
```

OpenTofu가 namespace를 먼저 만들게 한 후 인증서와 PAT를 생성합니다.

```bash
tofu init
tofu apply \
  -target=kubernetes_namespace_v1.longhorn \
  -target=kubernetes_namespace_v1.object_storage \
  -target=kubernetes_namespace_v1.registry \
  -target=kubernetes_namespace_v1.openbao \
  -target=kubernetes_namespace_v1.azure_pipelines

kubectl -n registry create secret tls harbor-tls \
  --cert=harbor.crt --key=harbor.key
kubectl -n openbao create secret tls openbao-tls \
  --cert=openbao.crt --key=openbao.key
kubectl -n azure-pipelines create secret generic azure-pipelines-agent-pat \
  --from-file=pat=/secure/path/azure-agent.pat
```

초기에는 `azure_pipelines_agent_enabled = false`로 플랫폼을 먼저 올립니다.

```bash
export TF_VAR_harbor_admin_password='...'
export TF_VAR_harbor_secret_key='0123456789ABCDEF'
export TF_VAR_seaweedfs_s3_access_key='...'
export TF_VAR_seaweedfs_s3_secret_key='...'

tofu plan -out=platform.tfplan
tofu apply platform.tfplan
```

## Pipeline Agent 이미지

이미지는 Linux x86-64 전용입니다. Windows 컨테이너나 Windows VM을 만들지
않습니다.

```bash
docker build \
  --platform linux/amd64 \
  -t registry.infra.example.com/platform/azure-pipelines-agent:2022.2-3.238.0 \
  images/azure-pipelines-agent
docker push \
  registry.infra.example.com/platform/azure-pipelines-agent:2022.2-3.238.0
```

이미지를 Harbor에 push한 다음 `azure_pipelines_agent_enabled = true`로 바꾸고
다시 apply합니다. Agent별 PVC가 `_work`, NuGet, Sonar, `uv` Python 다운로드를
보존하므로 replica를 늘려도 RWO PVC를 공유하지 않습니다.

Agent 서비스 계정에는 Kubernetes API 권한을 부여하지 않습니다. 배포 Pipeline이
필요하면 별도의 최소 권한 Service Connection/kubeconfig를 사용합니다.

## OpenBao 초기화

OpenBao는 1노드부터 integrated Raft로 시작하므로 나중에 3 replica로 확장할 때
스토리지 엔진을 바꿀 필요가 없습니다. 최초 배포 뒤 한 번만 초기화하고 unseal
key와 root token은 Kubernetes/Terraform state 밖의 승인된 보관소에 저장합니다.

```bash
kubectl -n openbao exec -it openbao-0 -- \
  bao operator init -key-shares=5 -key-threshold=3
kubectl -n openbao exec -it openbao-0 -- bao operator unseal
```

OpenBao auto-unseal은 별도 신뢰 루트(HSM/KMS)가 필요하므로 초기 구성에는
포함하지 않았습니다. 자체 OpenBao로 자기 자신을 auto-unseal하는 순환 구성은
사용하지 않습니다.

## 확장 시 주의

`deployment_profile = "ha"`로 변경하기 전에 k3s server VM을 총 3대로 만듭니다.
Longhorn의 기존 볼륨 replica 수와 SeaweedFS의 기존 volume replication은 프로필
변경만으로 자동 재작성되지 않으므로, 운영 절차에 따라 기존 데이터도 3 replica로
조정하고 복구 테스트를 수행해야 합니다.
