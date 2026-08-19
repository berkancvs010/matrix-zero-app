# ZeroLog server release

`server.js` is the VDS-side release version.

Deploy from the extracted ZIP on the VDS:

```bash
cd ~/matrix-zero-app-main/server
bash deploy-server.sh
```

The script:
1. backs up the existing VDS `server.js`;
2. installs the release `server.js`;
3. runs `node --check`.

Restart the existing ZeroLog Node service with the same process manager/command already used on the VDS after the check succeeds.
