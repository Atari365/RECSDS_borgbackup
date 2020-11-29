#!/usr/bin/env bash

export BORG_REPO=borg@$HOSTNAME:~/borgbackup/$HOSTNAME
export KEEP_DAILY=7
export KEEP_WEEKLY=4
export KEEP_MONTHLY=4

export PRUNE=true
export PRUNE_PREFIX=recsds
export LOG_TIMESTAMP=[$(date +'%m/%d/%Y %H:%M:%S.%N')]
export TIMESTAMP={now:%Y-%m-%d}
export BACKUP_NAME

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

export virsh="virsh --connect qemu:///system"
export keyring=keys/ceph.client.borg.keyring
export rbd="rbd --user borg --keyring $keyring"
export PIDFILE=recsds_borgbackup.pid

usage() {
echo "Usage: $0 [OPTIONS]... DOMAIN...
Backup DOMAIN(s) of libvirt via Borgbackup

  -kd, --keep-daily    How many backups of each day will be kept (Default: 7)
  -kw, --keep-weekly   How many backups of each week will be kept (Default: 4)
  -km, --keep-monthly  How many backups of each month will be kept (Default: 4)
  -t,  --timestamp     Timestamp format (Default: {now:%Y-%m-%d})
  -r,  --repo          Where to backup (Default: borg@\$HOSTNAME:~/borgbackup/\$HOSTNAME)
  -p,  --prefix        Prefix used by prune (Default: recsds)
  -np, --not-prune     Do not prune (For manual backup, default - off)
  -n,  --name          Set the custom name (Default: \$PREFIX_\$DOMAIN_\$DRIVE_\$TIMESTAMP;
                       work with only one domain)
  -h,  --help          Print this message

Examples:
  $0 --repo borg@10.0.1.15:~/borgbackup/web_servers
  $0 --keep-daily 7 centos
  $0 centos ubuntu"
}

error() {
  local -r msg=$1

  echo -e $LOG_TIMESTAMP Error: $msg
  exit 1
}

create_repo() {
  echo $LOG_TIMESTAMP Check repository $BORG_REPO:
  borg init --make-parent-dirs -e none $BORG_REPO

  case $? in
    0)
      echo $LOG_TIMESTAMP Repo $BORG_REPO created
      return 0
      ;;
    2)
      echo $LOG_TIMESTAMP Repo $BORG_REPO exist
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
  local flag=true

  if [[ $($virsh list --all | awk '{print $2}' | grep '^controller-virt$') != running ]]; then
    error "Domain $domain does not exist"
  else
    echo $LOG_TIMESTAMP Prepare to $domain backup
  fi

  # Get info about attached drives
  image=($($virsh domblklist --details $domain | awk '/disk/{print $4}' | tr " " "\n"))
  drive_name=($($virsh domblklist --details $domain | awk '/disk/{print $3}' | tr " " "\n"))

  # Freeze domain
  printf "$LOG_TIMESTAMP "
  if ! $virsh domfsfreeze $domain | sed -r '/^\s*$/d'; then
    error "Unable to freeze filesystems"
  fi
  sleep 5 # For warranty
  for img in "${image[@]}"; do
    if $rbd snap create $img@borg; then
      echo $LOG_TIMESTAMP  Snapshot $img@borg created
    fi
  done
  printf "$LOG_TIMESTAMP "
  $virsh domfsthaw $domain | sed -r '/^\s*$/d'

  for ((i = 0; i < ${#image[@]}; i++)); do
    echo $LOG_TIMESTAMP Start backup $domain/${drive_name[$i]}
    if [[ ! $BACKUP_NAME ]]; then
      if $PRUNE; then
        BACKUP_NAME=$PRUNE_PREFIX"_"$domain"_"${drive_name[$i]}"_"$TIMESTAMP
      else
        BACKUP_NAME=$domain"_"${drive_name[$i]}"_"$TIMESTAMP
      fi
    else
      flag=false
      if $PRUNE; then
        BACKUP_NAME=$PRUNE_PREFIX"_"$BACKUP_NAME
      fi
    fi
    # Backup RBD to Borg repo
    if $rbd export ${image[$i]}@borg - | borg create --stats \
         --stdin-name $domain"_"${drive_name[$i]}".raw" \
         $BORG_REPO::$BACKUP_NAME -;
    then
      echo $LOG_TIMESTAMP Backup $domain/${drive_name[$i]} complete
    else
      error "Backup $domain/${drive_name[$i]} stoped"
    fi
    $rbd snap rm ${image[$i]}@borg
    if $PRUNE; then
      if $flag; then
        echo $LOG_TIMESTAMP Prune prefix: $PRUNE_PREFIX"_"$domain"_"${drive_name[$i]}"_"
        borg prune -v --list -P $PRUNE_PREFIX"_"$domain"_"${drive_name[$i]}"_" \
            --keep-daily=$KEEP_DAILY \
            --keep-weekly=$KEEP_WEEKLY \
            --keep-monthly=$KEEP_MONTHLY \
            $BORG_REPO
      else
        echo $LOG_TIMESTAMP Prune prefix: $PRUNE_PREFIX"_"
        borg prune -v --list -P $PRUNE_PREFIX"_" \
            --keep-daily=$KEEP_DAILY \
            --keep-weekly=$KEEP_WEEKLY \
            --keep-monthly=$KEEP_MONTHLY \
            $BORG_REPO
      fi
    fi
    BACKUP_NAME=""
  done

  return 0
}

main() {
  while [[ -e $PIDFILE ]]; do
    echo $LOG_TIMESTAMP Warning: Backup already running...
    sleep 60
  done
  trap "rm -f -- '$PIDFILE'" EXIT
  echo $$ > $PIDFILE

  if ! [[ -e $keyring ]]; then
    error "keys/ceph.client.borg.keyring not exist"
  fi

  create_repo

  if [[ $BACKUP_NAME == "" ]]; then
    for domain in $@; do
      backup_domain $domain
    done
  else
    if [[ $# -gt 1 ]]; then
      error "You are using the flag name. With it, you can backup only one domain at a time."
    fi
    backup_domain $1
  fi

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
    -t | --timestamp)
      shift
      TIMESTAMP=$1
      ;;
    -p | --prefix)
      shift
      PRUNE_PREFIX=$1
      ;;
    -np | --not-prune)
      PRUNE=false
      ;;
    -n | --name)
      shift
      BACKUP_NAME=$1
      ;;
    *)
      main $@
      shift $#
  esac
  shift
done
exit 0
