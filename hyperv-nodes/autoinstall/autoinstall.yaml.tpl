#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  timezone: Asia/Seoul
  refresh-installer:
    update: false
  shutdown: poweroff

  early-commands:
    - |
      set -eu
      disk_count="$(lsblk -dn -o TYPE | grep -c '^disk$' || true)"
      if [ "$disk_count" -ne 1 ] || [ ! -b /dev/sda ]; then
        echo "Expected exactly one install disk at /dev/sda; refusing destructive autoinstall" >&2
        exit 1
      fi

  identity:
    hostname: ${VM_HOSTNAME}
    username: asoladmin
    password: '${ASOLADMIN_PASSWORD_HASH}'

  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - >-
        ${ASOLADMIN_SSH_PUBLIC_KEY}

  network:
    version: 2
    ethernets:
      eth0:
        match:
          macaddress: "${VM_MAC_ADDRESS}"
        set-name: eth0
        dhcp4: false
        dhcp6: false
        addresses:
          - "${VM_ADDRESS_CIDR}"
        routes:
          - to: default
            via: "${VM_GATEWAY}"
        nameservers:
          addresses: ${VM_DNS_SERVERS_YAML}
          search: ${VM_DNS_SEARCH_YAML}

  storage:
    swap:
      size: 0
    config:
      - type: disk
        id: disk0
        path: /dev/sda
        ptable: gpt
        wipe: superblock-recursive
        preserve: false
        grub_device: true
      - type: partition
        id: partition-efi
        device: disk0
        size: 1G
        flag: boot
      - type: format
        id: format-efi
        volume: partition-efi
        fstype: fat32
      - type: mount
        id: mount-efi
        device: format-efi
        path: /boot/efi
      - type: partition
        id: partition-root
        device: disk0
        size: 100G
      - type: format
        id: format-root
        volume: partition-root
        fstype: ext4
      - type: mount
        id: mount-root
        device: format-root
        path: /
        options: defaults,noatime
      - type: partition
        id: partition-data
        device: disk0
        size: -1
      - type: format
        id: format-data
        volume: partition-data
        fstype: xfs
      - type: mount
        id: mount-data
        device: format-data
        path: /mnt/data
        options: defaults,noatime,prjquota

  packages:
    - ca-certificates
    - cryptsetup
    - curl
    - dmsetup
    - linux-cloud-tools-virtual
    - linux-tools-virtual
    - nfs-common
    - open-iscsi
    - xfsprogs

  late-commands:
    - [install, -m, "0600", /cdrom/k3s-cluster-token, /target/root/k3s-cluster-token]

  user-data:
    disable_root: true
    ssh_pwauth: false
    write_files:
      - path: /etc/ssh/sshd_config.d/20-asol-hardening.conf
        owner: root:root
        permissions: '0644'
        content: |
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          PermitRootLogin no
      - path: /usr/local/sbin/prepare-ubuntu-node.sh
        owner: root:root
        permissions: '0755'
        encoding: b64
        content: ${PREPARE_NODE_SCRIPT_BASE64}
      - path: /usr/local/sbin/install-k3s-initial-server.sh
        owner: root:root
        permissions: '0755'
        encoding: b64
        content: ${INSTALL_K3S_SCRIPT_BASE64}
      - path: /usr/local/sbin/asol-first-boot.sh
        owner: root:root
        permissions: '0700'
        content: |
          #!/usr/bin/env bash
          set -euo pipefail

          systemctl restart ssh
          env ASOLADMIN_PASSWORD_FILE= EXPIRE_ASOLADMIN_PASSWORD=true /usr/local/sbin/prepare-ubuntu-node.sh
          env K3S_TLS_SAN="${K3S_TLS_SAN}" /usr/local/sbin/install-k3s-initial-server.sh
          shred -u /root/k3s-cluster-token
          touch /var/lib/cloud/asol-bootstrap-complete
    runcmd:
      - [/usr/local/sbin/asol-first-boot.sh]
