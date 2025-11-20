<?php

class KeycloakOAuth {
    private $keycloak_url;
    private $keycloak_internal_url;
    private $realm;
    private $client_id;
    private $client_secret;
    private $redirect_uri;
    private $demo_mode;
    
    public function __construct($keycloak_url, $realm, $client_id, $client_secret, $redirect_uri, $keycloak_internal_url = null, $demo_mode = false) {
        $this->keycloak_url = $keycloak_url;
        $this->keycloak_internal_url = $keycloak_internal_url ?: $keycloak_url;
        $this->realm = $realm;
        $this->client_id = $client_id;
        $this->client_secret = $client_secret;
        $this->redirect_uri = $redirect_uri;
        $this->demo_mode = $demo_mode;
    }
    
    public function getAuthorizationUrl() {
        $state = bin2hex(random_bytes(16));
        
        if ($this->demo_mode) {
            // In modalità demo, passiamo lo state come parametro URL invece di usare la sessione
            $params = [
                'client_id' => $this->client_id,
                'redirect_uri' => $this->redirect_uri . '?demo=1&oauth_state=' . $state,
                'response_type' => 'code',
                'scope' => 'openid profile email',
                'state' => $state
            ];
        } else {
            $_SESSION['oauth_state'] = $state;
            $params = [
                'client_id' => $this->client_id,
                'redirect_uri' => $this->redirect_uri,
                'response_type' => 'code',
                'scope' => 'openid profile email',
                'state' => $state
            ];
        }
        
        $auth_url = $this->keycloak_url . '/realms/' . $this->realm . '/protocol/openid-connect/auth';
        return $auth_url . '?' . http_build_query($params);
    }
    
    public function handleCallback($code, $state, $expected_state = null) {
        if ($this->demo_mode) {
            // In modalità demo, verifica lo state passato come parametro
            if (!$expected_state || $state !== $expected_state) {
                throw new Exception('Invalid state parameter in demo mode');
            }
        } else {
            // Modalità normale: verifica lo state dalla sessione
            if (!isset($_SESSION['oauth_state']) || $state !== $_SESSION['oauth_state']) {
                throw new Exception('Invalid state parameter');
            }
            unset($_SESSION['oauth_state']);
        }
        
        // Scambia il code con l'access token (usa URL interno per server-to-server)
        $token_url = $this->keycloak_internal_url . '/realms/' . $this->realm . '/protocol/openid-connect/token';
        
        $redirect_uri = $this->demo_mode ? 
            explode('?', $this->redirect_uri)[0] . '?demo=1&oauth_state=' . $expected_state :
            $this->redirect_uri;
        
        $post_data = [
            'grant_type' => 'authorization_code',
            'client_id' => $this->client_id,
            'client_secret' => $this->client_secret,
            'code' => $code,
            'redirect_uri' => $redirect_uri
        ];
        
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $token_url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($post_data));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/x-www-form-urlencoded'
        ]);
        
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($http_code !== 200) {
            throw new Exception('Failed to exchange code for token: ' . $response);
        }
        
        $token_data = json_decode($response, true);
        
        if (!$token_data || !isset($token_data['access_token'])) {
            throw new Exception('Invalid token response');
        }
        
        return $token_data;
    }
    
    public function getUserInfo($access_token) {
        $userinfo_url = $this->keycloak_internal_url . '/realms/' . $this->realm . '/protocol/openid-connect/userinfo';
        
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $userinfo_url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Authorization: Bearer ' . $access_token
        ]);
        
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($http_code !== 200) {
            throw new Exception('Failed to get user info: ' . $response);
        }
        
        return json_decode($response, true);
    }
    
    public function getLogoutUrl($id_token = null) {
        $params = [
            'client_id' => $this->client_id,
            'post_logout_redirect_uri' => $this->redirect_uri
        ];
        
        if ($id_token) {
            $params['id_token_hint'] = $id_token;
        }
        
        $logout_url = $this->keycloak_url . '/realms/' . $this->realm . '/protocol/openid-connect/logout';
        return $logout_url . '?' . http_build_query($params);
    }
} 