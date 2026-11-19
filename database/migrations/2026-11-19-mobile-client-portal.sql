-- ============================================================================
-- Mobile client portal — database support (2026-11-19)
--
-- The organizer mobile app reads and writes the SAME tables as the web client
-- portal: clients, events, tickets, payments, auth_tokens. No new column was
-- required, and nothing is removed here. The only columns in those tables that
-- no web/API code reads or writes are three legacy event scheduling flags,
-- dropped by 2026-11-19-drop-unused-event-columns.sql; every other column
-- (including the deprecated Paystack subaccount columns) is still referenced.
--
-- This migration is additive and idempotent. It only adds covering indexes for
-- the queries the app fires on every launch (dashboard, events, tickets,
-- payments) plus a token lookup index for the session-refresh endpoint, so
-- those screens stay fast as the tables grow.
--
-- Run once per environment:
--   mysql -u USER -p DB_NAME < database/migrations/2026-11-19-mobile-client-portal.sql
-- ============================================================================

-- events: "my events" dashboard + upcoming/passed filters.
SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE events ADD INDEX idx_event_client_date (client_id, event_date, deleted_at)',
        'SELECT 1'
    )
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'events'
      AND index_name = 'idx_event_client_date'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- payments: client revenue summary + recent payments list.
SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE payments ADD INDEX idx_payment_event_status_created (event_id, status, created_at)',
        'SELECT 1'
    )
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'payments'
      AND index_name = 'idx_payment_event_status_created'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- tickets: sold tickets per event, newest first.
SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE tickets ADD INDEX idx_ticket_event_created (event_id, created_at)',
        'SELECT 1'
    )
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'tickets'
      AND index_name = 'idx_ticket_event_created'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- auth_tokens: Bearer-token validation on every authenticated mobile call.
SET @sql := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE auth_tokens ADD INDEX idx_token_lookup (token, type, expires_at)',
        'SELECT 1'
    )
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'auth_tokens'
      AND index_name = 'idx_token_lookup'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
