#!/usr/bin/env bash

export BORG_REPO=${3:-"~/borgbackup/$HOSTNAME"}
export virsh="virsh --connect qemu:///system"
export rbd="rbd --keyring ../keys/ceph.client.admin.keyring"

error() {
  local -r msg=$1

  echo -e Error: $msg
  exit 1
}

create_repo() {
  echo Check repository $BORG_REPO:
  borg init --make-parent-dirs -e none $BORG_REPO > /dev/null 2>&1

  case $? in
    0)
      echo Repo $BORG_REPO created
      return 0
      ;;
    2)
      echo Repo $BORG_REPO exist
      return 1
      ;;
    *)
      echo error "Can't access or create repo"
      exit 1
      ;;
  esac
}

snap_domain() {
  local -r domain=$1; shift
  local -r drives_amount=$(($# / 2))
  local image=()
  local drive_name=()

  if ! $virsh domfsfreeze $domain; then
    error "Unable to freeze filesystems"
  fi
  sleep 30
  for ((i = 0; i < $drives_amount; i++)); do
    image+=($1)
    $rbd snap create $1@borg
    echo Snapshot $1@borg created
    shift
  done
  echo ""
  $virsh domfsthaw $domain

  for ((i = 0; i < $drives_amount; i++)); do
    drive_name+=($1); shift
  done

  for ((i = 0; i < $drives_amount; i++)); do
    $rbd export ${image[$i]}@borg "/tmp/"$domain"_"${drive_name[$i]}"_borg.raw"
    $rbd snap rm ${image[$i]}@borg
  done

  $virsh dumpxml $domain > "/tmp/"$domain"_borg.xml"

  return 0
}

backup_domain() {
  local -r name=$1
  local -r domain=$2
  local -r domain_state=$($virsh list --all | grep $domain | awk '{print $3}')
  local image
  local drive_name
  local backup_images
  local xml

  if [[ $domain_state != running ]]; then
    error "Domain $domain does not exist"
  fi

  # Get info about attached drives
  image=$($virsh domblklist --details $domain | awk '/disk/{print $4}')
  drive_name=$($virsh domblklist --details $domain | awk '/disk/{print $3}')

  snap_domain $domain $image $drive_name

  for blk in $drive_name; do
    backup_images+=" /tmp/"$domain"_"$blk"_borg.raw"
  done

  xml="/tmp/"$domain"_borg.xml"

  echo Start backup
  (borg create --stats $BORG_REPO::$name $backup_images $xml > /dev/null 2>&1) &
  wait

  for img in $backup_images; do
   rm $img
  done
  rm "/tmp/"$domain"_borg.xml"
  echo Backup complete
}

cd $(dirname ${BASH_SOURCE[0]})

if ! [[ -e ../keys/ceph.client.admin.keyring ]]; then
  error "keys/ceph.client.admin.keyring not exist"
fi

while [[ ! -z `pidof -x -o $$ $(basename $0)` ]]; do
  echo "Backup already running..."
  sleep 10
done

create_repo
echo ""
backup_domain $1 $2 $3
