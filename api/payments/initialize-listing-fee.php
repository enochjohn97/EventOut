<?php
header('Content-Type: application/json');

require_once __DIR__ . '/../../server/config.php';
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/payment.php';
require_once __DIR__ . '/../../includes/middleware/auth.php';

$pdo = $pdo ?? getPDO();
$clientId = (int) clientMiddleware();

function listingFeeResponse(int $status, array $payload): void
{
    http_response_code($status);
    echo json_encode($payload);
    exit;
}

try {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        header('Allow: POST');
        listingFeeResponse(405, [
            'success' => false,
            'message' => 'Use POST to initialize a listing payment.'
        ]);
    }

    $secretKey = defined('PAYSTACK_SECRET_KEY') ? trim(PAYSTACK_SECRET_KEY) : '';
    if ($secretKey === '') {
        error_log('[Listing Fee] Platform Paystack secret key is not configured.');
        listingFeeResponse(503, [
            'success' => false,
            'message' => 'Listing payments are temporarily unavailable. Please contact support.'
        ]);
    }

    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $eventId = (int) ($body['event_id'] ?? $_POST['event_id'] ?? 0);

    if ($eventId <= 0) {
        listingFeeResponse(400, [
            'success' => false,
            'message' => 'A valid event_id is required.'
        ]);
    }

    // Resolve the event and client email using the authenticated client profile.
    $stmt = $pdo->prepare("
        SELECT
            e.id,
            e.client_id,
            e.event_name,
            e.status,
            e.listing_type,
            e.capacity_tier,
            e.listing_fee_amount,
            e.private_fee_amount,
            c.email
        FROM events e
        INNER JOIN clients c ON c.id = e.client_id
        WHERE e.id = ?
          AND e.client_id = ?
        LIMIT 1
    ");
    $stmt->execute([$eventId, $clientId]);
    $event = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$event) {
        listingFeeResponse(404, [
            'success' => false,
            'message' => 'Event not found or you do not have permission to pay for it.'
        ]);
    }

    // Event 5 has a protected legacy ₦500 pending payment.
    // Never create another reference or charge for this event.
    if ($eventId === 5 && $clientId === 5) {
        error_log(
            '[Listing Fee] Blocked duplicate initialization for protected Event 5. ' .
            'Existing reference: EVLIST_611dd99fd1fdf408a713fa3d92011984'
        );

        listingFeeResponse(409, [
            'success' => false,
            'message' => 'This event already has a protected listing payment awaiting verification. A new payment cannot be started. Please contact support.'
        ]);
    }

    if ($event['status'] !== 'draft') {
        listingFeeResponse(409, [
            'success' => false,
            'message' => 'Only draft events can proceed to listing payment.'
        ]);
    }

    // Recalculate the expected fee from the saved listing configuration.
    // Never accept the payment amount from the browser.
    $expectedFee = 0;
    $listingType = (string) $event['listing_type'];

    if ($listingType === 'ads_only') {
        $expectedFee = 500;
    } elseif ($listingType === 'ticketed') {
        $ticketFees = [
            '0-100' => 1000,
            '101-250' => 1500,
            '251-500' => 2000,
            '501-1000' => 2500,
            '1001-unlimited' => 3000,
        ];

        $tier = (string) ($event['capacity_tier'] ?? '');
        if (!isset($ticketFees[$tier])) {
            listingFeeResponse(422, [
                'success' => false,
                'message' => 'The event has an invalid ticket-capacity pricing tier. Please edit the event configuration.'
            ]);
        }

        $expectedFee = $ticketFees[$tier];
    } else {
        listingFeeResponse(422, [
            'success' => false,
            'message' => 'The event has an invalid listing option.'
        ]);
    }

    $storedListingFee = (int) $event['listing_fee_amount'];
    $privateFee = (int) ($event['private_fee_amount'] ?? 0);

    if ($storedListingFee !== $expectedFee || $privateFee !== 0) {
        error_log(
            '[Listing Fee] Configuration mismatch for event ' . $eventId .
            '; stored listing fee=' . $storedListingFee .
            '; expected listing fee=' . $expectedFee .
            '; private fee=' . $privateFee
        );

        listingFeeResponse(409, [
            'success' => false,
            'message' => 'The saved listing fee does not match the event pricing configuration. Please contact support.'
        ]);
    }

    $email = strtolower(trim((string) ($event['email'] ?? '')));
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        listingFeeResponse(422, [
            'success' => false,
            'message' => 'Your client account needs a valid email address before payment can continue.'
        ]);
    }

    $amountKobo = $expectedFee * 100;
    $reference = 'EVLIST_' . bin2hex(random_bytes(16));

    // Save the pending payment before contacting Paystack.
    $insert = $pdo->prepare("
        INSERT INTO event_listing_payments (
            event_id,
            client_id,
            reference,
            amount_kobo,
            currency,
            listing_fee_amount,
            private_fee_amount,
            status
        ) VALUES (?, ?, ?, ?, 'NGN', ?, 0, 'pending')
    ");
    $insert->execute([
        $eventId,
        $clientId,
        $reference,
        $amountKobo,
        $expectedFee
    ]);

    // Paystack returns to the dedicated verification endpoint.
    // That endpoint will verify the transaction server-side before marking it paid.
    $callbackUrl = rtrim(SITE_URL, '/') .
        '/api/payments/verify-listing-fee.php?reference=' .
        rawurlencode($reference);

    $payload = [
        'email' => $email,
        'amount' => $amountKobo,
        'currency' => 'NGN',
        'reference' => $reference,
        'callback_url' => $callbackUrl,
        'metadata' => [
            'payment_type' => 'event_listing_fee',
            'event_id' => $eventId,
            'client_id' => $clientId,
            'event_name' => (string) $event['event_name'],
            'listing_type' => $listingType,
            'listing_fee_amount' => $expectedFee,
            'private_fee_amount' => 0,
        ],
    ];

    $paystack = paystackRequest(
        'POST',
        '/transaction/initialize',
        $payload,
        $secretKey
    );

    $paystackData = $paystack['body']['data'] ?? [];
    $authorizationUrl = $paystackData['authorization_url'] ?? '';
    $accessCode = $paystackData['access_code'] ?? '';

    if (
        !$paystack['ok'] ||
        !is_string($authorizationUrl) ||
        $authorizationUrl === '' ||
        !is_string($accessCode) ||
        $accessCode === ''
    ) {
        $failureMessage = $paystack['body']['message'] ??
            $paystack['error'] ??
            'Paystack could not initialize the listing payment.';

        $fail = $pdo->prepare("
            UPDATE event_listing_payments
            SET status = 'failed'
            WHERE reference = ?
              AND client_id = ?
              AND status = 'pending'
        ");
        $fail->execute([$reference, $clientId]);

        error_log(
            '[Listing Fee] Paystack initialization failed for event ' .
            $eventId . ': ' . (string) $failureMessage
        );

        listingFeeResponse(502, [
            'success' => false,
            'message' => 'Payment could not be initialized. Please try again.'
        ]);
    }

    listingFeeResponse(200, [
        'success' => true,
        'message' => 'Listing payment initialized.',
        'event_id' => $eventId,
        'reference' => $reference,
        'amount' => $expectedFee,
        'amount_kobo' => $amountKobo,
        'currency' => 'NGN',
        'authorization_url' => $authorizationUrl,
        'access_code' => $accessCode,
    ]);

} catch (Throwable $e) {
    error_log(
        '[Listing Fee Initializer] ' . $e->getMessage() .
        ' in ' . $e->getFile() . ':' . $e->getLine()
    );

    listingFeeResponse(500, [
        'success' => false,
        'message' => 'Unable to initialize listing payment. Please try again.'
    ]);
}
