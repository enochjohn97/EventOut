<?php

/**
 * Event Form Options API
 *
 * Public, read-only source of truth for the create-event form so the mobile
 * organizer portal renders the exact same categories and states as the web
 * app (public/js/utils.js → EVENT_CATEGORIES / NIGERIAN_STATES).
 *
 * GET /api/events/form-options
 *   { success, categories: [...], states: [...], ticket_tiers: [...] }
 */

ob_start();

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    ob_end_clean();
    http_response_code(204);
    exit;
}

// Keep in sync with window.EVENT_CATEGORIES in public/js/utils.js.
$categories = [
    'Conference',
    'Workshop',
    'Seminar',
    'Entertainment',
    'Sport & Fitness',
    'Exhibition',
    'Networking',
    'Festival',
    'Concert',
    'Business',
    'Education',
    'Social',
    'Personal',
    'Community',
    'Religion',
    'Cultural',
    'Technology',
    'Art',
    'Health',
    'Food',
    'Agriculture',
    'Tourism',
    'Fashion',
    'Real Estate',
    'Awards',
    'Charity',
    'Finance',
    'Gaming',
    'Political',
    'Creative',
    'Entrepreneurship & Innovation',
    'Other',
];

// Keep in sync with NIGERIAN_STATES in public/js/utils.js.
$states = [
    'Abia',
    'Adamawa',
    'Akwa Ibom',
    'Anambra',
    'Bauchi',
    'Bayelsa',
    'Benue',
    'Borno',
    'Cross River',
    'Delta',
    'Ebonyi',
    'Edo',
    'Ekiti',
    'Enugu',
    'Gombe',
    'Imo',
    'Jigawa',
    'Kaduna',
    'Kano',
    'Katsina',
    'Kebbi',
    'Kogi',
    'Kwara',
    'Lagos',
    'Nasarawa',
    'Niger',
    'Ogun',
    'Ondo',
    'Osun',
    'Oyo',
    'Plateau',
    'Rivers',
    'Sokoto',
    'Taraba',
    'Yobe',
    'Zamfara',
    'FCT',
];

ob_end_clean();

echo json_encode([
    'success' => true,
    'categories' => $categories,
    'states' => $states,
    'ticket_tiers' => ['regular', 'vip', 'premium'],
]);
