<?php
/**
 * Admin-only client/event flag management.
 * POST JSON: {type: client|event, id: integer, action: flag|unflag, reason?: string}
 */
header('Content-Type: application/json');

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../includes/middleware/auth.php';

checkAuth('admin');

require_once __DIR__ . '/../utils/notification-helper.php';

function flagResponse(int $status, array $data): void {
    http_response_code($status);
    echo json_encode($data);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    flagResponse(405, ['success' => false, 'message' => 'POST required.']);
}

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    flagResponse(400, ['success' => false, 'message' => 'Invalid JSON request.']);
}

$type = $input['type'] ?? '';
$id = filter_var($input['id'] ?? null, FILTER_VALIDATE_INT);
$action = $input['action'] ?? '';
$reason = trim((string)($input['reason'] ?? ''));

if (!in_array($type, ['client', 'event'], true) ||
    !$id || $id < 1 ||
    !in_array($action, ['flag', 'unflag'], true)) {
    flagResponse(400, ['success' => false, 'message' => 'Invalid type, ID or action.']);
}

if ($action === 'flag' && ($reason === '' || mb_strlen($reason) > 2000)) {
    flagResponse(422, ['success' => false, 'message' => 'A flag reason is required (maximum 2,000 characters).']);
}

$adminAuthId = (int)($_SESSION['auth_id'] ?? 0);

// Native PHP sessions may contain admin_id without auth_id.
if ($adminAuthId < 1) {
    $adminProfileId = (int)($_SESSION['admin_id'] ?? 0);

    if ($adminProfileId > 0) {
        $adminLookup = $pdo->prepare(
            "SELECT admin_auth_id FROM admins WHERE id = ? LIMIT 1"
        );
        $adminLookup->execute([$adminProfileId]);
        $adminAuthId = (int)$adminLookup->fetchColumn();
    }
}

if ($adminAuthId < 1) {
    flagResponse(403, ['success' => false, 'message' => 'Admin identity could not be verified.']);
}

$table = $type === 'client' ? 'clients' : 'events';

try {
    $pdo->beginTransaction();

    if ($type === 'client') {
        $stmt = $pdo->prepare("
            SELECT id, client_auth_id, business_name
            FROM clients
            WHERE id = ? AND deleted_at IS NULL
            FOR UPDATE
        ");
    } else {
        $stmt = $pdo->prepare("
            SELECT e.id, e.event_name, c.client_auth_id
            FROM events e
            LEFT JOIN clients c ON c.id = e.client_id
            WHERE e.id = ?
            FOR UPDATE
        ");
    }

    $stmt->execute([$id]);
    $record = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$record) {
        $pdo->rollBack();
        flagResponse(404, ['success' => false, 'message' => ucfirst($type) . ' not found.']);
    }

    if ($action === 'flag') {
        $update = $pdo->prepare("
            UPDATE `$table`
            SET is_flagged = 1,
                flag_reason = ?,
                flagged_at = NOW(),
                flagged_by_auth_id = ?
            WHERE id = ?
        ");
        $update->execute([$reason, $adminAuthId, $id]);

        $recipientAuthId = (int)($record['client_auth_id'] ?? 0);
        if ($recipientAuthId > 0) {
            $subject = $type === 'client'
                ? 'Your EventOut client account has been flagged'
                : 'Your EventOut event has been flagged';

            $itemName = $type === 'client'
                ? (string)($record['business_name'] ?? 'Your account')
                : (string)($record['event_name'] ?? 'Your event');

            $message = $subject . '. Item: ' . $itemName .
                '. Admin reason: ' . $reason .
                '. Please review and correct the issue. Contact support if you need clarification.';

            $notificationType = $type === 'client' ? 'account_warning' : 'event_warning';

            if (!createNotification(
                $recipientAuthId,
                $message,
                $notificationType,
                $adminAuthId,
                'client',
                'admin',
                [
                    'target_type' => $type,
                    'target_id' => (int)$id,
                    'reason' => $reason
                ]
            )) {
                throw new RuntimeException('Could not create the client warning notification.');
            }
        }
    } else {
        $update = $pdo->prepare("
            UPDATE `$table`
            SET is_flagged = 0,
                flag_reason = NULL,
                flagged_at = NULL,
                flagged_by_auth_id = NULL
            WHERE id = ?
        ");
        $update->execute([$id]);
    }

    $pdo->commit();

    flagResponse(200, [
        'success' => true,
        'message' => ucfirst($type) . ($action === 'flag' ? ' flagged successfully.' : ' flag removed successfully.'),
        'type' => $type,
        'id' => (int)$id,
        'is_flagged' => $action === 'flag'
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[Admin set-flag] ' . $e->getMessage());
    flagResponse(500, ['success' => false, 'message' => 'Unable to update flag. Please try again.']);
}
