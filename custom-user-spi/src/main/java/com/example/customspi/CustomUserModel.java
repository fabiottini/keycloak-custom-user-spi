package com.example.customspi;

import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.SubjectCredentialManager;
import org.keycloak.storage.StorageId;
import org.keycloak.storage.adapter.AbstractUserAdapter;

import java.util.List;
import java.util.Map;
import java.util.HashMap;

public class CustomUserModel extends AbstractUserAdapter {
    
    private final String id;
    private final String username;
    private final String email;
    private final String firstName;
    private final String lastName;
    private final String password;
    
    public CustomUserModel(KeycloakSession session, RealmModel realm, ComponentModel model, 
                          String id, String username, String email, String firstName, String lastName, String password) {
        super(session, realm, model);
        this.id = id;
        this.username = username;
        this.email = email;
        this.firstName = firstName;
        this.lastName = lastName;
        this.password = password;
    }
    
    @Override
    public String getId() {
        return StorageId.keycloakId(storageProviderModel, id);
    }
    
    @Override
    public String getUsername() {
        return username;
    }
    
    @Override
    public void setUsername(String username) {
        // Read-only provider
    }
    
    @Override
    public String getEmail() {
        return email;
    }
    
    @Override
    public void setEmail(String email) {
        // Read-only provider
    }
    
    @Override
    public String getFirstName() {
        return firstName;
    }
    
    @Override
    public void setFirstName(String firstName) {
        // Read-only provider
    }
    
    @Override
    public String getLastName() {
        return lastName;
    }
    
    @Override
    public void setLastName(String lastName) {
        // Read-only provider
    }
    
    @Override
    public boolean isEmailVerified() {
        return true; // Assume verified for simplicity
    }
    
    @Override
    public void setEmailVerified(boolean verified) {
        // Read-only provider
    }
    
    @Override
    public SubjectCredentialManager credentialManager() {
        return new org.keycloak.credential.UserCredentialManager(session, realm, this);
    }
    
    @Override
    public String getFirstAttribute(String name) {
        List<String> list = getAttributes().getOrDefault(name, List.of());
        return list.isEmpty() ? null : list.get(0);
    }
    
    @Override
    public Map<String, List<String>> getAttributes() {
        Map<String, List<String>> attrs = new HashMap<>(super.getAttributes());
        attrs.put("id", List.of(id));
        attrs.put("username", List.of(username));
        attrs.put("email", List.of(email != null ? email : ""));
        attrs.put("firstName", List.of(firstName != null ? firstName : ""));
        attrs.put("lastName", List.of(lastName != null ? lastName : ""));
        return attrs;
    }
    
    public String getPassword() {
        return password;
    }
    
    // Override required action methods to avoid ReadOnlyException
    @Override
    public void addRequiredAction(String action) {
        // Do nothing - we don't need to persist required actions for external users
    }
    
    @Override
    public void removeRequiredAction(String action) {
        // Do nothing - we don't need to persist required actions for external users
    }
    

} 