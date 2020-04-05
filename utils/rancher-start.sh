#!/bin/bash
docker run -d --restart=unless-stopped \
  -p 80:80 -p 443:443 \
  -v /var/log/rancher/auditlog:/var/log/auditlog \
  -v /var/lib/rancher:/var/lib/rancher \
  -e AUDIT_LEVEL=1 \
  --name rancher \
  rancher/rancher:latest
