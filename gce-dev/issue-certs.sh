#!/bin/bash
# Run after A records for the three hosts point at 8.234.105.200
set -euxo pipefail
certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email \
  -d dev.crowdandcult.com \
  -d admin.dev.crowdandcult.com \
  -d api.dev.crowdandcult.com
