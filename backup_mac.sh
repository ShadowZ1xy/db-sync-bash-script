#!/bin/bash

cat banner

echo "[INFO] Starting db sync"
sleep 0.2

TEMPORARY_DATABASE_NAME="temporary777"
LOGS_FOLDER="logs"

PROFILE_NAME=$1
if [[ $1 != .* ]]; then
    PROFILE_NAME=.$1
fi

if [[ -f "profiles/$PROFILE_NAME" ]]; then
    export $(grep -v '^#' "profiles/$PROFILE_NAME" | xargs)
else 
    echo "[ERROR] Can't find profile $PROFILE_NAME"
    exit 1
fi

mkdir -p "$PATH_TO_BACKUP_FOLDER"
mkdir -p "$LOGS_FOLDER"

CURRENT_DATE=$(date +"%d-%m-%Y_%H-%M-%S")
LOG_FILE="$LOGS_FOLDER/log_${PROFILE_NAME#?}_${CURRENT_DATE}.log"
touch "$LOG_FILE"

echo "[INFO] Selected profile $1"
sleep 0.2

FILE_COUNT=$(ls $PATH_TO_BACKUP_FOLDER | grep -c $BACKUP_FILE_NAME)
if [[ $2 == "full" ]]; then
    echo "[INFO] Choosed full backup"
    sleep 0.2
    #if (( $(($FILE_COUNT)) >= 500 )); then
        #echo "[INFO] Backups count more then 500, deleting oldest"
        #sleep 0.2
        #OLDEST_FILE_NAME=$(ls -t "$PATH_TO_BACKUP_FOLDER" | tail -1)
        #rm $PATH_TO_BACKUP_FOLDER/$OLDEST_FILE_NAME
    #fi
    if (( $(($FILE_COUNT)) > 0 )); then
        echo "[INFO] Renaming old backup to not overwrite it"
        sleep 0.2
        OLD_BACKUP_DATETIME=$(date -r $PATH_TO_BACKUP_FOLDER/$BACKUP_FILE_NAME +"%d-%m-%Y_%H-%M-%S")
        NEW_FILE_NAME="${BACKUP_FILE_NAME}_${OLD_BACKUP_DATETIME}"
        mv $PATH_TO_BACKUP_FOLDER/$BACKUP_FILE_NAME $PATH_TO_BACKUP_FOLDER/$NEW_FILE_NAME
    fi
    echo "[INFO] Starting pg_dump from first server..."
    sleep 0.2
    DUMP_START_TIME=$(date +%s)
    PGPASSWORD=$PASSWORD_FOR_FIRST_DATABASE $PATH_TO_PG_FOLDER/pg_dump --file "$PATH_TO_BACKUP_FOLDER/$BACKUP_FILE_NAME" --host "$HOST_FOR_FIRST_DATABASE" --port "$PORT_FOR_FIRST_DATABASE" --username "$USERNAME_FOR_FIRST_DATABASE" --verbose --format=c --blobs "$FIRST_DATABASE_NAME" >> "$LOG_FILE" 2>&1
    DUMP_END_TIME=$(date +%s)
    DUMP_TIME_SECONDS=$(($DUMP_END_TIME - $DUMP_START_TIME))
    echo "[INFO] Dump takes $DUMP_TIME_SECONDS seconds"
else
    if (( $(($FILE_COUNT)) == 0 )); then
        echo "[ERROR] Can't find backup file, pls run first with 'full' flag" 2>&1 | tee $LOG_FILE
        exit 1
    fi
fi

echo "[INFO] Clean existing db to restore it with new"
sleep 0.2

if $IS_DOCKER; then
{
    docker exec -it $DOCKER_CONTAINER_NAME psql -U $USERNAME_FOR_SECOND_DATABASE -d postgres -c "CREATE DATABASE $TEMPORARY_DATABASE_NAME;"
    docker exec -it $DOCKER_CONTAINER_NAME psql -U $USERNAME_FOR_SECOND_DATABASE -d $TEMPORARY_DATABASE_NAME -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$SECOND_DATABASE_NAME' AND pid <> pg_backend_pid();"
    docker exec -it $DOCKER_CONTAINER_NAME psql -U $USERNAME_FOR_SECOND_DATABASE -d $TEMPORARY_DATABASE_NAME -c "DROP DATABASE $SECOND_DATABASE_NAME;"
    docker exec -it $DOCKER_CONTAINER_NAME psql -U $USERNAME_FOR_SECOND_DATABASE -d $TEMPORARY_DATABASE_NAME -c "CREATE DATABASE $SECOND_DATABASE_NAME;"
} >> "$LOG_FILE" 2>&1
else
{
    psql -U $USERNAME_FOR_SECOND_DATABASE -d postgres -c "CREATE DATABASE $TEMPORARY_DATABASE_NAME;"
    psql -U $USERNAME_FOR_SECOND_DATABASE -d $TEMPORARY_DATABASE_NAME -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$SECOND_DATABASE_NAME' AND pid <> pg_backend_pid();"
    psql -U "$USERNAME_FOR_SECOND_DATABASE" -d $TEMPORARY_DATABASE_NAME -c "DROP DATABASE $SECOND_DATABASE_NAME;"
    psql -U $USERNAME_FOR_SECOND_DATABASE -d $TEMPORARY_DATABASE_NAME -c "CREATE DATABASE $SECOND_DATABASE_NAME;"
} >> "$LOG_FILE" 2>&1
fi

echo "[INFO] Starting pg_restore to second db"
sleep 0.2
PGPASSWORD=$PASSWORD_FOR_SECOND_DATABASE $PATH_TO_PG_FOLDER/pg_restore --host "$HOST_FOR_SECOND_DATABASE" --port "$PORT_FOR_SECOND_DATABASE" --username "$USERNAME_FOR_SECOND_DATABASE" --dbname "$SECOND_DATABASE_NAME" --verbose "$PATH_TO_BACKUP_FOLDER/$BACKUP_FILE_NAME" >> "$LOG_FILE" 2>&1
echo "[INFO] Done"
