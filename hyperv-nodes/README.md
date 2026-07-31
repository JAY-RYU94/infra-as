# Hyper-V k3s 노드

이 디렉터리는 Hyper-V VM과 VHDX를 플랫폼 Kubernetes 리소스와 분리된
OpenTofu/Terraform state로 관리합니다. Terraform Registry에서 설치 가능한
최신판인 `windsorcli/hyperv 0.3.1`을 정확히 고정했으며, WSL에서 WinRM으로
기존 Hyper-V 호스트를 제어합니다. 2026-07-31 현재 GitHub에는 `v0.3.3` 태그가
있지만 Registry version 목록에 배포되지 않아 재현 가능한 `init` 대상에서
제외했습니다. 이 provider는 OpenTofu Registry에 없으므로 `required_providers`의
source를 `registry.terraform.io/windsorcli/hyperv`로 완전히 명시합니다.

Ubuntu Server `24.04.4 LTS` 무인 설치 ISO는 다음 구성을 자동으로 만듭니다.

- Generation 2 VM, Secure Boot, 고정 MAC, 고정 메모리
- 하나의 동적 VHDX
- `/`: 100 GiB ext4
- `/mnt/data`: 나머지 공간 XFS, `noatime,prjquota`
- swap 없음
- `asoladmin` 계정, SSH 공개키 로그인, 비밀번호 SSH 차단
- k3s `v1.36.2+k3s1`, 데이터 디렉터리 `/mnt/data/k3s`

커스텀 ISO에는 `asoladmin` 비밀번호의 salted SHA-512 hash와 k3s bootstrap
token이 들어갑니다. 평문 비밀번호와 token은 Terraform 변수/state에 들어가지
않지만 ISO 자체는 민감한 파일입니다.

## 1. Hyper-V 호스트 준비

Hyper-V 호스트의 관리자 PowerShell에서 한 번 실행합니다. WinRM 계정은 VM을
관리할 권한과 아래 디렉터리의 쓰기 권한이 있어야 합니다.

```powershell
$account = 'DOMAIN\hyperv-terraform'
$hyperVAdministrators = Get-LocalGroup -SID 'S-1-5-32-578'
$remoteManagementUsers = Get-LocalGroup -SID 'S-1-5-32-580'

New-Item -ItemType Directory -Force `
  C:\Hyper-V\ASOL\ISO, `
  C:\Hyper-V\ASOL\VHDX

Add-LocalGroupMember -Group $hyperVAdministrators -Member $account
Add-LocalGroupMember -Group $remoteManagementUsers -Member $account

icacls C:\Hyper-V\ASOL /inheritance:r /T /C
icacls C:\Hyper-V\ASOL /grant:r `
  "${account}:(OI)(CI)M" `
  '*S-1-5-18:(OI)(CI)F' `
  '*S-1-5-32-544:(OI)(CI)F' `
  /T /C
```

SID로 group을 찾으므로 한국어 Windows에서도 group 이름 번역에 의존하지 않습니다.
도메인 계정이 아니면 `DOMAIN\...` 대신 실제 로컬 계정을 사용합니다. JEA endpoint를
별도로 위임하지 않은 기본 WinRM에서는 `Remote Management Users` 권한과 Hyper-V
권한이 모두 필요합니다. WinRM은 운영 환경에서 5986/HTTPS listener와 사내 CA
인증서를 권장합니다. 연결 확인은 WSL에서 다음처럼 수행할 수 있습니다.
위 `icacls`는 상속 ACL을 제거하고 WinRM 계정, Local System, 로컬 Administrators만
ASOL 디렉터리에 접근하게 합니다. ISO에는 k3s token이 있으므로 일반 Users 읽기
권한을 남기지 않습니다.

```bash
nc -vz hyperv01.infra.example.com 5986
curl --cacert /path/to/asol-winrm-ca.pem \
  https://hyperv01.infra.example.com:5986/wsman
```

`curl`의 `405 Method Not Allowed`는 WSMan endpoint까지 TLS 연결이 된 것입니다.
인증과 Hyper-V 권한까지 포함한 최종 확인은 아래의 `tofu plan`으로 합니다.
HTTPS host는 인증서 SAN에 들어 있는 FQDN을 사용합니다. IP로 접속하려면 인증서
IP SAN에도 그 주소가 있어야 합니다.

## 2. WSL 도구와 비밀 파일 준비

Ubuntu WSL에서 저장소를 받은 뒤 자동화 스크립트를 실행하는 방법을 권장합니다.
설치 스크립트는 공식 OpenTofu APT repository를 등록하고 `1.12.5`를 정확히
pin한 뒤 ISO 생성에 필요한 패키지를 함께 설치합니다.

```bash
cd hyperv-nodes
./scripts/install-wsl-prerequisites.sh
./scripts/configure-deployment.sh
source ./hyperv.env
```

설정 스크립트는 WinRM, VM network, External vSwitch와 VM resource를 대화식으로
받아 mode `0600`인 `hyperv.env`와 `terraform.tfvars`를 생성합니다. 초기
`asoladmin` 비밀번호는 숨김 prompt로 두 번 받고 WSL home의 mode `0600` 파일에만
저장합니다. k3s token은 자동 생성하며 SSH key가 없으면 `ssh-keygen`을 실행합니다.
마지막에는 새 VM disk 초기화 확인을 위해 VM 이름을 정확히 다시 입력해야 합니다.
기존 설정 파일은 자동으로 덮어쓰지 않으며 의도적으로 재생성할 때만 검토 후
`--force`를 사용합니다.

CI나 별도의 안전한 자동 입력 환경에서는 필요한 값을 환경변수로 전달한 뒤
`--non-interactive`를 사용할 수 있습니다. 이 모드에서는 초기 비밀번호 파일과
SSH 공개키가 이미 존재해야 하며 `INSTALL_DISK_WIPE_CONFIRMATION`도 VM 이름과
정확히 같아야 합니다. 일반 운영자 배포는 대화식 실행을 사용합니다.

수동 설치가 필요하면 아래 패키지를 설치하고
[OpenTofu 공식 Debian 설치 절차](https://opentofu.org/docs/intro/install/deb/)로
`1.12.5`를 설치합니다. 이미 Terraform CLI를 표준으로 사용한다면 이 구성과
호환되는 `1.11` 이상 버전을 사용해도 됩니다.

```bash
sudo apt-get update
sudo apt-get install -y \
  curl gettext-base openssl openssh-client python3 xorriso
```

자동 설정 스크립트를 사용하지 않는 경우 환경 파일을 복사해 실제
호스트·네트워크·External vSwitch 값으로 수정합니다.
`hyperv.env`는 Git에서 제외되며, source할 때 WinRM 비밀번호를 prompt로 받아
디스크에 저장하지 않습니다.

```bash
cd hyperv-nodes
cp hyperv.env.example hyperv.env
chmod 0600 hyperv.env
${EDITOR:-vi} hyperv.env
source ./hyperv.env
```

매번 새 shell에서 `source ./hyperv.env`를 실행해야 합니다. HTTP/5985를 임시로
사용해 endpoint만 진단한다면 환경 파일에서 다음 세 값을 바꿀 수 있습니다.

```bash
export HYPERV_PORT="5985"
export HYPERV_WINRM_USE_HTTPS="false"
export HYPERV_WINRM_CACERT=""
```

운영에서는 HTTP 대신 HTTPS를 사용합니다. `HYPERV_WINRM_INSECURE=true`는 인증서
검증을 끄므로 일시적인 진단 외에는 사용하지 않습니다. 커스텀 ISO에는 k3s token이
있으므로 HTTP/5985 또는 인증서 검증이 꺼진 상태에서는 `plan/apply`하거나 ISO를
전송하지 않습니다.

비밀 파일은 WSL home 아래에 만들고 group/other 권한을 제거합니다. 비밀번호
입력을 shell history나 Git 파일에 직접 남기지 않습니다.

```bash
umask 077
install -d -m 0700 "${HOME}/.config/asol-infra/secrets"

read -rsp 'asoladmin initial password: ' initial_password
printf '\n'
printf '%s' "${initial_password}" \
  >"${HOME}/.config/asol-infra/secrets/asoladmin-initial-password"
unset initial_password

openssl rand -hex 32 \
  >"${HOME}/.config/asol-infra/secrets/k3s-cluster-token"
chmod 0600 "${HOME}/.config/asol-infra/secrets/"*
```

합의한 초기 비밀번호는 저장소나 명령줄에 쓰지 말고 위 prompt에 직접 입력합니다.
설치된 Ubuntu는 이 비밀번호를 Hyper-V 콘솔에서 즉시 바꾸도록 강제합니다. SSH
key가 없다면 Ed25519 key를 만듭니다.

```bash
ssh-keygen -t ed25519 -a 100 -f "${HOME}/.ssh/id_ed25519"
```

## 3. 무인 설치 ISO 생성

환경 파일을 source한 shell에서 실행합니다.

```bash
./scripts/build-autoinstall-iso.sh
```

스크립트는 Canonical의 Ubuntu Server `24.04.4` ISO를 내려받아 고정 SHA-256
checksum을 검증하고 `ASOL_ARTIFACT_DIR` 아래에 커스텀 ISO를 만듭니다. 예제
환경 파일은 WSL Linux home 아래를 사용하며 `/mnt/c` 같은 Windows mount는
builder가 거부합니다. 생성 결과는 mode `0600`입니다. 같은 경로에 생성되는
`.manifest.json`에는 비밀값 없이 ISO checksum, hostname, MAC, IP가 기록됩니다.
Terraform은 manifest와 현재 변수가 모두 일치하지 않으면 ISO 업로드를 거부하므로
환경 파일을 바꾼 뒤에는 ISO를 반드시 다시 생성해야 합니다.

기본 ISO와 checksum:

- `https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso`
- `e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433`

## 4. VM 설치 단계 적용

설정 스크립트를 실행했다면 이미 생성된 `terraform.tfvars`를 검토합니다. 수동으로
설정하는 경우에만 비밀값이 없는 예제를 복사해 VHDX 경로와 크기를 수정합니다.
VM 이름, MAC, vSwitch는 환경 파일이 `TF_VAR_*`로 함께 전달하므로 ISO 설정과
Terraform 설정이 어긋나지 않습니다. 무인 설치는 디스크를 초기화하므로
`install_disk_wipe_confirmation`에는 환경 파일의 `VM_HOSTNAME`과 정확히 같은
VM 이름을 입력해야 plan이 허용됩니다.

```bash
# 자동 설정 스크립트를 사용하지 않은 경우에만 실행
test -f terraform.tfvars || cp terraform.tfvars.example terraform.tfvars
${EDITOR:-vi} terraform.tfvars

tofu init
tofu validate
tofu plan -out=hyperv-install.tfplan
tofu apply hyperv-install.tfplan
```

OpenTofu 대신 호환되는 Terraform CLI를 사용해도 됩니다. ISO 전송은 WSL runner에서
Hyper-V 호스트로 WinRM을 통하므로 네트워크에 따라 오래 걸릴 수 있습니다.

첫 apply는 VM을 Hyper-V 기본값인 `Off`로 만들고 install phase 동안 power state를
관리하지 않습니다. Terraform이 전원을 `Running`으로 계속 강제하면 설치가 끝나
꺼진 VM을 다시 ISO로 부팅해 디스크를 재초기화할 수 있고, `Off`로 강제하면 설치
중 재apply가 VM을 hard power-off할 수 있기 때문입니다. 호스트 PowerShell에서
checkpoint를 비활성화하고 상태를 확인한 뒤 VM을 **한 번만** 시작합니다.

```powershell
Set-VM -Name asol-k3s-01 -AutomaticCheckpointsEnabled $false
Get-VM -Name asol-k3s-01 | Select-Object Name, State
Start-VM -Name asol-k3s-01
```

provider `0.3.1`은 automatic checkpoint 설정을 노출하지 않으므로 첫 생성 직후
위 명령으로 한 번 비활성화합니다. 이 명령은 기존 checkpoint를 삭제하지 않습니다.
VM 콘솔에서 Ubuntu 설치가 진행되고 `shutdown: poweroff`에 의해 완료 후 다시
`Off`가 됩니다. install phase를 다시 plan/apply해도 Terraform은 실행 중인 VM을
끄거나, 꺼진 VM을 다시 켜지 않습니다.

## 5. VHDX 부팅 전환과 운영 단계

VM이 `Off`인 것을 확인한 뒤 `terraform.tfvars`를 수정합니다.

```hcl
installation_phase = "run"
```

다시 적용하면 먼저 `hyperv_vm_state`로 실제 VM이 `Off`인지 확인합니다. 아직
설치 중이면 plan이 실패하므로 DVD를 live installer에서 분리하지 않습니다.
검사를 통과하면 DVD를 분리하고 boot order를 VHDX 단독으로 변경합니다. provider의
조건부 power-state 처리 결함과 재apply 강제 종료를 피하기 위해 VM 전원은
Terraform이 지속 관리하지 않습니다.

```bash
tofu plan -out=hyperv-run.tfplan
tofu apply hyperv-run.tfplan
```

run 전환이 완료되면 `terraform.tfvars`를 운영 상태로 바꾸고 VM이 여전히 `Off`일
때 한 번 더 apply합니다. 이 guard apply는 install에서 operational로 잘못
건너뛰더라도 live installer의 DVD를 분리하지 못하게 합니다.

```hcl
installation_phase = "operational"
```

```bash
tofu apply
```

guard apply가 성공한 뒤 Hyper-V에서 한 번 시작합니다. 민감 ISO를 아직 보관하는
동안에는 실행 중인 VM에 대한 Hyper-V plan을 의도적으로 막습니다. bootstrap 검증
후 아래 cleanup 확인값과 함께 ISO를 제거하면 이후 일반 plan을 허용합니다.

```powershell
Start-VM -Name asol-k3s-01
```

첫 부팅에서 cloud-init이 노드 준비와 k3s 설치를 수행합니다. Hyper-V 콘솔에서
`asoladmin`으로 로그인하고 초기 비밀번호를 즉시 바꿔야 SSH가 정상적으로
사용됩니다. 그다음 WSL에서 확인합니다.

```bash
ssh asoladmin@192.0.2.31
cloud-init status --wait --long
sudo test -f /var/lib/cloud/asol-bootstrap-complete
sudo systemctl status k3s --no-pager
sudo kubectl get nodes -o wide
findmnt / /mnt/data
```

`/`가 ext4, `/mnt/data`가 XFS이고 `prjquota`가 mount option에 포함되어야 합니다.

## 6. 민감한 설치 ISO 제거

부팅과 k3s를 확인한 뒤 `terraform.tfvars`를 수정합니다.

```hcl
installation_phase             = "operational"
installer_iso_present          = false
installer_cleanup_confirmation = "REMOVE_SENSITIVE_ISO_AFTER_BOOTSTRAP:asol-k3s-01"
```

확인 문구는 cloud-init marker, k3s와 mount 검증을 마친 뒤에만 입력합니다.
적용하면 Hyper-V 호스트의 커스텀 ISO를 삭제합니다.

```bash
tofu apply
rm -f -- "${OUTPUT_ISO}" "${OUTPUT_ISO}.manifest.json"
unset HYPERV_PASSWORD
```

SSD나 가상 디스크에서는 `shred`가 완전 삭제를 보장하지 않으므로 WSL 및 Hyper-V
볼륨 자체의 암호화도 사용해야 합니다. Ubuntu 원본 ISO cache에는 비밀이 없습니다.

## 7. 플랫폼 배포로 연결

kubeconfig를 WSL에 복사하고 server 주소를 노드의 고정 IP 또는 k3s API DNS로
바꿉니다.

```bash
install -d -m 0700 "${HOME}/.kube"
ssh asoladmin@192.0.2.31 \
  'sudo cat /etc/rancher/k3s/k3s.yaml' \
  >"${HOME}/.kube/asol-k3s.yaml"
chmod 0600 "${HOME}/.kube/asol-k3s.yaml"
sed -i 's#https://127.0.0.1:6443#https://192.0.2.31:6443#' \
  "${HOME}/.kube/asol-k3s.yaml"
export KUBECONFIG="${HOME}/.kube/asol-k3s.yaml"

cd ..
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
```

## 8. 후속 노드와 폐기 경계

현재 `hyperv-nodes` root는 첫 번째 `--cluster-init` 서버 한 대만 자동 설치합니다.
후속 서버에 이 ISO를 재사용하면 별도 클러스터를 만들 수 있으므로 사용하지
않습니다. 당장 수동으로 증설할 때는 고유 VM/MAC/IP/VHDX를 준비하고
`scripts/prepare-ubuntu-node.sh` 다음 `scripts/install-k3s-server-node.sh`를
실행합니다. 운영 증설 자동화 전에는 node map과 노드별 별도 ISO, `K3S_URL`을
사용하는 join profile을 이 root에 추가하고 non-production에서 검증해야 합니다.
etcd server는 1대 다음 3대로 확장하고 2대 상태를 장기간 운용하지 않습니다.

첫 실제 적용은 비운영 Hyper-V host/vSwitch에서 ISO Secure Boot, 자동 설치 완료
poweroff, run guard, VHDX 부팅까지 smoke test한 뒤 운영 host에 적용합니다.

운영 전에는 이 디렉터리와 root module 모두 클러스터와 장애 영역을 공유하지 않는
암호화된 remote backend 및 state locking을 구성합니다.

VHDX에는 `prevent_destroy`를 설정했습니다. 따라서 `tofu destroy`, VHDX path 변경,
교체가 데이터 디스크를 삭제하려 하면 plan이 실패합니다. 승인된 폐기 절차에서는
먼저 workload를 drain하고 VM을 정상 종료한 뒤 백업 복구 시험을 완료합니다.
그다음 아래처럼 VHDX를 Terraform state에서만 분리하고 VM 리소스를 제거합니다.
VHDX 파일은 Hyper-V 호스트에 남으므로 보존 정책에 따라 별도로 보관합니다.

```bash
tofu state rm hyperv_vhd.node
tofu destroy
```

Hyper-V provider는 VM destroy 시 실행 중인 VM을 hard power-off하므로 정상 종료를
생략하면 안 됩니다. VHDX 파일의 실제 삭제는 이 저장소가 자동화하지 않습니다.
