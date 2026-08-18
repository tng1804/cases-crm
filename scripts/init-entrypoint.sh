#!/bin/bash
set -e

echo "======================================================================"
echo " Odoo Container Entrypoint Wrapper"
echo "======================================================================"

# In ra thông tin user hiện tại
echo "Running as user: $(whoami) (UID: $(id -u))"

# Chạy entrypoint mặc định của Odoo image và chuyển tiếp toàn bộ đối số (arguments)
echo "Delegating to original Odoo entrypoint..."
exec /entrypoint.sh "$@"
