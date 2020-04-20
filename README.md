# RECSDS borgbackup project

## Install packages
```bash
sudo yum install -y borgbackup
```

## Create borg user
```bash
sudo useradd borg
sudo passwd borg
sudo usermod -aG wheel,libvirt borg
```

## SSH Keys (under borg user)
```bash
ssh-keygen
ssh-copy-id ip-or-hostname
```

## Disable some features in images
```bash
sudo rbd feature disable path-to-image object-map fast-diff deep-flatten
```
