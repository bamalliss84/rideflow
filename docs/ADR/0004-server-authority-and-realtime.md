# ADR-0004 Server authority, idempotency and real-time hints
Status: ACCEPTED (from 03_ARCHITECTURE_AND_API, D005)
Decision: server is the sole authority for trips, bids, matches, scores, subscriptions; every mutation carries idempotency key and expected version; WebSocket only hints; clients resync via REST snapshot + event cursor.
Alternatives: client-authoritative offline-first sync (unsafe for matching/money); polling only (higher bandwidth).
