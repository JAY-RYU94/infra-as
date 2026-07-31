# Hyper-V 배치 기준

## 초기 노드

Ubuntu Server 24.04 LTS Gen2 VM 한 대에서 시작합니다.

| 항목 | 초기 권장값 |
|---|---:|
| vCPU | 8 |
| 고정 메모리 | 24~32 GiB |
| VHDX | 동적 확장 1 TiB 이상, 운영 최대 크기는 용량 계획에 맞게 조정 |
| NIC | External vSwitch, 고정 MAC + 고정 IP |
| Secure Boot | Microsoft UEFI Certificate Authority |
| Dynamic Memory | 사용하지 않음 |
| Checkpoint | 사용하지 않음 |

SonarQube 서버가 외부에 있으므로 이 산정에는 SonarQube 메모리와 PostgreSQL이
포함되지 않습니다. Harbor의 실제 이미지 보존 정책과 SeaweedFS 복제본 수를
고려해 VHDX의 데이터 영역은 여유 있게 산정해야 합니다.

## 디스크와 마운트 지점

VHDX는 한 개를 사용해도 됩니다. Ubuntu 설치 화면의 Custom storage layout에서
같은 VHDX 안에 서로 다른 LVM logical volume 또는 파티션을 만들고 다음처럼
마운트합니다.

| 마운트 지점 | 권장 크기 | 용도 |
|---|---:|---|
| `/` | 100 GiB, ext4 | Ubuntu OS, 패키지, 로그 |
| `/mnt/data` | 나머지 공간, XFS | k3s와 플랫폼 영속 데이터 |

수동 설치에서는 VHDX를 확장한 뒤 logical volume 크기를 조정하기 쉬워 LVM을
권장합니다. 자동 설치는 단순성과 재현성을 위해 `/mnt/data`를 디스크의 마지막
partition으로 만들므로, 증설할 때는 VHDX 확장 후 partition과 XFS를 순서대로
확장합니다. `/mnt/data`는 `/`와 같은 물리 VHDX에 있어도 되지만 별도
filesystem으로 마운트되어야 하며 `/etc/fstab`에 등록되어 부팅 때 자동
마운트되어야 합니다. XFS는 `ftype=1`이어야 합니다. Ubuntu 24.04의 최신
`mkfs.xfs` 기본값이지만 준비 스크립트에서도 파일시스템 종류, `ftype=1`,
read-write 마운트를 모두 검사합니다. 이 구성은 Kubernetes NodeSwap을 별도로
활성화하지 않으므로 swap partition/file은 만들지 않거나 설치 전에 비활성화하고
`/etc/fstab`에서도 제거합니다.

`/etc/fstab`의 데이터 항목은 설치기가 생성한 UUID를 사용합니다. 예시는 다음과
같으며 실제 UUID로 바꿔야 합니다.

```fstab
UUID=<data-lv-uuid> /mnt/data xfs defaults,noatime,prjquota 0 0
```

플랫폼 경로는 다음으로 고정합니다.

- `/mnt/data/k3s`: k3s 상태, embedded etcd, containerd, kubelet 데이터
- `/mnt/data/local-path`: k3s local-path PVC
- `/mnt/data/longhorn`: Longhorn replica 데이터

여기서 `/mnt/data`의 호스트 filesystem은 XFS이고, Longhorn이 Pod에 제공하는
기본 volume 내부 filesystem은 Terraform의 StorageClass 설정대로 ext4입니다.
두 계층의 filesystem이 다른 것은 정상입니다.

기본 `local-path` provisioner는 PVC 요청 크기를 filesystem quota로 강제하지
않습니다. 준비 스크립트는 XFS project quota로 k3s 15%, local-path 50%의 hard
limit을 적용합니다. 비율은 `K3S_QUOTA_PERCENT`,
`LOCAL_PATH_QUOTA_PERCENT` 환경변수로 조정할 수 있습니다.

Longhorn 경로에는 XFS project quota를 걸지 않습니다. Longhorn은 directory의
project quota가 아니라 전체 filesystem `statfs` 용량을 기준으로 스케줄링하므로,
별도 30% XFS hard limit을 걸면 스케줄러가 더 큰 여유 공간을 보고 쓰다가
`EDQUOT`로 실패할 수 있습니다. 대신 Helm 설정에서 새 default disk의 reserved를
70%, over-provisioning을 100%로 설정해 Longhorn의 schedulable maximum을 전체
filesystem의 30%로 제한하고 최소 5%의 실제 여유 공간을 요구합니다. k3s 15%,
local-path 50%, Longhorn 최대 30%의 합계가 95%를 넘지 않아야 합니다. 기존
Longhorn disk에는 default 변경이 소급되지 않으므로 UI/API에서 reserved를 70%로
별도 수정하고 실제 `StorageMaximum`을 확인합니다. 이 제한과 별개로 디스크
사용률 경보와 Harbor 보존 정책을 함께 운영해야 합니다.

새 VM은 [`hyperv-nodes`](../hyperv-nodes/README.md)의 고정된 무인 설치 구성이
위 파티션·포맷을 자동 생성합니다. 기존 VM을 수동 전환하는 경우에는 디스크
선택과 파티션·포맷이 되돌리기 어려운 작업이므로 이 자동 설치 ISO를 사용하지
말고 백업 후 별도 마이그레이션 절차를 적용합니다.

## 사내 CA와 Harbor

Harbor가 사내 CA 인증서를 사용하면 모든 k3s 서버 노드가 이미지를 pull할 수
있도록 CA 인증서를 노드에 설치하고, k3s 설치 전에
`/etc/rancher/k3s/registries.yaml`을 준비합니다.

```yaml
configs:
  "registry.infra.example.com":
    tls:
      ca_file: /usr/local/share/ca-certificates/asol-root-ca.crt
```

인증서는 `update-ca-certificates`로 Ubuntu trust store에도 반영합니다. Harbor
인증 정보는 이 파일에 평문으로 넣지 않고 Kubernetes imagePullSecret을 사용합니다.
레지스트리 설정을 사후 변경하면 해당 노드의 k3s를 재시작해야 합니다.

## k3s 설치

Ubuntu 관리 계정은 `asoladmin`으로 통일합니다. 요청한 초기 비밀번호를 Git이나
Terraform 변수에 넣지 말고 Hyper-V 콘솔에서 최초 로그인한 직후 변경합니다.
노드 준비 스크립트는 비밀번호를 root 전용 파일로 받아 계정을 생성하고
`chage`로 최초 로그인 시 변경을 강제합니다. 또한 `k3s-admin` group에 계정을
추가해 root 소유 kubeconfig를 group read 권한으로 사용할 수 있게 합니다.

```bash
sudo install -m 0600 /dev/stdin /root/asoladmin-initial-password
# 표준 입력으로 합의한 초기 비밀번호를 전달하고 Ctrl-D

ASOLADMIN_PASSWORD_FILE=/root/asoladmin-initial-password \
  ./scripts/prepare-ubuntu-node.sh
sudo shred -u /root/asoladmin-initial-password
```

SSH 공개키는 Ubuntu 설치/cloud-init 단계에서 `asoladmin`에 등록합니다. 비밀번호
SSH 로그인은 활성화하지 않으며 초기 비밀번호는 Hyper-V 콘솔 복구용으로만
사용합니다. 기존 로그인 세션에는 새 group이 즉시 반영되지 않으므로 준비
스크립트 실행 후 로그아웃했다가 다시 로그인합니다.

준비 스크립트를 복구 목적으로 다시 실행할 때는 초기 비밀번호 파일을 전달하지
않으면 변경된 비밀번호를 다시 만료시키지 않습니다. quota 비율을 줄일 때도 새
hard limit이 현재 directory 사용량보다 작거나 같으면 적용 전에 실패합니다.
비밀번호 재만료가 명시적으로 필요할 때만
`EXPIRE_ASOLADMIN_PASSWORD=true`를 사용합니다.

각 노드에서 위 준비를 마친 후 k3s를 설치합니다. 초기 서버는
처음부터 embedded etcd로 시작해야 나중에 control-plane 노드를 자연스럽게
추가할 수 있습니다. 설치 스크립트는 Kubernetes Secret의 etcd 저장 시 암호화,
압축된 etcd snapshot과 14개 보존 정책도 모든 server 노드에 동일하게 적용합니다.

```bash
sudo install -m 0600 /dev/stdin /root/k3s-cluster-token
# 위 명령의 표준 입력으로 충분히 긴 무작위 토큰을 전달

K3S_TLS_SAN=k3s.infra.example.com \
  ./scripts/install-k3s-initial-server.sh
```

추가 서버 노드는 동일한 토큰 파일과 `/mnt/data` 마운트를 준비한 뒤 실행합니다.

```bash
K3S_URL=https://10.0.0.10:6443 \
  ./scripts/install-k3s-server-node.sh
```

etcd 쿼럼을 위해 서버 노드는 1대 다음에 바로 3대로 확장하며 2대 상태를
장기간 운용하지 않습니다. VM 세 대는 가능하면 서로 다른 Hyper-V 호스트에
분산해야 호스트 장애까지 견딜 수 있습니다. Hyper-V 호스트가 한 대뿐이면
3노드는 유지보수 편의와 Pod 분산에는 도움이 되지만 호스트 장애는 막지 못합니다.

기본 etcd snapshot도 `/mnt/data/k3s`와 같은 VHDX에 있으므로 디스크 장애에 대한
백업은 아닙니다. 운영 전에는 이 클러스터와 장애 영역을 공유하지 않는 외부
S3/NFS 백업 대상을 정하고 복구 훈련을 별도로 수행해야 합니다. 같은 클러스터의
SeaweedFS를 etcd의 유일한 백업 대상으로 사용하면 동시 장애 때 복구할 수 없습니다.

## Terraform 경계

플랫폼 리소스는 이 디렉터리의 OpenTofu/Terraform state로 관리합니다. Hyper-V
VM은 [`hyperv-nodes`](../hyperv-nodes/) root module과 별도 state로 분리합니다.
이 구성은 MPL-2.0 오픈소스인 `windsorcli/hyperv 0.3.1`을 정확히 고정하며,
WSL의 환경변수에서 WinRM 접속 정보를 받습니다. 2026-07-31 현재 Terraform
Registry에서 설치 가능한 최신판은 `0.3.1`입니다. GitHub의 `v0.3.3` 태그는
Registry에 게시되지 않아 사용하지 않습니다. provider가 아직 `0.x`이므로
업그레이드는 Registry 게시 여부, changelog와 non-production plan을 검증한 뒤
명시적으로 수행합니다.

VM 설치는 provider가 제공하는 appliance 설치 패턴을 3단계
(`install` → `run` → `operational`) guard로 확장합니다.
첫 apply는 DVD를 첫 boot device로 두고 install phase의 VM power state를 관리하지
않습니다. 새 VM은 기본값인 `Off`로 생성되며 관리자가 Hyper-V에서 한 번만
시작하고 Ubuntu 설치가 완료되어 다시 꺼진 것을 확인합니다. 두 번째 apply의
`run` phase는 `hyperv_vm_state` data source로 실제 `Off` 상태를 강제 검사한 후
DVD를 분리하고 VHDX를 첫 boot device로 설정합니다. 이후 변수를 `operational`로
바꾸고 VM이 `Off`일 때 guard apply를 한 번 더 통과한 뒤 관리자가 VM을 시작합니다.
ISO 삭제는 bootstrap 검증 후 별도 확인 문구가 있어야 허용됩니다. 모든 phase에서
전원을 Terraform이 `Running`이나 `Off`로 계속 관리하지 않으므로 재apply가 설치
ISO를 재부팅하거나 진행 중인 설치를 hard power-off하는 일을 막습니다.
`operational` guard 뒤 VM을 시작하면 민감 ISO를 보관하는 동안 Hyper-V plan을
막고, bootstrap 검증 및 확인값과 함께 ISO를 제거한 뒤 실행 중인 VM의 일반
plan을 허용합니다.
비밀번호 원문은 ISO builder가 로컬 root-only 파일에서 읽고 salted hash만 넣으며,
k3s token도 Terraform 입력/state가 아니라 민감한 커스텀 ISO를 통해 전달합니다.
설치를 검증한 뒤 Hyper-V 호스트와 WSL runner의 커스텀 ISO를 모두 제거합니다.

Hyper-V와 Windows Server는 기존 회사 플랫폼 예외이며, Ubuntu 게스트 내부의
k3s와 플랫폼 구성요소 및 사용한 Terraform provider는 오픈소스로 구성합니다.
