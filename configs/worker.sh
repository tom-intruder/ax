#!/bin/zsh
set -e

TASKS_PATH="/home/op/bin/tasks.py"

source /home/op/.zshrc

export $(xargs < /home/op/bin/worker.env)

if [ -z "$S3_CONFIG_BUCKET" ]; then
    echo "S3_CONFIG_BUCKET is not set" >&2
    exit 1
fi

echo "Pulling latest tasks.py from s3://$S3_CONFIG_BUCKET/tasks.py"
aws s3 cp "s3://$S3_CONFIG_BUCKET/tasks.py" "$TASKS_PATH"

echo "Pulling latest config from s3://$S3_CONFIG_BUCKET/config.env"
aws s3 cp "s3://$S3_CONFIG_BUCKET/config.env" /home/op/bin/config.env
export $(xargs < /home/op/bin/config.env)

echo "Starting Celery worker"
exec /home/op/.local/bin/celery -A tasks worker --loglevel=info
