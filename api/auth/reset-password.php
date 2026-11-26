<?php

/**
 * Reset Password - Step 3: Set New Password (CLIENTS ONLY)
 * Called after OTP verification with new password.
 */

header('Content-Type: application/json');

require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../includes/helpers/validation.php';

$data = json_decode(file_get_contents("php://input"), true);

if (!is_array($data)) {
    echo json_encode(['success' => false, 'message' => 'Invalid request.']);
    exit;
}

$resetToken = trim((string) ($data['reset_token'] ?? ''));
$password = $data['password'] ?? $data['new_password'] ?? null;
$passwordConfirm = $data['password_confirm'] ?? $password;

if ($resetToken === '' || !is_string($password) || $password === '') {
    echo json_encode(['success' => false, 'message' => 'Reset token and password are required.']);
    exit;
}

if (strlen($password) < 8) {
    echo json_encode(['success' => false, 'message' => 'Password must be at least 8 characters long.']);
    exit;
}

if (!is_string($passwordConfirm) || $password !== $passwordConfirm) {
    echo json_encode(['success' => false, 'message' => 'Passwords do not match.']);
    exit;
}

try {
    $pdo = getPDO();
    $pdo->beginTransaction();

    // Lock and verify the reset token and its active client account.
    $stmt = $pdo->prepare("
        SELECT t.id AS token_id, t.auth_id
        FROM auth_tokens t
        INNER JOIN auth_accounts a ON a.id = t.auth_id
        INNER JOIN clients c ON c.client_auth_id = a.id
        WHERE t.token = ?
          AND t.type = 'reset_password'
          AND t.revoked = 0
          AND t.expires_at > NOW()
          AND a.role = 'client'
          AND a.is_active = 1
          AND a.deleted_at IS NULL
          AND c.deleted_at IS NULL
        LIMIT 1
        FOR UPDATE
    ");
    $stmt->execute([$resetToken]);
    $tokenRecord = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$tokenRecord) {
        $pdo->rollBack();
        echo json_encode(['success' => false, 'message' => 'Invalid or expired reset token.']);
        exit;
    }

    $authId = $tokenRecord['auth_id'];
    $passwordHash = password_hash($password, PASSWORD_BCRYPT);

    if ($passwordHash === false) {
        throw new RuntimeException('Password hashing failed.');
    }

    // Update only an active client account.
    $stmt = $pdo->prepare("
        UPDATE auth_accounts
        SET password = ?
        WHERE id = ?
          AND role = 'client'
          AND is_active = 1
          AND deleted_at IS NULL
    ");
    $stmt->execute([$passwordHash, $authId]);

    if ($stmt->rowCount() !== 1) {
        throw new RuntimeException('Client password update failed.');
    }

    // Invalidate every outstanding password-reset token for this client.
    $stmt = $pdo->prepare("
        UPDATE auth_tokens
        SET revoked = 1
        WHERE auth_id = ?
          AND type = 'reset_password'
          AND revoked = 0
    ");
    $stmt->execute([$authId]);

    $pdo->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Your password has been reset successfully. You can now log in.'
    ]);

} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }

    error_log("Reset password error: " . $e->getMessage());

    echo json_encode([
        'success' => false,
        'message' => 'An error occurred. Please try again later.'
    ]);
}
