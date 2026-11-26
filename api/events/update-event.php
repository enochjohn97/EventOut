<?php

/**
 * Update Event API
 * Updates event details (only for draft and scheduled events)
 */

header('Content-Type: application/json');
require_once '../../config/database.php';
require_once '../../includes/middleware/auth.php';
require_once '../utils/notification-helper.php';

/**
 * Compress event image for storage
 */
function compressEventImage($filePath, $extension) {
    if (!extension_loaded('gd')) {
        return $filePath;
    }

    try {
        $maxWidth = 1200;
        $quality = 80;
        
        $image = null;
        switch ($extension) {
            case 'jpg':
            case 'jpeg':
                $image = imagecreatefromjpeg($filePath);
                break;
            case 'png':
                $image = imagecreatefrompng($filePath);
                break;
            case 'webp':
                $image = imagecreatefromwebp($filePath);
                break;
        }

        if (!$image) return $filePath;

        $width = imagesx($image);
        $height = imagesy($image);

        if ($width > $maxWidth) {
            $ratio = $maxWidth / $width;
            $newWidth = $maxWidth;
            $newHeight = (int)($height * $ratio);

            $resized = imagecreatetruecolor($newWidth, $newHeight);
            imagecopyresampled($resized, $image, 0, 0, 0, 0, $newWidth, $newHeight, $width, $height);
            $image = $resized;
        }

        $tempPath = $filePath . '.tmp';
        switch ($extension) {
            case 'jpg':
            case 'jpeg':
                imagejpeg($image, $tempPath, $quality);
                break;
            case 'png':
                imagepng($image, $tempPath, 6);
                break;
            case 'webp':
                imagewebp($image, $tempPath, $quality);
                break;
        }

        if (filesize($tempPath) < filesize($filePath)) {
            unlink($filePath);
            rename($tempPath, $filePath);
        } else {
            unlink($tempPath);
        }

        chmod($filePath, 0644);
        return $filePath;
    } catch (Exception $e) {
        return $filePath;
    }
}

$headers = getallheaders();
$headersLower = array_change_key_case($headers, CASE_LOWER);
$portal = $headersLower['x-eventra-portal'] ?? null;

if ($portal === 'client') {
    $user_id = checkAuth('client');
    $role = 'client';
} elseif ($portal === 'admin') {
    $user_id = checkAuth('admin');
    $role = 'admin';
} else {
    $role = $_SESSION['role'] ?? null;
    if ($role === 'client') {
        $user_id = checkAuth('client');
    } elseif ($role === 'admin') {
        $user_id = checkAuth('admin');
    } else {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'Unauthorized']);
        exit;
    }
}

$event_id = $_POST['event_id'] ?? null;

// Fallback to JSON body if $_POST is empty (happens with some fetch configurations)
if (!$event_id) {
    $json_input = json_decode(file_get_contents('php://input'), true);
    $event_id = $json_input['event_id'] ?? null;
}

if (!$event_id) {
    error_log("[Update Event Error] No Event ID provided in POST or JSON body. Headers: " . json_encode($headersLower));
    echo json_encode(['success' => false, 'message' => 'Event ID is required']);
    exit;
}

try {
    // EVENT_LISTING_TRANSACTION_GUARD_V4
    // Lock the event before reading or validating its listing configuration.
    $pdo->beginTransaction();
    register_shutdown_function(static function () use ($pdo) {
        if ($pdo instanceof PDO && $pdo->inTransaction()) {
            $pdo->rollBack();
        }
    });

    // Use user_id (which is client_id from checkAuth('client'))
    $real_client_id = $user_id;

    // Get current event details - Scoped to client
    $sql = "SELECT * FROM events WHERE id = ?";
    $params = [$event_id];

    if ($role !== 'admin') {
        $sql .= " AND client_id = ?";
        $params[] = $real_client_id;
    }

    $sql .= " FOR UPDATE";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $event = $stmt->fetch();

    if (!$event) {
        echo json_encode(['success' => false, 'message' => 'Event not found']);
        exit;
    }

    // Check if user owns the event or is admin
    if ($role !== 'admin' && $event['client_id'] != $real_client_id) {
        error_log("[Update Event Debug] Role: $role | Event Client ID: " . $event['client_id'] . " | User Real Client ID: " . $real_client_id);
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'You do not have permission to update this event']);
        exit;
    }

    // LOCKING: Prevent client edit if tickets sold; admins can always edit
    if ($role !== 'admin' && $event['attendee_count'] > 0) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'This event is locked because tickets have already been sold. Please contact support for critical changes.']);
        exit;
    }

    // Handle image upload if provided using standardized path
    $image_path = $event['image_path']; // Keep existing image by default
    if (isset($_FILES['event_image']) && $_FILES['event_image']['error'] === UPLOAD_ERR_OK) {
        if (!defined('EVENT_IMAGE_MAX_BYTES')) {
            define('EVENT_IMAGE_MAX_BYTES', 10 * 1024 * 1024);
        }
        if ($_FILES['event_image']['size'] > EVENT_IMAGE_MAX_BYTES) {
            $mb = number_format($_FILES['event_image']['size'] / (1024 * 1024), 1);
            http_response_code(413);
            echo json_encode(['success' => false, 'message' => "Image size passes the 10MB limit ({$mb}MB). Please choose a smaller image."]);
            exit;
        }
        $upload_dir = dirname(__DIR__, 2) . DIRECTORY_SEPARATOR . 'public' . DIRECTORY_SEPARATOR . 'assets' . DIRECTORY_SEPARATOR . 'event_assets' . DIRECTORY_SEPARATOR;

        if (!is_dir($upload_dir)) {
            mkdir($upload_dir, 0755, true);
        }

        $file_extension = strtolower(pathinfo($_FILES['event_image']['name'], PATHINFO_EXTENSION));
        $new_filename = uniqid('event_') . '.' . $file_extension;
        $upload_path = $upload_dir . $new_filename;

        if (move_uploaded_file($_FILES['event_image']['tmp_name'], $upload_path)) {
            // Compress image
            $upload_path = compressEventImage($upload_path, $file_extension);
            $image_path = "/public/assets/event_assets/" . basename($upload_path);

            // Delete old image if it exists
            if ($event['image_path']) {
                $old_full_path = __DIR__ . '/../../' . ltrim($event['image_path'], '/');
                if (file_exists($old_full_path) && !is_dir($old_full_path)) {
                    unlink($old_full_path);
                }
            }

            // Register the image in the media table
            try {
                $file_size = filesize($upload_path);
                $mime_type = function_exists('detectUploadMimeType')
                    ? detectUploadMimeType($upload_path, $file_extension)
                    : (function_exists('mime_content_type') ? mime_content_type($upload_path) : 'image/' . strtolower($file_extension));

                // Resolve (or create) the Event Assets folder for this client
                $ea_stmt = $pdo->prepare("SELECT id FROM media_folders WHERE client_id = ? AND name = 'Event Assets' AND is_deleted = 0 LIMIT 1");
                $ea_stmt->execute([$event['client_id']]);
                $ea_folder_id = $ea_stmt->fetchColumn();
                if (!$ea_folder_id) {
                    $pdo->prepare("INSERT INTO media_folders (client_id, name, is_deleted, created_at) VALUES (?, 'Event Assets', 0, NOW())")->execute([$event['client_id']]);
                    $ea_folder_id = $pdo->lastInsertId();
                }

                $media_stmt = $pdo->prepare("
                    INSERT INTO media (client_id, folder_id, folder_name, file_name, file_extension, file_path, file_type, file_size, mime_type)
                    VALUES (?, ?, 'Event Assets', ?, ?, ?, 'image', ?, ?)
                ");
                $media_stmt->execute([
                    $event['client_id'],
                    $ea_folder_id,
                    $_FILES['event_image']['name'],
                    $file_extension,
                    $image_path,
                    $file_size,
                    $mime_type
                ]);
            } catch (Throwable $media_err) {
                // Log media registration error but don't fail the entire update
                error_log("[Update Event Media Register Error] " . $media_err->getMessage());
            }
        } else {
            throw new Exception("Failed to move uploaded file to $upload_path. Check directory permissions.");
        }
    } elseif (isset($_FILES['event_image']) && $_FILES['event_image']['error'] !== UPLOAD_ERR_NO_FILE) {
        $error_code = $_FILES['event_image']['error'];
        $error_message = "Image upload failed (Error: $error_code)";

        if ($error_code === UPLOAD_ERR_INI_SIZE || $error_code === UPLOAD_ERR_FORM_SIZE) {
            $max_size = ini_get('upload_max_filesize');
            $error_message = "The uploaded image is too large. Your server's current limit is $max_size. Please upload a smaller image or increase 'upload_max_filesize' in your PHP configuration.";
        }

        throw new Exception($error_message);
    }
    $scheduled_publish_time = $_POST['scheduled_publish_time'] ?? null;
    $status = $_POST['status'] ?? ($event['status'] ?? 'draft');


    if ($status === 'scheduled') {
        if (empty($scheduled_publish_time)) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'Scheduled publish time is required for scheduled events.']);
            exit;
        }
        if (strtotime($scheduled_publish_time) <= time()) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'Scheduled publish time must be in the future.']);
            exit;
        }
    } elseif (empty($scheduled_publish_time)) {
        $scheduled_publish_time = null;
    }

    // EVENTOUT_MULTI_STATE_ADS_OPTIONAL_UPDATE_V1
    // Omitted fields retain their existing values. Explicit empty values are respected.
    $listing_type = trim((string)($_POST['listing_type'] ?? ($event['listing_type'] ?? 'ticketed')));

    if (!in_array($listing_type, ['ads_only', 'ticketed'], true)) {
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'Choose a valid listing option.']);
        exit;
    }

    foreach ([
        'event_name', 'event_type', 'event_date', 'event_time',
        'description', 'state', 'address', 'phone_contact_1',
        'phone_contact_2', 'visibility', 'event_visibility', 'category'
    ] as $field) {
        if (!array_key_exists($field, $_POST)) {
            $_POST[$field] = $event[$field] ?? null;
        }
    }

    $locations_was_submitted = array_key_exists('locations_json', $_POST);
    $new_locations_json = $event['locations'] ?? null;
    $clean_locations = [];

    if ($locations_was_submitted) {
        $raw_locations = trim((string)$_POST['locations_json']);

        if ($raw_locations === '') {
            $new_locations_json = null;
        } else {
            $decoded = json_decode($raw_locations, true);

            if (!is_array($decoded) || json_last_error() !== JSON_ERROR_NONE) {
                http_response_code(422);
                echo json_encode(['success' => false, 'message' => 'Invalid locations data.']);
                exit;
            }

            foreach ($decoded as $loc) {
                if (!is_array($loc)) {
                    http_response_code(422);
                    echo json_encode(['success' => false, 'message' => 'Each location must be a valid object.']);
                    exit;
                }

                $entry = [
                    'state' => trim((string)($loc['state'] ?? '')),
                    'address' => trim((string)($loc['address'] ?? '')),
                    'date' => trim((string)($loc['date'] ?? '')),
                    'time' => trim((string)($loc['time'] ?? ''))
                ];

                if ($listing_type === 'ticketed' &&
                    ($entry['state'] === '' || $entry['address'] === '' ||
                     $entry['date'] === '' || $entry['time'] === '')) {
                    http_response_code(422);
                    echo json_encode([
                        'success' => false,
                        'message' => 'Every ticketed event location must include a state, address, date and time.'
                    ]);
                    exit;
                }

                if ($entry['state'] !== '') {
                    $clean_locations[] = $entry;
                }
            }

            if ($listing_type === 'ticketed' && count($clean_locations) !== count($decoded)) {
                http_response_code(422);
                echo json_encode(['success' => false, 'message' => 'Every ticketed event location must include a state.']);
                exit;
            }

            $new_locations_json = $clean_locations
                ? json_encode($clean_locations, JSON_INVALID_UTF8_SUBSTITUTE)
                : null;

            if ($clean_locations) {
                $first = $clean_locations[0];
                $_POST['state'] = $first['state'];
                $_POST['address'] = count($clean_locations) > 1
                    ? 'Multi-state'
                    : $first['address'];

                $scheduled = array_values(array_filter(
                    $clean_locations,
                    static fn($loc) => $loc['date'] !== ''
                ));

                if ($scheduled) {
                    usort($scheduled, static function ($a, $b) {
                        return strtotime($a['date'] . ' ' . ($a['time'] ?: '00:00'))
                            <=> strtotime($b['date'] . ' ' . ($b['time'] ?: '00:00'));
                    });
                    $_POST['event_date'] = $scheduled[0]['date'];
                    if ($scheduled[0]['time'] !== '') {
                        $_POST['event_time'] = $scheduled[0]['time'];
                    }
                }
            } elseif ($listing_type === 'ticketed') {
                http_response_code(422);
                echo json_encode(['success' => false, 'message' => 'Ticketed events require at least one complete location.']);
                exit;
            }
        }
    }

    if ($listing_type === 'ticketed') {
        foreach (['event_date', 'event_time', 'state', 'address'] as $field) {
            if (trim((string)($_POST[$field] ?? '')) === '') {
                http_response_code(400);
                echo json_encode([
                    'success' => false,
                    'message' => "Ticketed events require {$field}."
                ]);
                exit;
            }
        }
    } else {
        if (array_key_exists('event_date', $_POST) && trim((string)$_POST['event_date']) === '') {
            $_POST['event_date'] = null;
        }
        if (array_key_exists('event_time', $_POST) && trim((string)$_POST['event_time']) === '') {
            $_POST['event_time'] = null;
        }
        if (array_key_exists('state', $_POST) && trim((string)$_POST['state']) === '') {
            $_POST['state'] = null;
        }
        if (!isset($_POST['address'])) {
            $_POST['address'] = '';
        }
    }

    // Event name must be text-only.
    if (!empty($_POST['event_name']) && !preg_match(
        "/^[A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{00FF}][A-Za-z\x{00C0}-\x{00D6}\x{00F8}-\x{00F6}\x{00F8}-\x{00FF}'. -]*$/u",
        trim((string)$_POST['event_name'])
    )) {
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'Event name must contain letters only (no digits or symbols).']);
        exit;
    }

    // ─────────────────────────────────────────────────────────────────────────

    // Event name must be text-only (same rule as create-event.php)
    if (!empty($_POST['event_name']) && !preg_match("/^[A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{00FF}][A-Za-z\x{00C0}-\x{00D6}\x{00D8}-\x{00F6}\x{00F8}-\x{00FF}'. -]*$/u", trim((string)$_POST['event_name']))) {
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'Event name must contain letters only (no digits or symbols).']);
        exit;
    }
    
    // Ticketed events require an address or a complete locations_json map.
    // Ads Only may omit all location fields, including an empty locations_json.
    $has_locations = !empty($_POST['locations_json']);
    if ($listing_type === 'ticketed' && !$has_locations &&
        (empty($_POST['address']) || trim((string)$_POST['address']) === '')) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => "Field 'address' is required"]);
        exit;
    }
    
    // LISTING_AND_TICKET_RULES_V2 validated above.

    $listingFees = [
        '0-100' => 1000,
        '101-250' => 1500,
        '251-500' => 2000,
        '501-1000' => 2500,
        '1001-unlimited' => 3000
    ];
    $capacityLimits = [
        '0-100' => [1, 100],
        '101-250' => [101, 250],
        '251-500' => [251, 500],
        '501-1000' => [501, 1000],
        '1001-unlimited' => [1001, PHP_INT_MAX]
    ];

    $capacity_tier = null;
    $isLegacyZeroFeeEvent4 = false;
    $listing_fee_amount = 500;
    $private_fee_amount = 0;
    $ticket_type_mode = 'none';
    $is_free = false;
    $regular_price = 0.00;
    $vip_price = 0.00;
    $premium_price = 0.00;
    $new_regular_qty = null;
    $new_vip_qty = null;
    $new_premium_qty = null;
    $new_total_tickets = null;
    $new_ticket_count = null;
    $price = 0.00;

    if ($listing_type === 'ticketed') {
        $capacity_tier = trim((string)($_POST['capacity_tier'] ?? ($event['capacity_tier'] ?? '')));

        // EVENT_4_LEGACY_ZERO_FEE_UPDATE_V1
        // Preserve only Event 4's exact existing zero-fee configuration.
        $isLegacyZeroFeeEvent4 = (
            (int)($event['id'] ?? 0) === 4 &&
            (int)($event['client_id'] ?? 0) === 5 &&
            (string)($event['listing_type'] ?? '') === 'ticketed' &&
            ($event['capacity_tier'] ?? null) === null &&
            (int)($event['listing_fee_amount'] ?? 0) === 0 &&
            (int)($event['private_fee_amount'] ?? 0) === 0 &&
            $capacity_tier === ''
        );

        if ($isLegacyZeroFeeEvent4) {
            $capacity_tier = null;
        }

        if (!$isLegacyZeroFeeEvent4 && !isset($listingFees[$capacity_tier])) {
            http_response_code(422);
            echo json_encode(['success' => false, 'message' => 'Select a valid ticket-capacity pricing bracket.']);
            exit;
        }

        $raw_mode = $_POST['ticket_type_mode'] ?? [];
        if (is_string($raw_mode)) {
            $raw_mode = array_filter(array_map('trim', explode(',', $raw_mode)));
        }
        if (!is_array($raw_mode)) {
            $raw_mode = [];
        }

        $allowed_tiers = ['regular', 'vip', 'premium'];
        $selected_tiers = array_values(array_unique(array_filter(
            array_map('strtolower', $raw_mode),
            static fn($tier) => in_array($tier, $allowed_tiers, true)
        )));

        if (empty($selected_tiers)) {
            http_response_code(422);
            echo json_encode(['success' => false, 'message' => 'Select at least one ticket type.']);
            exit;
        }

        $tier_fields = [
            'regular' => ['price' => 'regular_price', 'quantity' => 'regular_quantity'],
            'vip' => ['price' => 'vip_price', 'quantity' => 'vip_quantity'],
            'premium' => ['price' => 'premium_price', 'quantity' => 'premium_quantity']
        ];

        $total_quantity = 0;
        $active_prices = [];

        foreach ($tier_fields as $tier => $fields) {
            if (!in_array($tier, $selected_tiers, true)) {
                continue;
            }

            $raw_price = trim((string)($_POST[$fields['price']] ?? ''));
            $raw_quantity = trim((string)($_POST[$fields['quantity']] ?? ''));

            if ($raw_price === '' || !is_numeric($raw_price) || (float)$raw_price <= 0) {
                http_response_code(422);
                echo json_encode(['success' => false, 'message' => ucfirst($tier) . ' ticket price must be greater than zero.']);
                exit;
            }
            if ($raw_quantity === '' || !ctype_digit($raw_quantity) || (int)$raw_quantity <= 0) {
                http_response_code(422);
                echo json_encode(['success' => false, 'message' => ucfirst($tier) . ' ticket quantity must be a positive whole number.']);
                exit;
            }

            $tier_price = (float)$raw_price;
            $tier_quantity = (int)$raw_quantity;

            if ($tier === 'regular') {
                $regular_price = $tier_price;
                $new_regular_qty = $tier_quantity;
            } elseif ($tier === 'vip') {
                $vip_price = $tier_price;
                $new_vip_qty = $tier_quantity;
            } else {
                $premium_price = $tier_price;
                $new_premium_qty = $tier_quantity;
            }

            $active_prices[] = $tier_price;
            $total_quantity += $tier_quantity;
        }

        if ($isLegacyZeroFeeEvent4) {
            // Preserve the existing legacy inventory limit.
            $minimum_quantity = 1;
            $maximum_quantity = 100;
        } else {
            [$minimum_quantity, $maximum_quantity] = $capacityLimits[$capacity_tier];
        }
        if ($total_quantity < $minimum_quantity || $total_quantity > $maximum_quantity) {
            http_response_code(422);
            echo json_encode([
                'success' => false,
                'message' => "The selected ticket quantities must total between {$minimum_quantity} and " .
                    ($maximum_quantity === PHP_INT_MAX ? 'unlimited' : $maximum_quantity) .
                    ' for the selected capacity bracket.'
            ]);
            exit;
        }

        $ticket_type_mode = implode(',', $selected_tiers);
        $listing_fee_amount = $isLegacyZeroFeeEvent4
            ? 0
            : $listingFees[$capacity_tier];
        $price = min($active_prices);
        $new_total_tickets = $total_quantity;

        // Preserve tickets already sold when recalculating remaining inventory.
        $already_sold = (int)($event['sales_count'] ?? $event['attendee_count'] ?? 0);
        $new_ticket_count = max(0, $new_total_tickets - $already_sold);
    } else {
        // Ads Only listings never contain ticket inventory or ticket prices.
        $capacity_tier = null;
        $listing_fee_amount = 500;
        $private_fee_amount = 0;
        $ticket_type_mode = 'none';
        $price = 0.00;
        $new_total_tickets = 0;
        $new_ticket_count = 0;
    }

    // EVENT_5_GRANDFATHERED_LISTING_FEE_V1
    // Preserve Event 5's existing ₦500 fee only while its configuration is unchanged.
    if (
        (int)($event['id'] ?? 0) === 5 &&
        (int)($event['client_id'] ?? 0) === 5 &&
        (string)($event['listing_type'] ?? '') === 'ticketed' &&
        (string)($event['capacity_tier'] ?? '') === '0-100' &&
        (int)($event['listing_fee_amount'] ?? 0) === 500 &&
        (int)($event['private_fee_amount'] ?? 0) === 0 &&
        $listing_type === 'ticketed' &&
        $capacity_tier === '0-100' &&
        $private_fee_amount === 0
    ) {
        $listing_fee_amount = 500;
    }

    // A changed fee or missing matching paid payment means the event must remain a draft.
    $old_listing_fee = (int)($event['listing_fee_amount'] ?? 0);
    $old_private_fee = (int)($event['private_fee_amount'] ?? 0);
    $fee_changed = (
        $old_listing_fee !== $listing_fee_amount ||
        $old_private_fee !== $private_fee_amount ||
        (string)($event['listing_type'] ?? 'ticketed') !== $listing_type ||
        (string)($event['capacity_tier'] ?? '') !== (string)($capacity_tier ?? '')
    );

    $paidPaymentStmt = $pdo->prepare("
        SELECT id
        FROM event_listing_payments
        WHERE event_id = ?
          AND client_id = ?
          AND listing_fee_amount = ?
          AND private_fee_amount = ?
          AND amount_kobo = ?
          AND currency = 'NGN'
          AND status = 'paid'
          AND (
              event_id <> 5
              OR (
                  client_id = 5
                  AND reference = 'EVLIST_611dd99fd1fdf408a713fa3d92011984'
              )
          )
        LIMIT 1 FOR UPDATE
    ");
    $paidPaymentStmt->execute([
        $event_id,
        (int)$event['client_id'],
        $listing_fee_amount,
        $private_fee_amount,
        ($listing_fee_amount + $private_fee_amount) * 100
    ]);
    $has_matching_paid_payment = (bool)$paidPaymentStmt->fetchColumn();

    // An unchanged Event 4 legacy configuration requires no listing payment.
    $payment_required = !$has_matching_paid_payment && !$isLegacyZeroFeeEvent4;
    $reset_published_at = ($fee_changed || $payment_required) ? 1 : 0;

    if ($reset_published_at) {
        $status = 'draft';
        $scheduled_publish_time = null;
    }

    $new_metadata = [];
    if (!empty($event['metadata'])) {
        $decoded_metadata = json_decode($event['metadata'], true);
        if (is_array($decoded_metadata)) {
            $new_metadata = $decoded_metadata;
        }
    }
    $new_metadata = array_merge($new_metadata, [
        'regular_price' => $regular_price,
        'vip_price' => $vip_price,
        'premium_price' => $premium_price,
        'regular_quantity' => $new_regular_qty,
        'vip_quantity' => $new_vip_qty,
        'premium_quantity' => $new_premium_qty,
        'ticket_type_mode' => $ticket_type_mode,
        'is_free' => false
    ]);
    $metadata_json = json_encode($new_metadata, JSON_INVALID_UTF8_SUBSTITUTE);
    if ($metadata_json === false) {
        throw new RuntimeException('Could not encode event ticket metadata.');
    }

    // Admin-only fields
    $new_is_boosted = ($role === 'admin' && isset($_POST['is_boosted']))
        ? (int)$_POST['is_boosted']
        : (int)($event['is_boosted'] ?? 0);

    // Prepare metadata - store pricing fields that don't have dedicated columns
    $existing_metadata = !empty($event['metadata']) ? json_decode($event['metadata'], true) : [];
    if (!is_array($existing_metadata)) $existing_metadata = [];
    
    $new_metadata = array_merge($existing_metadata, [
        'regular_price' => $regular_price,
        'vip_price' => $vip_price,
        'premium_price' => $premium_price,
        'regular_quantity' => $new_regular_qty,
        'vip_quantity' => $new_vip_qty,
        'premium_quantity' => $new_premium_qty,
        'ticket_type_mode' => $ticket_type_mode,
        'is_free' => $is_free
    ]);
    $metadata_json = json_encode($new_metadata);

    // locations_json already parsed early as $new_locations_json

    // Begin transaction — all DB writes below must succeed together
    // Transaction already started before the authoritative event read.

    // LISTING_TYPE_ADS_ONLY_CONVERSION_GUARD_V1
    // Lock the authoritative event row before checking attendee activity.
    $lockSql = "SELECT id, listing_type FROM events WHERE id = ?";
    $lockParams = [$event_id];

    if ($role !== 'admin') {
        $lockSql .= " AND client_id = ?";
        $lockParams[] = $real_client_id;
    }

    $lockSql .= " FOR UPDATE";
    $lockStmt = $pdo->prepare($lockSql);
    $lockStmt->execute($lockParams);
    $lockedEvent = $lockStmt->fetch(PDO::FETCH_ASSOC);

    if (!$lockedEvent) {
        $pdo->rollBack();
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'message' => 'Event not found or access denied.'
        ]);
        exit;
    }

    // Only block an actual ticketed-to-Ads-Only conversion.
    if (
        ($lockedEvent['listing_type'] ?? 'ticketed') !== 'ads_only'
        && $listing_type === 'ads_only'
    ) {
        $orderCheck = $pdo->prepare("
            SELECT COUNT(*)
            FROM orders
            WHERE event_id = ?
              AND payment_status IN ('pending', 'processing', 'success')
        ");
        $orderCheck->execute([$event_id]);
        $activeOrderCount = (int)$orderCheck->fetchColumn();

        $paymentCheck = $pdo->prepare("
            SELECT COUNT(*)
            FROM payments
            WHERE event_id = ?
              AND status IN ('pending', 'paid')
        ");
        $paymentCheck->execute([$event_id]);
        $activePaymentCount = (int)$paymentCheck->fetchColumn();

        $ticketCheck = $pdo->prepare("
            SELECT COUNT(*)
            FROM tickets
            WHERE event_id = ?
        ");
        $ticketCheck->execute([$event_id]);
        $existingTicketCount = (int)$ticketCheck->fetchColumn();

        if (
            $activeOrderCount > 0
            || $activePaymentCount > 0
            || $existingTicketCount > 0
        ) {
            $pdo->rollBack();
            http_response_code(409);
            echo json_encode([
                'success' => false,
                'code' => 'ADS_ONLY_CONVERSION_BLOCKED',
                'message' => 'This event cannot be changed to Ads Only because attendee orders, payment records, or tickets already exist. Keep it as a ticketed event to protect existing purchases and tickets.'
            ]);
            exit;
        }
    }

    // Build UPDATE (priority column intentionally omitted — deprecated)
    $sql = "UPDATE events SET
            event_name = ?,
            event_type = ?,
            event_date = ?,
            event_time = ?,
            price = ?,
            status = ?,
            description = ?,
            state = ?,
            visibility = ?,
            event_visibility = ?,
            listing_type = ?,
            capacity_tier = ?,
            listing_fee_amount = ?,
            private_fee_amount = ?,
            published_at = IF(? = 1, NULL, published_at),
            address = ?,
            phone_contact_1 = ?,
            phone_contact_2 = ?,
            image_path = ?,
            category = ?,
            is_boosted = ?,
            total_tickets = COALESCE(?, total_tickets),
            ticket_count  = COALESCE(?, ticket_count),
            scheduled_publish_time = ?,
            metadata = ?,
            locations = IF(? = 1, ?, locations),
            ticket_type = ?,
            updated_at = NOW()
            WHERE id = ?";
    
    if ($role !== 'admin') {
        $sql .= " AND client_id = ?";
    }

    $stmt = $pdo->prepare($sql);
    
    $execute_params = [
        $_POST['event_name'],
        $_POST['event_type'],
        $_POST['event_date'],
        $_POST['event_time'],
        $price,
        $status,
        $_POST['description'],
        $_POST['state'],
        $_POST['visibility'] ?? 'all states',
        $_POST['event_visibility'] ?? 'public',
        $listing_type,
        $capacity_tier,
        $listing_fee_amount,
        $private_fee_amount,
        $reset_published_at,
        $_POST['address'] ?? ($new_locations_json ? 'Multi-state' : ''),
        $_POST['phone_contact_1'],
        $_POST['phone_contact_2'] ?? null,
        $image_path,
        $_POST['category'] ?? $_POST['event_type'],
        $new_is_boosted,
        $new_total_tickets,
        $new_ticket_count,
        $scheduled_publish_time,
        $metadata_json,
        $locations_was_submitted ? 1 : 0,
        $new_locations_json,   // per-state address map; explicit empty input clears it
        $ticket_type_mode,     // ticket_type column
        $event_id
    ];

    if ($role !== 'admin') {
        $execute_params[] = $real_client_id;
    }

    $stmt->execute($execute_params);

    try {
        $message = "Event '{$_POST['event_name']}' has been updated";
        $auth_id = getAuthId();
        $client_auth_id = $event['client_auth_id'] ?? null;
        if (!$client_auth_id) {
            $stmt = $pdo->prepare("SELECT client_auth_id FROM clients WHERE id = ?");
            $stmt->execute([$event['client_id']]);
            $client_auth_id = $stmt->fetchColumn();
        }

        createNotification($client_auth_id, $message, 'event_updated', $auth_id, 'client', ($role === 'admin' ? 'admin' : 'client'), ['event_id' => $event_id]);

        // Notify Admin as well
        $admin_id = getAdminUserId();
        if ($admin_id && $auth_id != $admin_id) {
            $name = $_POST['event_name'];
            $admin_message = "Event '{$name}' has been updated" . ($role === 'admin' ? " by an administrator." : " by organizer.");
            createNotification($admin_id, $admin_message, 'event_updated', $auth_id, 'admin', ($role === 'admin' ? 'admin' : 'client'), ['event_id' => $event_id]);
        }

        if ($status === 'scheduled' && $scheduled_publish_time) {
            createEventScheduledNotification($client_auth_id, $_POST['event_name'], $scheduled_publish_time, $event_id);
        }
    } catch (Throwable $notif_err) {
        error_log("[Update Event Notification Error] " . $notif_err->getMessage());
    }

    // Fetch updated event data to return to client - Scoped
    $sql = "SELECT * FROM events WHERE id = ?";
    $params = [$event_id];

    if ($role !== 'admin') {
        $sql .= " AND client_id = ?";
        $params[] = $real_client_id;
    }

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $updated_event = $stmt->fetch();

    // Commit only after all DB work succeeds — success response follows commit
    $pdo->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Event updated successfully',
        'event' => $updated_event,
        'payment_required' => $payment_required,
        'fee_changed' => $fee_changed
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log("[Update Event Global Error] " . $e->getMessage() . "\n" . $e->getTraceAsString());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Internal server error. Please try again.']);
}
