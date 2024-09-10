# swapping:
curl https://github.com/hornowitz/rog-fightmilk/raw/master/rog-create-zfs-swap.sh -o /usr/local/bin/rog-create-zfs-swap.sh
chmod +x /usr/local/bin/rog-create-zfs-swap.sh


cat << EOF >> /etc/systemd/system/rog-create-zfs-swap.service
[Unit]
Description=Create and Configure ZFS Swap File
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rog-create-zfs-swap.sh -z rog-babaracus-01 -d swap -s 32G -c
# -D off -C zle -L throughput -A off -R off -x 8k -S off -H fletcher4 -P none -Q none -Y always
# Ensure the script is executable and accessible by root
User=root
Group=root
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rog-create-zfs-swap.service --now
