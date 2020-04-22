# Deploy
### Install packages
```bash
sudo yum install -y borgbackup
```
### Create borg user
```bash
sudo useradd borg
sudo passwd borg
sudo usermod -aG libvirt borg
```
### SSH Keys (under borg user)
```bash
ssh-keygen
ssh-copy-id <borg-repo-host>
```
### Copy ceph.client.admin.keyring keyring to project
```bash
mkdir keys
sudo ceph auth get-or-create client.borg mgr 'allow r' mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=images, allow rwx pool=volumes, allow rwx pool=vms, allow rwx pool=ssd-root' -o keys/ceph.client.borg.keyring
sudo chown borg:borg keys/ceph.client.borg.keyring
```
###  Make scripts executable
```bash
git clone <github-repo>
cd RECSDS_borgbackup
chmod +x borgbackup.sh
```

### Create log dir
```bash
sudo mkdir /var/log/recsds_borgbackup/
sudo chown borg:borg /var/log/recsds_borgbackup/
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
For more information run
```bash
./borgbackup.sh --help
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
