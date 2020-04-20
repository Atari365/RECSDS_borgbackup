#!/usr/bin/env bash

export BORG_REPO=~/borgbackup/$HOSTNAME
virsh="virsh --connect qemu:///system"
rbd="rbd --keyring keys/ceph.client.admin.keyring"

error() {
  local -r msg=$1

  echo -e Error: $msg
  exit 1
}

create_repo() {
  echo check repository $BORG_REPO:
  borg init --make-parent-dirs -e none $BORG_REPO > /dev/null 2>&1

  case $? in
    0)
      echo repo $BORG_REPO created
      return 0
      ;;
    2)
      echo repo $BORG_REPO exist
      return 1
      ;;
    *)
      echo unexpected error, exit...
      exit 1
      ;;
  esac
}

snap_domain() {
  local -r domain=$1; shift
  local images=""

  # Create snapshots in ceph
  $virsh suspend $domain
  while [[ -n $1 ]]; do
    images+=" $1"
    $rbd snap create ${1:0:-3}@borg
    shift
  done
  $virsh resume $domain

  # Export all snapshots and delete in ceph
  for image in $images; do
    $rbd export ${image:0:-3}@borg "/tmp/"$domain"_"${image: -3}"_borg.raw"
    $rbd snap rm ${image:0:-3}@borg
  done

  $virsh dumpxml $domain > "/tmp/"$domain"_borg.xml"

  return 0
}

backup_domain() {
  local -r name=$1
  local -r domain=$2

  if [[ -z $domain ]] || ! $virsh dominfo $domain; then
    error "Domain $domain does not exist"
  fi

  # Get info about attached drives
  images=$($virsh domblklist --details $domain | awk '/disk/{print $4}')
  block_drives=$($virsh domblklist --details $domain | awk '/disk/{print $3}')

  snap_domain $domain $($virsh domblklist --details $domain | awk '/disk/{print $4$3}')

  for blk in $block_drives; do
    backup_images+=" /tmp/"$domain"_"$blk"_borg.raw"
  done

  echo Start backup
  (borg create --stats $BORG_REPO::"$name-{now:%Y-%m-%d_%H:%M}" $backup_images "/tmp/"$domain"_borg.xml"

  for img in $backup_images; do
    rm $img
  done
  rm"/tmp/"$domain"_borg.xml") &
}

while [[ ! -z `pidof -x -o $$ $(basename "$0")` ]]; do
  echo "Backup already running..."
  sleep 10
done

create_repo
backup_domain $1 $2
