# Architecture

**Analysis Date:** 2026-04-18

## Pattern Overview

**Overall:** Layered web application with Phoenix serving dual purposes: (1) HTTP/WebSocket server for future CLI client, and (2) SSH server for terminal-native access. Built on BEAM's concurrency primitives.

**Key Characteristics:**
- Clean separation between business domain (`FogletBbs.*`) and web layer (`FogletBbsWeb.*`)
- Supervision tree approach: all stateful systems supervised via OTP Application
- Context-driven architecture planned (not yet implemented in scaffolding phase)
- Presence-first design: real-time user tracking via Phoenix Presence integrated from the start
- Job queue infrastructure via Oban for background work (scheduled but not yet populated)

## Layers

**Application Core (`FogletBbs.*`):**
- Purpose: Business logic, domain models, data access, inter-service coordination
- Location: `lib/foglet_bbs/`
- Contains: Contexts (business domains), schemas (Ecto models), repo queries
- Depends on: Ecto, PostgreSQL
- Used by: Web layer, background jobs (Oban)

**Web Layer (`FogletBbsWeb.*`):**
- Purpose: HTTP routing, request handling, WebSocket channels, real-time features
- Location: `lib/foglet_bbs_web/`
- Contains: Router, controllers, channel handlers, error responses
- Depends on: Phoenix, Bandit (HTTP), core application
- Used by: HTTP clients, WebSocket clients (future CLI)

**SSH Server:**
- Purpose: Terminal-native user access over SSH
- Location: Not yet implemented (Milestone 3+)
- Planned integration: Erlang `:ssh` application
- Depends on: Custom TUI rendering logic, authentication context

**Infrastructure:**
- Purpose: Runtime setup, telemetry, configuration
- Location: `lib/foglet_bbs/application.ex`, `lib/foglet_bbs_web/endpoint.ex`, `lib/foglet_bbs_web/telemetry.ex`
- Contains: OTP supervision tree, Phoenix endpoint setup, metrics collection
- Key components:
  - `FogletBbs.Repo` - PostgreSQL connection pool
  - `FogletBbs.PubSub` - Phoenix pub/sub for real-time messaging
  - `DNSCluster` - Node discovery for distributed deployments
  - `FogletBbsWeb.Endpoint` - HTTP/WebSocket listener

## Data Flow

**HTTP/JSON Request Flow:**

1. Request arrives at `Bandit` HTTP server
2. `FogletBbsWeb.Endpoint` pipeline processes request:
   - Static file serving (via `Plug.Static`)
   - Request ID assignment
   - Telemetry instrumentation
   - Parameter parsing (form, multipart, JSON)
   - Session management (cookies)
3. Router (`FogletBbsWeb.Router`) dispatches to controller or channel
4. Controller/handler calls domain context (e.g., `FogletBbs.Users`)
5. Context performs validation and database operations via Ecto
6. Response serialized to JSON via `ErrorJSON` or custom response modules
7. Response sent to client with session cookie

**WebSocket/Channel Flow (Phoenix Channels):**

1. Client connects to `/live` socket
2. Connection validated; session loaded from cookie
3. Channel handler processes message
4. Message routed to appropriate channel module
5. Handler broadcasts to PubSub or updates Presence
6. Connected clients receive broadcast message in real-time

**State Management:**
- **Persistent state:** PostgreSQL (users, messages, boards, etc.)
- **Real-time state:** Phoenix Presence (who's online), ETS (in-memory caches)
- **Session state:** HTTP cookie (signed, encrypted optional)
- **Background work:** Oban job queue (future use for email digests, scheduled tasks)

## Key Abstractions

**Context Pattern:**
- Purpose: Encapsulate business logic and domain boundaries
- Examples: `FogletBbs.Users` (planned - user auth and profiles), `FogletBbs.Boards` (planned - message boards)
- Pattern: Public API functions that hide internal implementation; private functions for queries and changesets
- Not yet implemented (scaffolding phase)

**Ecto Schema & Changeset Pattern:**
- Purpose: Model definition and validation
- Examples: Not yet defined (pre-alpha)
- Pattern: Schemas define structure; changesets handle validation and transformation

**Phoenix Controller Pattern:**
- Purpose: HTTP request handling
- Examples: Not yet defined for domain (error handling in `FogletBbsWeb.ErrorJSON`)
- Pattern: Actions return `{:ok, data}` or `{:error, reason}` for JSON responses
- Configured for JSON-only (no HTML rendering)

**Phoenix Channel Pattern:**
- Purpose: Real-time bidirectional communication
- Examples: Not yet defined (infrastructure set up)
- Pattern: Join/leave lifecycle; message handlers broadcast to subscribers
- Configuration: `socket "/live"` with WebSocket and long-poll transports

**Repository Pattern (Ecto.Repo):**
- Purpose: Single entry point for all database operations
- Implementation: `FogletBbs.Repo` via `Ecto.Adapters.Postgres`
- Pattern: All queries go through repo; transactions coordinated at context level

## Entry Points

**HTTP Server:**
- Location: `lib/foglet_bbs_web/endpoint.ex`
- Triggers: Application startup; HTTP request arrival
- Responsibilities:
  - Listen on configured port (4000 dev, configurable in prod)
  - Apply middleware pipeline (logging, telemetry, security)
  - Route to appropriate handler
  - Serve static files

**Application Supervision Tree:**
- Location: `lib/foglet_bbs/application.ex`
- Triggers: Application startup via `FogletBbs.Application.start/2`
- Responsibilities:
  - Start Telemetry supervisor
  - Start database connection pool (`FogletBbs.Repo`)
  - Start DNS cluster for multi-node discovery
  - Start Phoenix PubSub
  - Start HTTP endpoint (Bandit)

**Mix Tasks:**
- Location: `lib/mix/tasks/foglet.doctor.ex`
- Triggers: `mix foglet.doctor` command
- Responsibilities:
  - Verify Elixir/Erlang versions match `.tool-versions`
  - Check PostgreSQL connectivity
  - Verify PostgreSQL `citext` extension
  - Check SSH host key presence
  - Verify environment variables

## Error Handling

**Strategy:** Pattern matching on result tuples (`{:ok, data}` or `{:error, reason}`)

**Patterns:**
- HTTP errors: `FogletBbsWeb.ErrorJSON.render/2` returns error JSON with status message
- Database errors: Ecto changesets collect validation errors; contexts propagate
- Router/channel errors: Phoenix catches and serializes exceptions
- Telemetry: Metrics collected on both success and exception paths

## Cross-Cutting Concerns

**Logging:**
- Framework: Elixir Logger (built-in)
- Approach: Structured logs via metadata (request IDs)
- Configuration: Level set to `:info` in production, `:debug` in development
- Future: Sentry integration for error aggregation (env var: `SENTRY_DSN`)

**Validation:**
- Framework: Ecto Changeset pattern
- Approach: Validators defined on schema; contexts return changesets with error messages
- Not yet implemented for domain (scaffolding phase)

**Authentication:**
- Framework: Session-based with Argon2 password hashing
- Approach: Custom implementation (bootstrapped from `mix phx.gen.auth`)
- Single active session per user: Designed but enforcement not yet implemented
- SSH public key auth: Planned for Milestone 3+
- Enforcement: Middleware in Phoenix router (not yet implemented)

**Database Transactions:**
- Pattern: Ecto.Repo.transaction/1 for multi-step operations
- Rollback on error: Automatic via transaction wrapper
- Implementation: Not yet used (no complex multi-entity operations)

---

*Architecture analysis: 2026-04-18*
