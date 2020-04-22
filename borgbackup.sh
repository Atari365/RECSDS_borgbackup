#!/usr/bin/env bash

export BORG_REPO=borg@$HOSTNAME:~/borgbackup/$HOSTNAME
export KEEP_DAILY=7
export KEEP_WEEKLY=4
export KEEP_MONTHLY=4

export TIMESTAMP={now:%Y-%m-%d}
export PRUNE_PREFIX=recsds

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

export virsh="virsh --connect qemu:///system"
export keyring=keys/ceph.client.admin.keyring
export rbd="rbd --keyring $keyring"

usage() {
echo "Usage: $0 [OPTIONS]... DOMAIN...
Backup DOMAIN(s) of libvirt via Borgbackup

  -kd, --keep-daily      how many backups of each day will be kept (Default: 7)
  -kw, --keep-weekly     how many backups of each week will be kept (Default: 4)
  -km, --keep-monthly    how many backups of each month will be kept (Default: 4)
  -t,  --timestamp       timestamp format (Default: {now:%Y-%m-%d})
  -r,  --repo            where to backup (Default: borg@\$HOSTNAME:~/borgbackup/\$HOSTNAME)
  -p,  --prefix          prefix used by prune (Default: recsds)
  -h,  --help            print this message

Examples:
  $0 --repo borg@10.0.1.15:~/borgbackup/web_servers
  $0 --keep-daily 7 centos
  $0 centos ubuntu"
}

error() {
  local -r msg=$1

  echo -e "[$(date +'%m/%d/%Y %H:%M:%S.%N')] Error: $msg"
  exit 1
}

create_repo() {
  echo [$(date +'%m/%d/%Y %H:%M:%S.%N')] Check repository $BORG_REPO:
  borg init --make-parent-dirs -e none $BORG_REPO > /dev/null 2>&1

  case $? in
    0)
      echo [$(date +'%m/%d/%Y %H:%M:%S.%N')] Repo $BORG_REPO created
      return 0
      ;;
    2)
      echo [$(date +'%m/%d/%Y %H:%M:%S.%N')] Repo $BORG_REPO exist
      return 1
      ;;
    *)
      error "Can't access or create repo"
      exit 1
      ;;
  esac
}

backup_domain() {
  local -r domain=$1
  local image=()
  local drive_name=()

  if [[ $($virsh list --all | grep $domain | awk '{print $3}') != running ]]; then
    error "Domain $domain does not exist"
  else
    echo [$(date +'%m/%d/%Y %H:%M:%S.%N')] Prepare to $domain backup
  fi

  # Get info about attached drives
  image=($($virsh domblklist --details $domain | awk '/disk/{print $4}' | tr " " "\n"))
  drive_name=($($virsh domblklist --details $domain | awk '/disk/{print $3}' | tr " " "\n"))

  # Freeze domain
  printf "[$(date +'%m/%d/%Y %H:%M:%S.%N')] "
  if ! $virsh domfsfreeze $domain | sed -r '/^\s*$/d'; then
    error "Unable to freeze filesystems"
  fi
  sleep 5 # For warranty
  for img in "${image[@]}"; do
    $rbd snap create $img@borg
    echo [$(date +'%m/%d/%Y %H:%M:%S.%N')]  Snapshot $img@borg created
  done
  printf "[$(date +'%m/%d/%Y %H:%M:%S.%N')] "
  $virsh domfsthaw $domain | sed -r '/^\s*$/d'

  for ((i = 0; i < ${#image[@]}; i++)); do
    echo [$(date +'%m/%d/%Y %H:%M:%S.%N')] Start backup $domain/${drive_name[$i]}
    # Backup RBD to Borg repo
    if $rbd export ${image[$i]}@borg - | borg create --stats \
         --stdin-name $domain"_"${drive_name[$i]}".raw" \
         $BORG_REPO::$PRUNE_PREFIX"_"$domain"_"${drive_name[$i]}"_"$TIMESTAMP -;
    then
      echo [$(date +'%m/%d/%Y %H:%M:%S.%N')] Backup $domain/${drive_name[$i]} complete
    else
      error "Backup $domain/${drive_name[$i]} stoped"
    fi
    $rbd snap rm ${image[$i]}@borg
  done

  return 0
}

main() {
  while [[ ! -z `pidof -x -o $$ $(basename $0)` ]]; do
    echo "$(date +'%m/%d/%Y %H:%M:%S.%N')] Backup already running..."
    sleep 10
  done

  if ! [[ -e $keyring ]]; then
    error "keys/ceph.client.admin.keyring not exist"
  fi

  create_repo

  printf "[$(date +'%m/%d/%Y %H:%M:%S.%N')] "
  for domain in $@; do
    backup_domain $domain
    borg prune -v --list -P $PRUNE_PREFIX"_"$domain \
        --keep-daily=$KEEP_DAILY \
        --keep-weekly=$KEEP_WEEKLY \
        --keep-monthly=$KEEP_MONTHLY \
        $BORG_REPO
  done

  return 0
}

cd $(dirname ${BASH_SOURCE[0]})
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi
while [[ "$1" != "" ]]; do
  case $1 in
    -h | --help )
      usage
      exit 0
      ;;
    -kd | --keep-daily)
      shift
      KEEP_DAILY=$1
      ;;
    -kw | --keep-weekly)
      shift
      KEEP_WEEKLY=$1
      ;;
    -km | --keep-monthly)
      shift
      KEEP_MONTHLY=$1
      ;;
    -r | --repo)
      shift
      BORG_REPO=$1
      ;;
    -t | --timestamp )
      shift
      TIMESTAMP=$1
      ;;
    -p | --prefix )
      shift
      PRUNE_PREFIX=$1
      ;;
    *)
      main $@
      shift $#
  esac
  shift
done
exit 0
