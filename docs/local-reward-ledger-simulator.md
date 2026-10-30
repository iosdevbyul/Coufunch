# Simulator-only local reward ledger integration

The shared Side Hustle screen uses TrisAdKit's real reward models. A new local bridge is compiled **only for DEBUG and iOS Simulator**; Release builds and physical devices continue to use the unconfigured provider. This does not change production HTTPS rules.

## Run locally

1. Update the TrisAdKit checkout on the Mac to include merged PR #16.
2. In TrisServerManager select **Reward Ledger Server** with the TrisAdKit checkout as the working directory.
3. Set its command to `REWARD_ENABLE_LOCAL_SESSIONS=1 python3 server/app.py`. Use local port `8765` and health check `/healthz`.
4. Start the service and confirm `curl http://127.0.0.1:8765/healthz` returns `{"status":"ok"}`.
5. Run Coufunch's DEBUG scheme on an iOS Simulator on the **same Mac**, open the sidebar's **부업** screen, and refresh points.

The bridge requests a server-created anonymous development session, then reads `GET /v1/rewards/points`. The bearer token lives only in provider memory for the current view instance; each new session gets a separate local test identity. As a result, a new app instance may show an empty balance even if another development identity has a ledger credit. The default is zero with no entries. This is a connectivity test, **not proof that TNK issued a reward**.

Use the Simulator: `127.0.0.1` on a real iPhone means that iPhone, not your Mac. The physical-device and Release paths are deliberately not connected. The local session issuance endpoint must remain on loopback and never be publicly exposed. No actual TNK ad integration or point crediting is enabled.
