<?php

/**
 * Client Session Refresh API
 *
 * Client access tokens are issued with a 1-hour TTL (fine for a website tab,
 * too short for a venue phone). The mobile organizer app exchanges its still
 * valid Bearer token for a fresh 30-day token here instead of forcing the user
 * through the email login code again.
 *
 * Auth: Bearer token belonging to a client account (clientMiddleware).
 * Response: { success, token, user }
 */

header('Content-Type: application/json');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../includes/middleware/auth.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed.']);
    exit;
}

try {
    // The phone has no way back in without a fresh e-mail code, so the current
    // access token may be exchanged for a new one for 30 days after it lapsed.
    // Only the newest token of an active client account qualifies (the login
    // flow keeps one active access token per account), which makes this behave
    // like a standard refresh token instead of requiring an unexpired one.
    $token = getBearerToken();
    if (empty($token)) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'Session expired. Please sign in again.']);
        exit;
    }

    $tokenStmt = $pdo->prepare("
        SELECT at.auth_id, at.expires_at
        FROM auth_tokens at
        JOIN auth_accounts aa ON at.auth_id = aa.id
        WHERE at.token = ?
          AND at.type = 'access'
          AND COALESCE(at.revoked, 0) = 0
          AND aa.role = 'client'
          AND aa.is_active = 1
          AND aa.deleted_at IS NULL
        LIMIT 1
    ");
    $tokenStmt->execute([$token]);
    $tokenRow = $tokenStmt->fetch(PDO::FETCH_ASSOC);

    if (!$tokenRow || strtotime((string) $tokenRow['expires_at']) < strtotime('-30 days')) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'Session expired. Please sign in again.']);
        exit;
    }

    $auth_id = (int) $tokenRow['auth_id'];

    $stmt = $pdo->prepare("
        SELECT c.id, c.custom_id, c.name, c.business_name, c.phone, c.profile_pic,
               c.city, c.state, c.country, c.address, c.job_title, c.company,
               c.dob, c.gender, c.verification_status, a.email
        FROM clients c
        JOIN auth_accounts a ON c.client_auth_id = a.id
        WHERE c.client_auth_id = ? AND c.deleted_at IS NULL
        LIMIT 1
    ");
    $stmt->execute([$auth_id]);
    $client = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$client) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'Client profile not found.']);
        exit;
    }

    $token = bin2hex(random_bytes(32));

    $pdo->beginTransaction();
    // One active access token per account — the same rule the login flow uses,
    // so the previous phone token cannot be replayed after a refresh.
    $pdo->prepare("DELETE FROM auth_tokens WHERE auth_id = ? AND type = 'access'")
        ->execute([$auth_id]);
    // Expiry comes from MySQL's clock so PHP/DB timezone skew cannot hand the
    // phone a token that the auth middleware already considers expired.
    $pdo->prepare("INSERT INTO auth_tokens (auth_id, token, expires_at, type) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL 30 DAY), 'access')")
        ->execute([$auth_id, $token]);
    $pdo->prepare("UPDATE auth_accounts SET last_seen = NOW(), is_online = 1 WHERE id = ?")
        ->execute([$auth_id]);
    $pdo->commit();

    $profilePic = $client['profile_pic'] ?? null;
    if (!empty($profilePic) && !preg_match('/^(https?:\/\/|data:)/i', $profilePic)) {
        $profilePic = '/' . ltrim($profilePic, '/');
    }

    echo json_encode([
        'success' => true,
        'message' => 'Session refreshed',
        'token' => $token,
        'user' => [
            'id' => (int) $auth_id,
            'profile_id' => (int) $client['id'],
            'client_id' => (int) $client['id'],
            'name' => $client['name'] ?? '',
            'business_name' => $client['business_name'] ?? '',
            'email' => $client['email'] ?? '',
            'phone' => $client['phone'] ?? null,
            'city' => $client['city'] ?? null,
            'state' => $client['state'] ?? null,
            'country' => $client['country'] ?? null,
            'address' => $client['address'] ?? null,
            'job_title' => $client['job_title'] ?? null,
            'company' => $client['company'] ?? null,
            'dob' => $client['dob'] ?? null,
            'gender' => $client['gender'] ?? null,
            'custom_id' => $client['custom_id'] ?? null,
            'verification_status' => $client['verification_status'] ?? null,
            'profile_pic' => $profilePic,
            'profile_image' => $profilePic,
            'role' => 'client',
            'token' => $token,
        ],
    ]);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('[clients/refresh-session] ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Could not refresh your session. Please sign in again.']);
}
