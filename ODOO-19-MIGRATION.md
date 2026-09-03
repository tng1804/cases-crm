# Quy trình nâng cấp Odoo 18 lên Odoo 19

Tài liệu này mô tả quy trình nâng cấp cho project Docker hiện tại.

## Trạng thái hiện tại

- Image đã đổi từ `odoo:18` sang `odoo:19`.
- Đã cài `openupgradelib` vào image Odoo 19.
- Đã clone OpenUpgrade nhánh `19.0` vào `.openupgrade/`.
- Đã backup database và filestore.
- Hai database `cases_crm` và `case_crm_test` đã chạy OpenUpgrade thành công.
- Cả hai database đã xác nhận module `base` ở phiên bản `19.0.1.3`.
- Odoo đã khởi động và endpoint database selector trả HTTP 200.

## 1. Chuẩn bị

Kiểm tra Docker và PostgreSQL:

```bash
docker compose ps db odoo
```

Kiểm tra source OpenUpgrade:

```bash
test -d .openupgrade/openupgrade_framework
test -d .openupgrade/openupgrade_scripts
```

Nếu chưa có source:

```bash
git clone --branch 19.0 --depth 1 \
  https://github.com/OCA/OpenUpgrade.git .openupgrade
```

Đảm bảo tất cả module custom đã có phiên bản tương thích Odoo 19. Project hiện chưa có custom addon thực tế ngoài `.gitkeep`.

## 2. Backup bắt buộc

Backup database:

```bash
mkdir -p backups
backup_file="backups/odoo-full-$(date +%Y%m%d-%H%M%S).sql.gz"
docker compose exec -T db sh -c 'pg_dumpall -U "$POSTGRES_USER"' \
  | gzip -9 > "$backup_file"
chmod 600 "$backup_file"
gzip -t "$backup_file"
```

Backup filestore, nơi chứa attachments và file nhị phân:

```bash
backup_file="backups/odoo-filestore-$(date +%Y%m%d-%H%M%S).tar.gz"
docker run --rm -v cases-crm_odoo_data:/data alpine \
  tar -C /data -czf - filestore > "$backup_file"
chmod 600 "$backup_file"
gzip -t "$backup_file"
```

Không chạy `docker compose down -v`, vì lệnh này xóa named volumes.

## 3. Build image Odoo 19

```bash
docker compose build odoo
docker run --rm --entrypoint /usr/bin/odoo cases-crm-odoo --version
```

Kết quả cần bắt đầu bằng `Odoo Server 19.0`.

## 4. Chạy migration

Dừng Odoo trước khi migration:

```bash
docker compose stop odoo
```

Migration từng database:

```bash
scripts/migrate-to-19.sh cases_crm
scripts/migrate-to-19.sh case_crm_test
```

Script sẽ:

- kiểm tra OpenUpgrade 19.0;
- kiểm tra PostgreSQL và database tồn tại;
- từ chối database hệ thống;
- yêu cầu Odoo đã dừng;
- yêu cầu xác nhận trước khi sửa database;
- chạy `--update all` và `--stop-after-init`.

Không chạy hai database đồng thời trên cùng volume PostgreSQL.

## 5. Kiểm tra database sau migration

```bash
docker compose exec -T db sh -c \
  'psql -U "$POSTGRES_USER" -d cases_crm -Atc \
  "SELECT latest_version FROM ir_module_module WHERE name='"'"'base'"'"';"'

docker compose exec -T db sh -c \
  'psql -U "$POSTGRES_USER" -d case_crm_test -Atc \
  "SELECT latest_version FROM ir_module_module WHERE name='"'"'base'"'"';"'
```

Kết quả mong đợi là `19.0.x`. Kiểm tra module còn chờ nâng cấp:

```bash
docker compose exec -T db sh -c \
  'psql -U "$POSTGRES_USER" -d cases_crm -Atc \
  "SELECT COUNT(*) FROM ir_module_module WHERE state='"'"'to upgrade'"'"';"'
```

Kết quả mong đợi là `0`.

## 6. Khởi động và kiểm tra ứng dụng

```bash
docker compose up -d odoo
docker compose ps odoo db
curl -fsS --retry 5 --retry-delay 2 \
  http://127.0.0.1:8069/web/database/selector \
  -o /tmp/odoo-health.html -w 'HTTP %{http_code}\n'
```

Kiểm tra log:

```bash
docker compose logs --no-color --tail=200 odoo
```

Kiểm tra thủ công trên từng database:

- đăng nhập và phân quyền;
- Contacts, CRM, Sales, Purchase, Inventory, Project và Accounting;
- tạo bản ghi mới, sửa, xóa và tìm kiếm;
- upload/download attachment;
- gửi email và kiểm tra scheduled actions;
- kiểm tra báo cáo, PDF và dữ liệu tiếng Việt;
- kiểm tra tích hợp bên ngoài và API.

## 7. WebSocket và reverse proxy

Odoo 19 dùng `gevent_port` thay cho `longpolling_port`. Project đã cấu hình `gevent_port = 8072` và xác nhận log `Evented Service (longpolling) running on 0.0.0.0:8072`. Nginx đã có route `/websocket` đến upstream cổng `8072` với HTTP/1.1 và Upgrade headers; route `/longpolling` được giữ để tương thích endpoint cũ.

```bash
docker compose logs --no-color odoo | grep -Ei \
  'websocket|longpolling|gevent|error|critical'
```

Smoke test HTTP thành công chưa đủ để xác nhận chat, bus notification và live update hoạt động. Sau khi chỉnh cấu hình, kiểm tra lại từ trình duyệt và qua Nginx.

Kết quả kiểm tra trực tiếp hiện tại:

- HTTP `8069`: trả `200`.
- WebSocket `8072`: trả `101 SWITCHING PROTOCOLS` với `Origin` và WebSocket headers hợp lệ.
- Nginx syntax: `syntax is ok` và `test is successful`.

Cần kiểm tra thêm qua domain HTTPS thực tế nếu Nginx đang chạy ngoài Docker, vì file `nginx/nginx.conf` của project chưa được mount vào container Nginx.

## 8. Nếu migration thất bại

Không tiếp tục chạy Odoo 19 trên database lỗi. Dừng Odoo và restore database bị ảnh hưởng từ backup trước migration. Với backup `pg_dumpall`, có thể restore riêng phần database sau khi drop/recreate database đó; cần xác định đúng điểm `\\connect <database>` trong file dump.

Filestore phải được restore đồng bộ với database. Database và filestore lệch thời điểm có thể làm mất attachment hoặc tạo reference không hợp lệ.

## 9. Sau khi nghiệm thu

- Giữ lại database backup và filestore backup ngoài máy chủ production.
- Không commit `.env`, `backups/` hoặc `.openupgrade/` vào Git.
- Đổi `POSTGRES_PASSWORD`, `DB_PASSWORD` và `ODOO_ADMIN_PASSWORD` nếu các secret đã từng được chia sẻ hoặc dùng cho môi trường production.
- Ghi lại phiên bản image, thời điểm migration và kết quả kiểm thử.
- Chỉ bật traffic production sau khi kiểm thử nghiệp vụ và WebSocket hoàn tất.

## Tài liệu tham khảo

- OpenUpgrade: https://github.com/OCA/OpenUpgrade/tree/19.0
- Odoo Upgrade service: dùng khi có Enterprise/subscription và cần đường nâng chính thức.
