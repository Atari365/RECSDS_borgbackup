# Deploy
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
chmod +x borgbackup.sh
```

## Install qemu agent on domain
### Open domain xml, and add this to <devices>
```xml
<channel type='unix'>
  <source mode='bind' path='/var/lib/libvirt/qemu/org.qemu.guest_agent.0.<guest-name>.sock'/>
  <target type='virtio' name='org.qemu.guest_agent.0'/>
</channel>
```

### On the domain install the guest-agent
```bash
sudo yum install qemu-guest-agent
```

### Enable the agent
```bash
sudo systemctl start qemu-guest-agent
sudo systemctl enable qemu-guest-agent
```

### Test the communication from the KVM Host
```bash
sudo virsh qemu-agent-command <guest-name> '{"execute":"guest-info"}'
```

# Usage
## Manual virsh domain backup
```bash
./borgbackup.sh [OPTIONS]... DOMAIN...
```

## Automation backup
### Add script to crontab
```bash
crontab -e
```
And add this string
```bash
0 0 * * * path-to-auto-backup-script [OPTIONS]... DOMAIN...
```

# Optional
## Disable some features in images
```bash
sudo rbd feature disable path-to-image object-map fast-diff deep-flatten
```
