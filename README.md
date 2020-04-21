# RECSDS borgbackup project

## Deploy
### Install packages
```bash
sudo yum install -y borgbackup
```

### Create borg user
```bash
sudo useradd borg
sudo passwd borg
sudo usermod -aG wheel,libvirt borg
```

### SSH Keys (under borg user)
```bash
ssh-keygen
ssh-copy-id BORG_REPO_HOST
```

### Copy ceph.client.admin.keyring keyring to project
```bash
mkdir keys
sudo cp /etc/ceph/ceph.client.admin.keyring keys/
chmod 644 keys/ceph.client.admin.keyring
```

###  Make scripts executable
```bash
chmod +x backup_scripts/borgbackup_virsh_domain.sh
```

## Usage
# Manual virsh domain backup
```bash
./backup_scripts/borgbackup_virsh_domain.sh BACKUP_NAME DOMAIN [BORG_REPO]
```

## Optional
### Disable some features in images
```bash
sudo rbd feature disable path-to-image object-map fast-diff deep-flatten
```
