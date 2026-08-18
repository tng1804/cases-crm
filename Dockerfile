FROM odoo:18

USER root

# Tạo thư mục cho custom addons và phân quyền cho user odoo
RUN mkdir -p /mnt/extra-addons && chown -R odoo:odoo /mnt/extra-addons

# Copy script entrypoint wrapper và phân quyền
COPY --chown=odoo:odoo scripts/init-entrypoint.sh /init-entrypoint.sh
RUN chmod +x /init-entrypoint.sh

# Chuyển lại về user odoo để bảo mật (tránh chạy root trong container)
USER odoo

ENTRYPOINT ["/init-entrypoint.sh"]
CMD ["odoo"]