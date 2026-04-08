## GitHub Copilot Chat

- Extension: 0.42.3 (prod)
- VS Code: 1.114.0 (e7fb5e96c0730b9deb70b33781f98e2f35975036)
- OS: linux 6.6.87.2-microsoft-standard-WSL2 x64
- Remote Name: wsl
- Extension Kind: Workspace
- GitHub Account: xy1122389-ops

## Network

User Settings:
```json
  "http.systemCertificatesNode": true,
  "github.copilot.advanced.debug.useElectronFetcher": true,
  "github.copilot.advanced.debug.useNodeFetcher": false,
  "github.copilot.advanced.debug.useNodeFetchFetcher": true
```

Connecting to https://api.github.com:
- DNS ipv4 Lookup: 140.82.116.6 (614 ms)
- DNS ipv6 Lookup: Error (637 ms): getaddrinfo ENOTFOUND api.github.com
- Proxy URL: None (0 ms)
- Electron fetch: Unavailable
- Node.js https: HTTP 200 (1417 ms)
- Node.js fetch (configured): HTTP 200 (1466 ms)

Connecting to https://api.individual.githubcopilot.com/_ping:
- DNS ipv4 Lookup: 140.82.112.21 (627 ms)
- DNS ipv6 Lookup: Error (588 ms): getaddrinfo ENOTFOUND api.individual.githubcopilot.com
- Proxy URL: None (0 ms)
- Electron fetch: Unavailable
- Node.js https: HTTP 200 (1622 ms)
- Node.js fetch (configured): HTTP 200 (250 ms)

Connecting to https://proxy.individual.githubcopilot.com/_ping:
- DNS ipv4 Lookup: 138.91.182.224 (601 ms)
- DNS ipv6 Lookup: Error (661 ms): getaddrinfo ENOTFOUND proxy.individual.githubcopilot.com
- Proxy URL: None (0 ms)
- Electron fetch: Unavailable
- Node.js https: HTTP 200 (1535 ms)
- Node.js fetch (configured): HTTP 200 (1510 ms)

Connecting to https://mobile.events.data.microsoft.com: HTTP 404 (294 ms)
Connecting to https://dc.services.visualstudio.com: HTTP 404 (1747 ms)
Connecting to https://copilot-telemetry.githubusercontent.com/_ping: HTTP 200 (1645 ms)
Connecting to https://telemetry.individual.githubcopilot.com/_ping: HTTP 200 (1627 ms)
Connecting to https://default.exp-tas.com: HTTP 400 (1627 ms)

Number of system certificates: 432

## Documentation

In corporate networks: [Troubleshooting firewall settings for GitHub Copilot](https://docs.github.com/en/copilot/troubleshooting-github-copilot/troubleshooting-firewall-settings-for-github-copilot).