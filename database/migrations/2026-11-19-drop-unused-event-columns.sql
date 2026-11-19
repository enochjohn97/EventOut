-- ============================================================================
-- Drop unused event columns (2026-11-19)
--
-- Audit of clients, events, tickets and payments against api/, includes/,
-- cron/, client/, admin/, public/, server/, config/ and mobile/lib found
-- exactly three columns with no reader and no writer anywhere:
--
--   events.scheduled_notification_at
--   events.scheduling_reminder_sent
--   events.notification_sent
--
-- Scheduling is driven by events.scheduled_publish_time; reminders use
-- events.user_reminder_sent and tickets.reminder_sent
-- (cron/notify-pre-event.php). These three flags are leftovers and are not
-- part of any index, foreign key, view or trigger.
--
-- Every other column in the four tables is referenced by live code, including
-- the deprecated Paystack subaccount columns and events.priority (still read
-- by search/list queries).
--
-- Idempotent: MySQL has no DROP COLUMN IF EXISTS, so each ALTER runs only when
-- information_schema still reports the column.
--
-- Run once per environment:
--   mysql -u USER -p DB_NAME < database/migrations/2026-11-19-drop-unused-event-columns.sql
-- ============================================================================

SET @sql := (
    SELECT IF(
        COUNT(*) > 0,
        'ALTER TABLE events DROP COLUMN scheduled_notification_at',
        'SELECT 1'
    )
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'events'
      AND column_name = 'scheduled_notification_at'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
    SELECT IF(
        COUNT(*) > 0,
        'ALTER TABLE events DROP COLUMN scheduling_reminder_sent',
        'SELECT 1'
    )
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'events'
      AND column_name = 'scheduling_reminder_sent'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := (
    SELECT IF(
        COUNT(*) > 0,
        'ALTER TABLE events DROP COLUMN notification_sent',
        'SELECT 1'
    )
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'events'
      AND column_name = 'notification_sent'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Rollback (only if the old flags are needed again):
-- ALTER TABLE events
--   ADD COLUMN scheduled_notification_at DATETIME DEFAULT NULL,
--   ADD COLUMN scheduling_reminder_sent  TINYINT(1) DEFAULT 0,
--   ADD COLUMN notification_sent         TINYINT(1) DEFAULT 0;
