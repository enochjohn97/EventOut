<?php

/**
 * Client Logout API (Bearer-token aware)
 *
 * The web portal logs out through its PHP session; the mobile app has no
 * cookie session, so its token is revoked here explicitly.
 */

header('Content-Type: application/json');
header('Cache-Control: no-store');

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../includes/middleware/auth.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

try {
    $token = getBearerToken();

    if (!empty($token)) {
        $stmt = $pdo->prepare("
            SELECT t.auth_id, a.role
            FROM auth_tokens t
            JOIN auth_accounts a ON a.id = t.auth_id
            WHERE t.token = ? AND t.type = 'access'
            LIMIT 1
        ");
        $stmt->execute([$token]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($row && strtolower((string) $row['role']) === 'client') {
            $pdo->prepare("DELETE FROM auth_tokens WHERE auth_id = ? AND token = ?")
                ->execute([$row['auth_id'], $token]);
            $pdo->prepare("UPDATE auth_accounts SET is_online = 0, last_seen = NOW() WHERE id = ?")
                ->execute([$row['auth_id']]);
            try {
                $pdo->prepare("UPDATE clients SET status = 'offline' WHERE client_auth_id = ?")
                    ->execute([$row['auth_id']]);
            } catch (Throwable $e) {
                // Presence tracking must never block logout.
            }
        }
    }

    // Always report success: the app clears its local token regardless.
    echo json_encode(['success' => true, 'message' => 'Logged out']);
} catch (Throwable $e) {
    error_log('[clients/logout] ' . $e->getMessage());
    echo json_encode(['success' => true, 'message' => 'Logged out']);
}
