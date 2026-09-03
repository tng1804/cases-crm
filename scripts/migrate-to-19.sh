#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OPENUPGRADE_DIR=${OPENUPGRADE_DIR:-$PROJECT_DIR/.openupgrade}
DATABASE=${1:-}

if [ -z "$DATABASE" ]; then
    echo "Usage: $0 DATABASE_NAME" >&2
    echo "Example: $0 cases_crm" >&2
    exit 2
fi

case "$DATABASE" in
    postgres|template0|template1)
        echo "Refusing to migrate PostgreSQL system database: $DATABASE" >&2
        exit 2
        ;;
esac

if [ ! -d "$OPENUPGRADE_DIR/openupgrade_framework" ] || [ ! -d "$OPENUPGRADE_DIR/openupgrade_scripts" ]; then
    echo "OpenUpgrade 19.0 source is missing at $OPENUPGRADE_DIR" >&2
    echo "Clone it first:" >&2
    echo "  git clone --branch 19.0 --depth 1 https://github.com/OCA/OpenUpgrade.git $OPENUPGRADE_DIR" >&2
    exit 1
fi

if ! docker compose ps --status running --services | grep -qx db; then
    echo "PostgreSQL service must be running." >&2
    exit 1
fi

if docker compose ps --status running --services | grep -qx odoo; then
    echo "Stop Odoo before migration: docker compose stop odoo" >&2
    exit 1
fi

if ! docker compose exec -e DATABASE_NAME="$DATABASE" -T db sh -c 'psql -U "$POSTGRES_USER" -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '\''$DATABASE_NAME'\'';"' </dev/null | grep -qx 1; then
    echo "Database does not exist: $DATABASE" >&2
    exit 1
fi

echo "Migrating database: $DATABASE"
echo "This changes the database in place. Use the verified SQL and filestore backups first."
printf "Type MIGRATE-%s to continue: " "$DATABASE"
read confirmation
if [ "$confirmation" != "MIGRATE-$DATABASE" ]; then
    echo "Migration cancelled."
    exit 1
fi

docker compose run --rm \
    -T \
    --no-deps \
    -v "$OPENUPGRADE_DIR:/mnt/openupgrade:ro" \
    odoo \
    odoo -c /etc/odoo/odoo.conf \
        --database "$DATABASE" \
        --update all \
        --stop-after-init \
        --load base,web,openupgrade_framework \
        --addons-path /usr/lib/python3/dist-packages/odoo/addons,/mnt/openupgrade,/mnt/extra-addons

echo "Migration finished for $DATABASE. Review the log before starting Odoo 19."