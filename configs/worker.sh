#!/bin/bash
set -e

TASKS_PATH="/home/op/bin/tasks.py"

if [ -z "$S3_CONFIG_BUCKET" ]; then
    echo "S3_CONFIG_BUCKET is not set" >&2
    exit 1
fi

echo "Pulling latest tasks.py from s3://$S3_CONFIG_BUCKET/tasks.py"
aws s3 cp "s3://$S3_CONFIG_BUCKET/tasks.py" "$TASKS_PATH"

echo "Starting Celery worker"
exec celery -A tasks worker --loglevel=info
