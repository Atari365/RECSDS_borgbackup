#!/usr/bin/env bash

export BORG_REPO=borg@localhost:~/borgbackup/$HOSTNAME
export KEEP_DAILY=7
export KEEP_WEEKLY=4
export KEEP_MONTHLY=4
export SCRIPT=../backup_scripts/borgbackup_virsh_domain.sh
export ARGS="autobackup_domain-name_{now:%Y-%m-%d} domain-name $BORG_REPO"
export PRUNE_PREFIX="autobackup_domain-name_"
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

cd $(dirname ${BASH_SOURCE[0]})

(eval $SCRIPT $ARGS) &
wait

(borg prune -v --list -P $PRUNE_PREFIX \
    --keep-daily=$KEEP_DAILY \
    --keep-weekly=$KEEP_WEEKLY \
    --keep-monthly=$KEEP_MONTHLY \
    $BORG_REPO) &
wait
