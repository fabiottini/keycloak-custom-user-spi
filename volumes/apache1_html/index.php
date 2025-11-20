<?php
session_start();
require_once 'KeycloakOAuth.php';

// =====================================================
// DYNAMIC CONFIGURATION FROM ENVIRONMENT VARIABLES
// =====================================================
// Load configuration from environment variables set by Docker
$keycloak_host = $_ENV['KEYCLOAK_HOST'] ?? 'localhost';
$keycloak_port = $_ENV['KEYCLOAK_PORT'] ?? '8080';
$realm = $_ENV['REALM_NAME'] ?? 'test_env';
$client_id = $_ENV['CLIENT_ID1'] ?? 'test_client';
$client_secret = $_ENV['CLIENT_SECRET1'] ?? 'PinfiDDsLkxJRXkiOEMIv3KOGwpjF0K6';
$redirect_port = $_ENV['REDIRECT_PORT'] ?? '8083';

// Build URLs dynamically
$keycloak_url = "http://$keycloak_host:$keycloak_port";  // External URL for browser
$keycloak_internal_url = "http://keycloak:$keycloak_port";  // Internal URL for server-to-server
$redirect_uri = "http://$keycloak_host:$redirect_port/index.php";

// Check if we are in demo mode
$demo_mode = isset($_GET['demo']) && $_GET['demo'] == '1';

// If demo reset requested, clear everything
if ($demo_mode && isset($_GET['reset'])) {
    header("Location: /index.php?demo=1");
    exit;
}

$oauth = new KeycloakOAuth($keycloak_url, $realm, $client_id, $client_secret, $redirect_uri, $keycloak_internal_url, $demo_mode);

// Handle logout
if (isset($_GET['logout'])) {
    if ($demo_mode) {
        header('Location: /index.php?demo=1');
    } else {
        $logout_url = $oauth->getLogoutUrl($_SESSION['id_token'] ?? null);
        session_destroy();
        header('Location: ' . $logout_url);
    }
    exit;
}

// Variables for user data
$user_info = null;
$token_data = null;
$is_authenticated = false;

// =====================================================
// OAUTH CALLBACK HANDLING
// =====================================================
// Handle OAuth callback
if (isset($_GET['code']) && !$demo_mode) {
    try {
        $state = $_GET['state'] ?? null;
        $tokens = $oauth->handleCallback($_GET['code'], $state);
        if ($tokens) {
            $_SESSION['access_token'] = $tokens['access_token'];
            $_SESSION['id_token'] = $tokens['id_token'] ?? null;
            $_SESSION['refresh_token'] = $tokens['refresh_token'] ?? null;
            
            // Get user information
            $user_info = $oauth->getUserInfo($tokens['access_token']);
            if ($user_info) {
                $_SESSION['user_info'] = $user_info;
                $is_authenticated = true;
                
                // Decode token to show additional information
                if (isset($tokens['access_token'])) {
                    $token_parts = explode('.', $tokens['access_token']);
                    if (count($token_parts) == 3) {
                        $token_data = json_decode(base64_decode(strtr($token_parts[1], '-_', '+/')), true);
                    }
                }
            }
        }
    } catch (Exception $e) {
        $error_message = "Authentication error: " . $e->getMessage();
    }
}

// Check if user is already authenticated
if (!$is_authenticated && isset($_SESSION['access_token']) && !$demo_mode) {
    try {
        $user_info = $oauth->getUserInfo($_SESSION['access_token']);
        if ($user_info) {
            $is_authenticated = true;
            
            // Decode token
            if (isset($_SESSION['access_token'])) {
                $token_parts = explode('.', $_SESSION['access_token']);
                if (count($token_parts) == 3) {
                    $token_data = json_decode(base64_decode(strtr($token_parts[1], '-_', '+/')), true);
                }
            }
        } else {
            // Token expired, clean session
            session_destroy();
        }
    } catch (Exception $e) {
        session_destroy();
    }
}

// Demo mode
if ($demo_mode) {
    $is_authenticated = true;
    $user_info = [
        'sub' => 'demo-user-123',
        'email' => 'demo@example.com',
        'name' => 'Demo User',
        'given_name' => 'Demo',
        'family_name' => 'User',
        'preferred_username' => 'demouser'
    ];
    $token_data = [
        'sub' => 'demo-user-123',
        'iss' => $keycloak_url . '/realms/' . $realm,
        'aud' => $client_id,
        'exp' => time() + 3600,
        'iat' => time(),
        'preferred_username' => 'demouser',
        'email' => 'demo@example.com'
    ];
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Apache 1 - SSO Test with Keycloak</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #4CAF50 0%, #45a049 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
            font-weight: 300;
        }
        .header .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
            margin-top: 10px;
        }
        .content {
            padding: 40px;
        }
        .config-info {
            background: #f8f9fa;
            border-left: 4px solid #007bff;
            padding: 15px;
            margin-bottom: 30px;
            border-radius: 0 8px 8px 0;
        }
        .config-info h3 {
            margin: 0 0 10px 0;
            color: #007bff;
        }
        .config-info p {
            margin: 5px 0;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }
        .auth-section {
            text-align: center;
            margin: 30px 0;
        }
        .btn {
            display: inline-block;
            padding: 15px 30px;
            margin: 10px;
            text-decoration: none;
            border-radius: 8px;
            font-weight: bold;
            transition: all 0.3s ease;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .btn-primary {
            background: linear-gradient(135deg, #007bff 0%, #0056b3 100%);
            color: white;
        }
        .btn-success {
            background: linear-gradient(135deg, #28a745 0%, #1e7e34 100%);
            color: white;
        }
        .btn-danger {
            background: linear-gradient(135deg, #dc3545 0%, #c82333 100%);
            color: white;
        }
        .btn-warning {
            background: linear-gradient(135deg, #ffc107 0%, #e0a800 100%);
            color: #212529;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        .user-info {
            background: #e8f5e8;
            border: 1px solid #4CAF50;
            border-radius: 10px;
            padding: 25px;
            margin: 20px 0;
        }
        .user-info h3 {
            color: #2e7d32;
            margin-top: 0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
            margin-top: 15px;
        }
        .info-item {
            background: white;
            padding: 10px;
            border-radius: 5px;
            border-left: 3px solid #4CAF50;
        }
        .info-item strong {
            color: #2e7d32;
        }
        .token-section {
            background: #f1f3f4;
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
        }
        .token-section h4 {
            margin-top: 0;
            color: #5f6368;
        }
        .token-content {
            background: #1a1a1a;
            color: #00ff00;
            padding: 15px;
            border-radius: 5px;
            font-family: 'Courier New', monospace;
            font-size: 0.85em;
            overflow-x: auto;
            white-space: pre-wrap;
            word-break: break-all;
        }
        .navigation {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            border-top: 1px solid #dee2e6;
        }
        .demo-mode {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            color: #856404;
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            text-align: center;
        }
        @media (max-width: 768px) {
            .info-grid {
                grid-template-columns: 1fr;
            }
            .container {
                margin: 10px;
            }
            .content {
                padding: 20px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Apache Server 1</h1>
            <div class="subtitle">SSO Integration Test with Keycloak</div>
        </div>

        <div class="content">
            <!-- Configuration information -->
            <div class="config-info">
                <h3>🔧 Dynamic Configuration Active</h3>
                <p><strong>Keycloak URL:</strong> <?= htmlspecialchars($keycloak_url) ?></p>
                <p><strong>Realm:</strong> <?= htmlspecialchars($realm) ?></p>
                <p><strong>Client ID:</strong> <?= htmlspecialchars($client_id) ?></p>
                <p><strong>Redirect URI:</strong> <?= htmlspecialchars($redirect_uri) ?></p>
                <p><strong>Server Port:</strong> <?= htmlspecialchars($redirect_port) ?></p>
            </div>

            <?php if ($demo_mode): ?>
            <div class="demo-mode">
                <strong>🎭 DEMO MODE ACTIVE</strong><br>
                Authentication simulation for interface testing
                <a href="/index.php?demo=1&reset=1" class="btn btn-warning" style="margin-left: 15px;">Reset Demo</a>
            </div>
            <?php endif; ?>

            <?php if ($is_authenticated): ?>
                <!-- Authenticated user -->
                <div class="user-info">
                    <h3>✅ Authentication Successful!</h3>
                    <p><strong>Welcome, <?= htmlspecialchars($user_info['name'] ?? $user_info['preferred_username'] ?? 'User') ?>!</strong></p>
                    
                    <div class="info-grid">
                        <div class="info-item">
                            <strong>User ID:</strong><br>
                            <?= htmlspecialchars($user_info['sub'] ?? 'N/A') ?>
                        </div>
                        <div class="info-item">
                            <strong>Email:</strong><br>
                            <?= htmlspecialchars($user_info['email'] ?? 'N/A') ?>
                        </div>
                        <div class="info-item">
                            <strong>Username:</strong><br>
                            <?= htmlspecialchars($user_info['preferred_username'] ?? 'N/A') ?>
                        </div>
                        <div class="info-item">
                            <strong>Full Name:</strong><br>
                            <?= htmlspecialchars(($user_info['given_name'] ?? '') . ' ' . ($user_info['family_name'] ?? '')) ?>
                        </div>
                    </div>
                </div>

                <!-- Token information -->
                <?php if ($token_data): ?>
                <div class="token-section">
                    <h4>🔑 JWT Token Information</h4>
                    <div class="token-content"><?= htmlspecialchars(json_encode($token_data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)) ?></div>
                </div>
                <?php endif; ?>

                <div class="auth-section">
                    <?php if (!$demo_mode): ?>
                    <a href="?logout=1" class="btn btn-danger">🚪 Logout</a>
                    <?php endif; ?>
                </div>

            <?php else: ?>
                <!-- Unauthenticated user -->
                <div class="auth-section">
                    <h2>🔐 Access Required</h2>
                    <p>To access this service, please log in through Keycloak.</p>
                    
                    <?php if (isset($error_message)): ?>
                    <div style="background: #f8d7da; color: #721c24; padding: 15px; border-radius: 8px; margin: 20px 0;">
                        <strong>❌ Error:</strong> <?= htmlspecialchars($error_message) ?>
                    </div>
                    <?php endif; ?>

                    <a href="<?= $oauth->getAuthorizationUrl() ?>" class="btn btn-primary">
                        🔑 Login with Keycloak
                    </a>
                    
                    <br><br>
                    <a href="?demo=1" class="btn btn-warning">
                        🎭 Demo Mode
                    </a>
                </div>
            <?php endif; ?>
        </div>

        <div class="navigation">
            <h4>🌐 Test Navigation</h4>
            <a href="http://<?= $keycloak_host ?>:<?= $keycloak_port === '8082' ? '8083' : '8082' ?>" class="btn btn-success">
                🔗 Go to Server <?= $keycloak_port === '8082' ? '1 (Port 8083)' : '2 (Port 8082)' ?>
            </a>
            <a href="<?= $keycloak_url ?>/admin" class="btn btn-primary" target="_blank">
                ⚙️ Keycloak Admin Console
            </a>
        </div>
    </div>
</body>
</html> 