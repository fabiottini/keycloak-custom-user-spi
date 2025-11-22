package com.example.customspi;

import org.keycloak.component.ComponentModel;
import org.keycloak.credential.CredentialInput;
import org.keycloak.credential.CredentialInputValidator;
import org.keycloak.models.GroupModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.credential.PasswordCredentialModel;
import org.keycloak.storage.StorageId;
import org.keycloak.storage.UserStorageProvider;
import org.keycloak.storage.user.UserLookupProvider;
import org.keycloak.storage.user.UserQueryProvider;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Map;
import java.util.stream.Stream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

import org.jboss.logging.Logger;

public class CustomUserStorageProvider implements 
      UserStorageProvider, UserLookupProvider, UserQueryProvider, CredentialInputValidator {
    
    private static final Logger logger = Logger.getLogger(CustomUserStorageProvider.class);
    
    private final KeycloakSession session;
    private final ComponentModel model;
    
    public CustomUserStorageProvider(KeycloakSession session, ComponentModel model) {
        this.session = session;
        this.model = model;
    }
    
    // Connection helper
    private Connection getConnection() throws SQLException {
        String dbUrl = model.getConfig().getFirst("dbUrl");
        String dbUser = model.getConfig().getFirst("dbUser");
        String dbPassword = model.getConfig().getFirst("dbPassword");
        
        if (dbUrl == null || dbUser == null || dbPassword == null) {
            throw new SQLException("Database connection parameters not configured. " +
                "Please configure dbUrl, dbUser, and dbPassword in Keycloak Admin Console > User Federation.");
        }
        
        return DriverManager.getConnection(dbUrl, dbUser, dbPassword);
    }
    
    // Helper to get the configured table name
    private String getTableName() {
        String tableName = model.getConfig().getFirst("tableName");
        return (tableName != null && !tableName.trim().isEmpty()) ? tableName : "utenti";
    }
    
    @Override
    public UserModel getUserById(RealmModel realm, String id) {
        logger.infof("Getting user by ID: %s", id);
        StorageId storageId = new StorageId(id);
        String externalId = storageId.getExternalId();
        
        try (Connection connection = getConnection()) {
            //TODO: generalize
            String sql = "SELECT id, nome, cognome, mail, username, password FROM " + getTableName() + " WHERE id = ?";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setInt(1, Integer.parseInt(externalId));
                try (ResultSet resultSet = statement.executeQuery()) {
                    if (resultSet.next()) {
                        UserModel user = mapUser(resultSet, realm);
                        logger.infof("User found by ID: %s", user.getUsername());
                        return user;
                    } else {
                        logger.infof("User not found by ID: %s", externalId);
                    }
                }
            }
        } catch (SQLException | NumberFormatException e) {
            logger.errorf("Error getting user by ID: %s", e.getMessage());
        }
        
        return null;
    }
    
    @Override
    public UserModel getUserByUsername(RealmModel realm, String username) {
        logger.infof("=== LOOKUP USER BY USERNAME: %s ===", username);
        
        try (Connection connection = getConnection()) {
            //TODO: generalize
            String sql = "SELECT id, nome, cognome, mail, username, password FROM " + getTableName() + " WHERE username = ?";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setString(1, username);
                try (ResultSet resultSet = statement.executeQuery()) {
                    if (resultSet.next()) {
                        UserModel user = mapUser(resultSet, realm);
                        logger.infof("User found: %s", user.getUsername());
                        return user;
                    } else {
                        logger.infof("User not found: %s", username);
                    }
                }
            }
        } catch (SQLException e) {
            logger.errorf("Error getting user by username: %s", e.getMessage());
        }
        
        return null;
    }
    
    @Override
    public UserModel getUserByEmail(RealmModel realm, String email) {
        logger.infof("Getting user by email: %s", email);
        
        try (Connection connection = getConnection()) {
            //TODO: generalize
            String sql = "SELECT id, nome, cognome, mail, username, password FROM " + getTableName() + " WHERE mail = ?";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setString(1, email);
                try (ResultSet resultSet = statement.executeQuery()) {
                    if (resultSet.next()) {
                        return mapUser(resultSet, realm);
                    }
                }
            }
        } catch (SQLException e) {
            logger.errorf("Error getting user by email: %s", e.getMessage());
        }
        
        return null;
    }
    
    @Override
    public int getUsersCount(RealmModel realm) {
        try (Connection connection = getConnection()) {
            String sql = "SELECT COUNT(*) FROM " + getTableName();
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                try (ResultSet resultSet = statement.executeQuery()) {
                    if (resultSet.next()) {
                        return resultSet.getInt(1);
                    }
                }
            }
        } catch (SQLException e) {
            logger.errorf("Error counting users: %s", e.getMessage());
        }
        return 0;
    }
    
    public Stream<UserModel> getUsersStream(RealmModel realm, Integer firstResult, Integer maxResults) {
        try (Connection connection = getConnection()) {
            //TODO: generalize
            String sql = "SELECT id, nome, cognome, mail, username, password FROM " + getTableName() + " LIMIT ? OFFSET ?";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setInt(1, maxResults);
                statement.setInt(2, firstResult);
                try (ResultSet resultSet = statement.executeQuery()) {
                    return Stream.generate(() -> {
                        try {
                            if (resultSet.next()) {
                                return mapUser(resultSet, realm);
                            }
                            return null;
                        } catch (SQLException e) {
                            logger.errorf("Error reading user: %s", e.getMessage());
                            return null;
                        }
                    }).takeWhile(user -> user != null);
                }
            }
        } catch (SQLException e) {
            logger.errorf("Error getting users: %s", e.getMessage());
        }
        
        return Stream.empty();
    }
    
    @Override
    public Stream<UserModel> searchForUserStream(RealmModel realm, String search) {
        return searchForUserStream(realm, search, 0, Integer.MAX_VALUE);
    }
    
    @Override
    public Stream<UserModel> searchForUserStream(RealmModel realm, String search, Integer firstResult, Integer maxResults) {
        if (search == null || search.trim().isEmpty()) {
            return getUsersStream(realm, firstResult, maxResults);
        }
        
        String searchPattern = "%" + search.toLowerCase() + "%";
        
        try (Connection connection = getConnection()) {
            //TODO: generalize
            String sql = "SELECT id, nome, cognome, mail, username, password FROM " + getTableName() + " " +
                        "WHERE LOWER(username) LIKE ? OR LOWER(nome) LIKE ? OR LOWER(cognome) LIKE ? OR LOWER(mail) LIKE ? " +
                        "LIMIT ? OFFSET ?";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setString(1, searchPattern);
                statement.setString(2, searchPattern);
                statement.setString(3, searchPattern);
                statement.setString(4, searchPattern);
                statement.setInt(5, maxResults);
                statement.setInt(6, firstResult);
                try (ResultSet resultSet = statement.executeQuery()) {
                    return Stream.generate(() -> {
                        try {
                            if (resultSet.next()) {
                                return mapUser(resultSet, realm);
                            }
                            return null;
                        } catch (SQLException e) {
                            logger.errorf("Error reading user in search: %s", e.getMessage());
                            return null;
                        }
                    }).takeWhile(user -> user != null);
                }
            }
        } catch (SQLException e) {
            logger.errorf("Error searching users: %s", e.getMessage());
        }
        
        return Stream.empty();
    }
    
    @Override
    public Stream<UserModel> searchForUserStream(RealmModel realm, Map<String, String> params) {
        return searchForUserStream(realm, params, 0, Integer.MAX_VALUE);
    }
    
    @Override
    public Stream<UserModel> searchForUserStream(RealmModel realm, Map<String, String> params, Integer firstResult, Integer maxResults) {
        return Stream.empty(); // Simplified implementation
    }
    
    @Override
    public Stream<UserModel> getGroupMembersStream(RealmModel realm, GroupModel group, Integer firstResult, Integer maxResults) {
        return Stream.empty(); // Not supported
    }
    
    @Override
    public Stream<UserModel> getGroupMembersStream(RealmModel realm, GroupModel group) {
        return Stream.empty(); // Not supported
    }
    
    @Override
    public Stream<UserModel> searchForUserByUserAttributeStream(RealmModel realm, String attrName, String attrValue) {
        return Stream.empty(); // Simplified implementation
    }
    
    // CredentialInputValidator methods
    @Override
    public boolean supportsCredentialType(String credentialType) {
        return PasswordCredentialModel.TYPE.equals(credentialType);
    }
    
    @Override
    public boolean isConfiguredFor(RealmModel realm, UserModel user, String credentialType) {
        return supportsCredentialType(credentialType);
    }
    
    @Override
    public boolean isValid(RealmModel realm, UserModel user, CredentialInput credentialInput) {
        logger.infof("=== VALIDATION START ===");
        logger.infof("Credential type: %s", credentialInput.getType());
        logger.infof("User: %s", user.getUsername());
        logger.infof("User instance type: %s", user.getClass().getSimpleName());
        
        if (!supportsCredentialType(credentialInput.getType())) {
            logger.errorf("Credential type not supported: %s", credentialInput.getType());
            return false;
        }
        
        String username = user.getUsername();
        String inputPassword = credentialInput.getChallengeResponse();
        
        logger.infof("Input password length: %d", inputPassword != null ? inputPassword.length() : 0);
        
        if (inputPassword == null || username == null) {
            logger.errorf("Username or password is null - username: %s, input password: %s", 
                         username != null, inputPassword != null);
            return false;
        }
        
        // Always fetch user from database to get the correct password hash
        String storedPassword = getPasswordFromDatabase(username);
        
        logger.infof("Stored password from DB: %s", storedPassword);
        
        if (storedPassword == null) {
            logger.errorf("No password found in database for user: %s", username);
            return false;
        }
        
        //TODO: generalize, support multiple hash types
        // Validate MD5 hash
        boolean isValid = validateMD5Password(inputPassword, storedPassword);
        logger.infof("Validation result: %s", isValid);
        logger.infof("=== VALIDATION END ===");
        return isValid;
    }
    
    private String getPasswordFromDatabase(String username) {
        try (Connection connection = getConnection()) {
            String sql = "SELECT password FROM " + getTableName() + " WHERE username = ?";
            try (PreparedStatement statement = connection.prepareStatement(sql)) {
                statement.setString(1, username);
                try (ResultSet resultSet = statement.executeQuery()) {
                    if (resultSet.next()) {
                        return resultSet.getString("password");
                    }
                }
            }
        } catch (SQLException e) {
            logger.errorf("Error getting password for user %s: %s", username, e.getMessage());
        }
        return null;
    }
    
    private boolean validateMD5Password(String inputPassword, String storedHash) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(inputPassword.getBytes());
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            String computedHash = sb.toString();
            logger.infof("Computed MD5: %s", computedHash);
            logger.infof("Stored MD5: %s", storedHash);
            boolean matches = computedHash.equals(storedHash);
            logger.infof("MD5 match: %s", matches);
            return matches;
        } catch (NoSuchAlgorithmException e) {
            logger.errorf("MD5 algorithm not available: %s", e.getMessage());
            return false;
        }
    }
    
    private UserModel mapUser(ResultSet resultSet, RealmModel realm) throws SQLException {
        //TODO: generalize, support multiple columns
        String id = resultSet.getString("id");
        String username = resultSet.getString("username");
        String email = resultSet.getString("mail");
        String firstName = resultSet.getString("nome");
        String lastName = resultSet.getString("cognome");
        String password = resultSet.getString("password");
        
        return new CustomUserModel(session, realm, model, id, username, email, firstName, lastName, password);
    }
    
    @Override
    public void close() {
        // Nothing to close
    }
}