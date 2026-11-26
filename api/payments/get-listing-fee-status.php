<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config/payment.php';
require_once __DIR__ . '/../../includes/middleware/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

function listingFeeStatusResponse(int $httpStatus, array $payload): void
{
    http_response_code($httpStatus);
    echo json_encode($payload);
    exit;
}

try {
    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        header('Allow: GET');
        listingFeeStatusResponse(405, [
            'success' => false,
            'message' => 'Method not allowed.',
        ]);
    }

    $clientId = (int) clientMiddleware();
    $eventId = filter_input(INPUT_GET, 'event_id', FILTER_VALIDATE_INT);

    if (!$eventId || $eventId < 1) {
        listingFeeStatusResponse(400, [
            'success' => false,
            'message' => 'A valid event_id is required.',
        ]);
    }

    $pdo = $pdo ?? getPDO();

    // Confirm ownership before looking up any payment information.
    $eventQuery = $pdo->prepare(
        'SELECT id, status FROM events WHERE id = ? AND client_id = ? LIMIT 1'
    );
    $eventQuery->execute([$eventId, $clientId]);
    $event = $eventQuery->fetch(PDO::FETCH_ASSOC);

    if (!$event) {
        listingFeeStatusResponse(404, [
            'success' => false,
            'message' => 'Event not found.',
        ]);
    }

    // Read the most recent listing-fee attempt only. This endpoint never writes.
    $paymentQuery = $pdo->prepare("
        SELECT
            id,
            reference,
            amount_kobo,
            currency,
            status AS payment_status
        FROM event_listing_payments
        WHERE event_id = ? AND client_id = ?
        ORDER BY id DESC
        LIMIT 1
    ");
    $paymentQuery->execute([$eventId, $clientId]);
    $payment = $paymentQuery->fetch(PDO::FETCH_ASSOC);

    listingFeeStatusResponse(200, [
        'success' => true,
        'event_id' => (int) $eventId,
        'event_status' => (string) $event['status'],
        'payment_status' => $payment
            ? (string) $payment['payment_status']
            : 'not_initialized',
        'amount_kobo' => $payment ? (int) $payment['amount_kobo'] : null,
        'currency' => $payment ? (string) $payment['currency'] : null,
    ]);
} catch (Throwable $e) {
    error_log('[Listing Fee Status] ' . $e->getMessage());
    listingFeeStatusResponse(500, [
        'success' => false,
        'message' => 'Unable to retrieve listing-fee payment status.',
    ]);
}
