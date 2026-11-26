<?php
require_once __DIR__ . '/../../server/config.php';
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../config/payment.php';

$pdo = $pdo ?? getPDO();

function listingVerificationRedirect(string $result, int $eventId = 0): void
{
    $url = rtrim(SITE_URL, '/') . '/client/pages/clientDashboard.html'
        . '?listing_payment=' . rawurlencode($result);

    if ($eventId > 0) {
        $url .= '&event_id=' . $eventId;
    }

    header('Location: ' . $url, true, 302);
    exit;
}

function listingVerificationLog(string $message): void
{
    error_log('[Listing Fee Verification] ' . $message);
}

try {
    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        header('Allow: GET');
        http_response_code(405);
        echo 'Method not allowed.';
        exit;
    }

    $reference = trim((string) ($_GET['reference'] ?? ''));

    // References are generated as EVLIST_ followed by 32 hexadecimal characters.
    if (!preg_match('/^EVLIST_[a-f0-9]{32}$/', $reference)) {
        listingVerificationRedirect('invalid_reference');
    }

    $secretKey = defined('PAYSTACK_SECRET_KEY') ? trim(PAYSTACK_SECRET_KEY) : '';
    if ($secretKey === '') {
        listingVerificationLog('Platform Paystack secret key is not configured.');
        listingVerificationRedirect('verification_unavailable');
    }

    // The random payment reference is the callback credential.
    // It must identify an existing listing payment before Paystack is contacted.
    $stmt = $pdo->prepare("
        SELECT
            p.id AS payment_id,
            p.event_id,
            p.client_id,
            p.reference,
            p.amount_kobo,
            p.currency,
            p.listing_fee_amount,
            p.private_fee_amount,
            p.status AS payment_status,
            e.listing_type,
            e.capacity_tier,
            e.listing_fee_amount AS current_listing_fee,
            e.private_fee_amount AS current_private_fee
        FROM event_listing_payments p
        INNER JOIN events e
            ON e.id = p.event_id
           AND e.client_id = p.client_id
        WHERE p.reference = ?
        LIMIT 1
    ");
    $stmt->execute([$reference]);
    $payment = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$payment) {
        listingVerificationRedirect('payment_not_found');
    }

    $eventId = (int) $payment['event_id'];

    if ($payment['payment_status'] === 'paid') {
        listingVerificationRedirect('success', $eventId);
    }

    if ($payment['payment_status'] !== 'pending') {
        listingVerificationRedirect('not_pending', $eventId);
    }

    // Recalculate the expected fee from the event's current saved configuration.
    $expectedListingFee = 0;

    if ($payment['listing_type'] === 'ads_only') {
        $expectedListingFee = 500;
    } elseif ($payment['listing_type'] === 'ticketed') {
        $ticketFees = [
            '0-100' => 1000,
            '101-250' => 1500,
            '251-500' => 2000,
            '501-1000' => 2500,
            '1001-unlimited' => 3000,
        ];

        $tier = (string) ($payment['capacity_tier'] ?? '');
        if (!isset($ticketFees[$tier])) {
            listingVerificationLog('Invalid capacity tier for event ' . $eventId);
            listingVerificationRedirect('configuration_mismatch', $eventId);
        }

        $expectedListingFee = $ticketFees[$tier];
    } else {
        listingVerificationLog('Invalid listing type for event ' . $eventId);
        listingVerificationRedirect('configuration_mismatch', $eventId);
    }

    // GRANDFATHERED_EVENT_5_PAYMENT_V1
    // Preserve only Event 5's original pending NGN 500 listing payment.
    // This exception cannot be used for another event or payment reference.
    $isGrandfatheredEvent5Payment =
        $reference === 'EVLIST_611dd99fd1fdf408a713fa3d92011984' &&
        $eventId === 5 &&
        (int) $payment['client_id'] === 5 &&
        $payment['payment_status'] === 'pending' &&
        $payment['listing_type'] === 'ticketed' &&
        (string) $payment['capacity_tier'] === '0-100' &&
        (int) $payment['amount_kobo'] === 50000 &&
        (string) $payment['currency'] === 'NGN' &&
        (int) $payment['listing_fee_amount'] === 500 &&
        (int) $payment['private_fee_amount'] === 0 &&
        (int) $payment['current_listing_fee'] === 500 &&
        (int) $payment['current_private_fee'] === 0;

    if ($isGrandfatheredEvent5Payment) {
        $expectedListingFee = 500;
    }

    $expectedPrivateFee = 0;
    $expectedAmountKobo = ($expectedListingFee + $expectedPrivateFee) * 100;

    if (
        (int) $payment['amount_kobo'] !== $expectedAmountKobo ||
        (string) $payment['currency'] !== 'NGN' ||
        (int) $payment['listing_fee_amount'] !== $expectedListingFee ||
        (int) $payment['private_fee_amount'] !== $expectedPrivateFee ||
        (int) $payment['current_listing_fee'] !== $expectedListingFee ||
        (int) $payment['current_private_fee'] !== $expectedPrivateFee
    ) {
        listingVerificationLog('Stored payment or event fee mismatch for event ' . $eventId);
        listingVerificationRedirect('amount_mismatch', $eventId);
    }

    // Verify directly with Paystack. Never trust the browser redirect as proof of payment.
    $verification = paystackRequest(
        'GET',
        '/transaction/verify/' . rawurlencode($reference),
        [],
        $secretKey
    );

    $transaction = $verification['body']['data'] ?? [];

    if (!$verification['ok'] || !is_array($transaction)) {
        listingVerificationLog('Paystack verification request failed for ' . $reference);
        listingVerificationRedirect('verification_pending', $eventId);
    }

    $verifiedReference = (string) ($transaction['reference'] ?? '');
    $verifiedStatus = (string) ($transaction['status'] ?? '');
    $verifiedCurrency = (string) ($transaction['currency'] ?? '');
    $verifiedAmount = (int) ($transaction['amount'] ?? 0);
    $transactionId = isset($transaction['id']) ? (string) $transaction['id'] : '';

    if (
        $verifiedReference !== $reference ||
        $verifiedStatus !== 'success' ||
        $verifiedCurrency !== 'NGN' ||
        $verifiedAmount !== $expectedAmountKobo ||
        $transactionId === ''
    ) {
        listingVerificationLog(
            'Paystack transaction did not satisfy verification requirements for ' . $reference
        );
        listingVerificationRedirect('payment_not_confirmed', $eventId);
    }

    // Lock and re-check the payment row to make callback retries idempotent.
    $pdo->beginTransaction();

    $lock = $pdo->prepare("
        SELECT status, amount_kobo, currency, event_id, client_id
        FROM event_listing_payments
        WHERE id = ?
        FOR UPDATE
    ");
    $lock->execute([(int) $payment['payment_id']]);
    $lockedPayment = $lock->fetch(PDO::FETCH_ASSOC);

    if (!$lockedPayment) {
        $pdo->rollBack();
        listingVerificationRedirect('payment_not_found', $eventId);
    }

    if ($lockedPayment['status'] === 'paid') {
        $pdo->commit();
        listingVerificationRedirect('success', $eventId);
    }

    if (
        $lockedPayment['status'] !== 'pending' ||
        (int) $lockedPayment['amount_kobo'] !== $expectedAmountKobo ||
        (string) $lockedPayment['currency'] !== 'NGN' ||
        (int) $lockedPayment['event_id'] !== $eventId ||
        (int) $lockedPayment['client_id'] !== (int) $payment['client_id']
    ) {
        $pdo->rollBack();
        listingVerificationRedirect('payment_state_changed', $eventId);
    }

    $update = $pdo->prepare("
        UPDATE event_listing_payments
        SET
            status = 'paid',
            paystack_transaction_id = ?,
            verified_at = NOW()
        WHERE id = ?
          AND status = 'pending'
    ");
    $update->execute([
        $transactionId,
        (int) $payment['payment_id']
    ]);

    if ($update->rowCount() !== 1) {
        $pdo->rollBack();
        listingVerificationRedirect('payment_state_changed', $eventId);
    }

    $pdo->commit();

    listingVerificationRedirect('success', $eventId);

} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }

    listingVerificationLog(
        $e->getMessage() . ' in ' . $e->getFile() . ':' . $e->getLine()
    );

    listingVerificationRedirect('verification_error');
}
