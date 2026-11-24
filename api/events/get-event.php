<?php

/**
 * API: Get Single Event
 * Returns event details by ID
 */

header('Content-Type: application/json');
require_once '../../config/database.php';

$event_id = $_GET['id'] ?? null;

if (!$event_id) {
    echo json_encode(['success' => false, 'message' => 'Event ID required']);
    exit;
}

try {
    $stmt = $pdo->prepare("
        SELECT e.*, c.name as client_name, c.business_name, a.email as client_email,
               c.verification_status, c.profile_pic as client_profile_pic
        FROM events e
        LEFT JOIN clients c ON e.client_id = c.id
        LEFT JOIN auth_accounts a ON c.client_auth_id = a.id
        WHERE e.id = ?
    ");
    $stmt->execute([$event_id]);
    $event = $stmt->fetch();

    if ($event) {
        // Parse metadata if it exists
        if (!empty($event['metadata'])) {
            $metadata = json_decode($event['metadata'], true);
            if (is_array($metadata)) {
                $event = array_merge($event, $metadata);
            }
        }

        // Per-tier capacity the organizer set at creation (regular/vip/premium)
        // plus the live remaining count: issued tickets (not cancelled) + the
        // pending checkouts that are still holding a reservation. The mobile
        // checkout screen renders these, so a tier never looks available while
        // its stock is actually gone.
        $tierCapacity = [];
        foreach (['regular', 'vip', 'premium'] as $tier) {
            $qty = $event[$tier . '_quantity'] ?? null;
            $tierCapacity[$tier] = ($qty === null || $qty === '') ? null : (int) $qty;
        }
        $soldByTier = [];
        $soldStmt = $pdo->prepare("
            SELECT ticket_type, COUNT(*) AS sold
            FROM tickets
            WHERE event_id = ? AND status <> 'cancelled'
            GROUP BY ticket_type
        ");
        $soldStmt->execute([$event['id']]);
        foreach ($soldStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $soldByTier[strtolower((string) $row['ticket_type'])] = (int) $row['sold'];
        }
        $reservedStmt = $pdo->prepare("
            SELECT LOWER(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.ticket_type')), 'regular')) AS tier,
                   COALESCE(SUM(CAST(JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.quantity')) AS UNSIGNED)), 0) AS reserved
            FROM orders
            WHERE event_id = ? AND payment_status = 'pending'
              AND created_at >= NOW() - INTERVAL 30 MINUTE
            GROUP BY tier
        ");
        $reservedStmt->execute([$event['id']]);
        foreach ($reservedStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $tier = strtolower((string) $row['tier']);
            $soldByTier[$tier] = ($soldByTier[$tier] ?? 0) + (int) $row['reserved'];
        }
        $tierRemaining = [];
        foreach ($tierCapacity as $tier => $capacity) {
            $tierRemaining[$tier] = $capacity === null
                ? null
                : max(0, $capacity - ($soldByTier[$tier] ?? 0));
        }
        $event['tier_capacity'] = $tierCapacity;
        $event['tier_remaining'] = $tierRemaining;

        // LISTING_PAYMENT_PREVIEW_STATUS_V1: mirror publish-event.php pricing checks.
        $fee = (int) ($event['listing_fee_amount'] ?? 0);
        $privateFee = (int) ($event['private_fee_amount'] ?? 0);
        $type = (string) ($event['listing_type'] ?? '');
        $expectedFee = null;

        if ($type === 'ads_only') {
            $expectedFee = 500;
        } elseif ($type === 'ticketed') {
            $fees = [
                '0-100' => 1000,
                '101-250' => 1500,
                '251-500' => 2000,
                '501-1000' => 2500,
                '1001-unlimited' => 3000,
            ];
            $expectedFee = $fees[(string) ($event['capacity_tier'] ?? '')] ?? null;
        }

        $grandfathered = (int) $event['id'] === 5
            && (int) $event['client_id'] === 5
            && $type === 'ticketed'
            && (string) ($event['capacity_tier'] ?? '') === '0-100'
            && $fee === 500
            && $privateFee === 0;

        $legacyZeroFee = ($fee === 0 && $privateFee === 0);
        $paymentPaid = $legacyZeroFee;

        if (!$legacyZeroFee && $expectedFee !== null
            && ($grandfathered || $fee === $expectedFee)
            && $privateFee === 0) {
            $paymentSql = "
                SELECT id
                FROM event_listing_payments
                WHERE event_id = ?
                  AND client_id = ?
                  AND listing_fee_amount = ?
                  AND private_fee_amount = 0
                  AND amount_kobo = ?
                  AND currency = 'NGN'
                  AND status = 'paid'
            ";
            $paymentParams = [
                (int) $event['id'],
                (int) $event['client_id'],
                $fee,
                ($fee + $privateFee) * 100
            ];
            if ($grandfathered) {
                $paymentSql .= " AND reference = ?";
                $paymentParams[] = 'EVLIST_611dd99fd1fdf408a713fa3d92011984';
            }
            $paymentStmt = $pdo->prepare($paymentSql);
            $paymentStmt->execute($paymentParams);
            $paymentPaid = (bool) $paymentStmt->fetchColumn();
        }

        $event['listing_payment_paid'] = $paymentPaid;

        echo json_encode(['success' => true, 'event' => $event]);
    } else {
        echo json_encode(['success' => false, 'message' => 'Event not found']);
    }
} catch (PDOException $e) {
    echo json_encode(['success' => false, 'message' => 'Database error. Please try again or contact support if it persists.']);
}
