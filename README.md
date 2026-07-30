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
| Container Registry | Harbor | chart/core `1.19.1` / `v2.15.2` (Redis `v2.15.1`) |
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

- Ubuntu 관리 계정은 `asoladmin`이며 초기 비밀번호는 Hyper-V 콘솔에서 처음
  로그인할 때 즉시 변경하도록 강제합니다. 평문 비밀번호는 저장소에 넣지 않습니다.
- 하나의 VHDX를 사용하되 `/`는 ext4, `/mnt/data`는 XFS(`ftype=1`)인 별도 LVM
  logical volume 또는 파티션으로 마운트합니다.
- k3s 상태는 `/mnt/data/k3s`, local-path PVC는 `/mnt/data/local-path`,
  Longhorn replica는 `/mnt/data/longhorn`에 저장됩니다.
- DNS에서 Harbor/OpenBao FQDN이 Traefik 진입 IP를 가리켜야 합니다.
- `registry`, `openbao`, `azure-pipelines` namespace에 사용할 TLS/PAT Secret을
  준비합니다.
- Harbor와 SeaweedFS의 초기 자격 증명은 환경변수로 전달합니다.

예제 변수를 복사하되 Secret은 넣지 않습니다.

```bash
cp terraform.tfvars.example terraform.tfvars
```

필수 bootstrap 값은 대상 지정 apply에서도 변수 검증에 필요합니다. 아래 예시
문자열을 그대로 쓰지 말고 현재 shell에만 실제 무작위 값을 설정합니다.

```bash
export TF_VAR_harbor_admin_password='replace-with-at-least-16-characters'
export TF_VAR_harbor_secret_key='0123456789ABCDEF'
export TF_VAR_seaweedfs_s3_access_key='REPLACEACCESSKEY'
export TF_VAR_seaweedfs_s3_secret_key='replace-with-at-least-32-characters'

tofu init
```

OpenTofu가 namespace를 먼저 만들게 한 후 인증서와 PAT를 생성합니다.
OpenBao 인증서는 외부 FQDN, `openbao-internal`,
`openbao-internal.openbao.svc`, `openbao-internal.openbao.svc.cluster.local`을
SAN으로 포함하고, `ca.crt`는 인증서를 발급한 CA chain이어야 합니다.

```bash
tofu apply \
  -target=kubernetes_namespace_v1.longhorn \
  -target=kubernetes_namespace_v1.object_storage \
  -target=kubernetes_namespace_v1.registry \
  -target=kubernetes_namespace_v1.openbao \
  -target=kubernetes_namespace_v1.azure_pipelines

kubectl -n registry create secret tls harbor-tls \
  --cert=harbor.crt --key=harbor.key
kubectl -n openbao create secret generic openbao-tls \
  --from-file=tls.crt=openbao.crt \
  --from-file=tls.key=openbao.key \
  --from-file=ca.crt=openbao-ca.crt
kubectl -n azure-pipelines create secret generic azure-pipelines-agent-pat \
  --from-file=pat=/secure/path/azure-agent.pat
```

초기에는 `azure_pipelines_agent_enabled = false`로 플랫폼을 먼저 올립니다.

```bash
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

Azure DevOps, SonarQube 또는 Harbor가 사내 CA 인증서를 사용하면 빌드할 때 CA를
BuildKit secret으로 전달합니다. CA 파일은 공개 인증서이지만 이 방식은 빌드
context와 Git에 파일이 섞이는 것을 막습니다.

```bash
docker build \
  --platform linux/amd64 \
  --secret id=asol_internal_ca,src=/secure/path/asol-root-ca.crt \
  -t registry.infra.example.com/platform/azure-pipelines-agent:2022.2-3.238.0 \
  images/azure-pipelines-agent
```

이미지를 Harbor에 push한 다음 `azure_pipelines_agent_enabled = true`로 바꾸고
다시 apply합니다. Agent별 PVC가 `_work`, NuGet, Sonar, `uv` Python 다운로드를
보존하므로 replica를 늘려도 RWO PVC를 공유하지 않습니다.

Agent 서비스 계정에는 Kubernetes API 권한을 부여하지 않습니다. 배포 Pipeline이
필요하면 별도의 최소 권한 Service Connection/kubeconfig를 사용합니다.
등록 PAT도 Agent Pools의 필요한 최소 scope만 부여하고 주기적으로 회전합니다.
이 self-hosted agent는 신뢰하는 사내 프로젝트와 검토된 Pipeline에서만 사용해야
합니다. Pipeline script는 실행 중인 job의 secret과 작업공간에 접근할 수 있습니다.

## OpenBao 초기화

OpenBao는 1노드부터 integrated Raft로 시작하므로 나중에 3 replica로 확장할 때
스토리지 엔진을 바꿀 필요가 없습니다. 최초 배포 뒤 한 번만 초기화하고 unseal
key와 root token은 Kubernetes/Terraform state 밖의 승인된 보관소에 저장합니다.
초기화 전에도 Helm 설치가 완료될 수 있도록 health probe는 uninitialized 상태만
bootstrap 가능한 상태로 취급합니다. 초기화 후 sealed Pod는 Ready가 되지 않습니다.

```bash
kubectl -n openbao exec -it openbao-0 -- \
  bao operator init -key-shares=5 -key-threshold=3
kubectl -n openbao exec -it openbao-0 -- bao operator unseal
```

초기화와 unseal 뒤에는 `/openbao/audit` 경로를 사용하는 file audit device를
활성화하고, root token 대신 운영 정책·인증 방식을 구성합니다.

OpenBao auto-unseal은 별도 신뢰 루트(HSM/KMS)가 필요하므로 초기 구성에는
포함하지 않았습니다. 자체 OpenBao로 자기 자신을 auto-unseal하는 순환 구성은
사용하지 않습니다.

OpenBao Agent Injector는 fail-closed이며 명시적으로 허용한 namespace에만
작동합니다. Secret 주입을 사용할 애플리케이션 namespace에 다음 label을
Terraform 또는 해당 namespace 관리 도구로 추가합니다.

```bash
kubectl label namespace <application-namespace> \
  openbao.asol.io/injection=enabled
```

주입되는 Agent가 OpenBao 서버 인증서를 검증하도록 같은 CA를 애플리케이션
namespace의 Secret으로 배포하고 Pod annotation의 CA 경로를 지정해야 합니다.
CA 배포와 annotation은 애플리케이션별 배포 저장소에서 관리합니다.

## 확장 시 주의

`deployment_profile = "ha"`로 변경하기 전에 k3s server VM을 총 3대로 만듭니다.
Longhorn의 기존 볼륨 replica 수와 SeaweedFS의 기존 volume replication은 프로필
변경만으로 자동 재작성되지 않으므로, 운영 절차에 따라 기존 데이터도 3 replica로
조정하고 복구 테스트를 수행해야 합니다. OpenBao의 새 Pod는 `retry_join`으로
Raft에 합류하지만 auto-unseal이 없으므로 각 Pod를 수동 unseal한 뒤
`bao operator raft list-peers`로 3개 peer를 확인합니다.

## 운영 전 필수 결정

- 현재 root module은 backend를 선언하지 않습니다. Terraform/OpenTofu state는
  이 클러스터와 장애 영역을 공유하지 않는 암호화된 remote backend와 locking을
  구성한 뒤 운영에 사용합니다. 같은 SeaweedFS를 유일한 state/backup 저장소로
  두면 클러스터 장애 시 복구가 막힙니다.
- `ha` 프로필도 자동으로 모든 계층을 완전한 HA로 만들지는 않습니다. 현재
  SeaweedFS filer와 Harbor 내부 DB는 1 replica이므로 노드 확장 전에 각 제품의
  외부 DB/metadata HA 설계와 실제 복구 시험이 필요합니다.
- Agent에는 Docker daemon socket이나 privileged builder를 넣지 않았습니다.
  OCI 이미지를 Pipeline에서 빌드해야 하면 별도 namespace에 rootless BuildKit
  서비스를 배포하고 최소 권한으로 연결합니다.
- 외부 etcd/OpenBao/Harbor 백업 대상, 보존 기간, RPO/RTO와 복구 runbook은
  회사의 백업 시스템이 정해진 뒤 별도로 구현하고 정기적으로 시험합니다.
- 인터넷에서 받는 Agent 도구는 고정 버전과 일부 checksum 검증을 적용했지만,
  운영망에서는 검증한 바이너리와 이미지를 Harbor에 mirror하고 서명·승인 절차를
  통과한 artifact만 사용하도록 공급망 정책을 추가합니다.
