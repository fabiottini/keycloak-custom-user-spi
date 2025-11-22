package com.example.customspi;

import org.keycloak.Config;
import org.keycloak.component.ComponentModel;
import org.keycloak.component.ComponentValidationException;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.provider.ProviderConfigurationBuilder;
import org.keycloak.storage.UserStorageProviderFactory;

import java.util.List;

/**
 * =====================================================
 * CUSTOM USER STORAGE PROVIDER FACTORY
 * =====================================================
 *
 * Factory class for creating CustomUserStorageProvider instances.
 * This factory is responsible for:
 *   - Registering the SPI with Keycloak via the provider ID
 *   - Defining configuration properties for database connection
 *   - Validating configuration before provider instantiation
 *   - Creating provider instances for each Keycloak session
 *
 * This class follows the Service Provider Interface (SPI) pattern
 * required by Keycloak's plugin architecture. It is registered via
 * META-INF/services/org.keycloak.storage.UserStorageProviderFactory
 *
 * Key Responsibilities:
 *   - Provider lifecycle management
 *   - Configuration schema definition
 *   - Configuration validation
 *   - Provider instance creation
 *
 * @author Custom SPI Development Team
 * @version 1.0.0
 */
public class CustomUserStorageProviderFactory implements UserStorageProviderFactory<CustomUserStorageProvider> {

    /**
     * Unique identifier for this User Storage Provider.
     * This ID is used by Keycloak to register and reference the provider.
     * It must match the configuration in the Admin Console.
     */
    public static final String PROVIDER_ID = "fabiottini-custom-user-storage";

    /**
     * Creates a new instance of the CustomUserStorageProvider.
     *
     * This method is called by Keycloak for each authentication request
     * or user operation that requires access to the custom user storage.
     *
     * @param session Keycloak session providing access to Keycloak's internal APIs
     * @param model Component configuration model containing database connection parameters
     * @return A new CustomUserStorageProvider instance configured with the provided parameters
     */
    @Override
    public CustomUserStorageProvider create(KeycloakSession session, ComponentModel model) {
        return new CustomUserStorageProvider(session, model);
    }

    /**
     * Returns the unique provider ID.
     *
     * This identifier is used throughout Keycloak to reference this specific
     * User Storage Provider implementation.
     *
     * @return The provider ID constant
     */
    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    /**
     * Provides help text displayed in the Keycloak Admin Console.
     *
     * This text appears when administrators configure the User Federation
     * component and helps them understand the purpose of this provider.
     *
     * @return Human-readable description of the provider
     */
    @Override
    public String getHelpText() {
        return "Custom User Storage Provider for PostgreSQL database with MD5 password hashing";
    }

    /**
     * Defines the configuration properties required by this provider.
     *
     * These properties are displayed in the Keycloak Admin Console
     * when configuring User Federation. Administrators must provide
     * valid values for all required properties.
     *
     * Configuration Properties:
     *   - dbUrl: JDBC connection string (e.g., jdbc:postgresql://host:port/database)
     *   - dbUser: Database authentication username
     *   - dbPassword: Database authentication password (masked in UI)
     *   - tableName: Name of the table containing user records
     *
     * @return List of configuration property definitions
     */
    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return ProviderConfigurationBuilder.create()
                // Database URL configuration
                .property()
                .name("dbUrl")
                .label("Database URL")
                .type(ProviderConfigProperty.STRING_TYPE)
                .defaultValue("jdbc:postgresql://user-db:5432/user")
                .helpText("JDBC connection URL for the PostgreSQL database")
                .add()
                // Database username configuration
                .property()
                .name("dbUser")
                .label("Database Username")
                .type(ProviderConfigProperty.STRING_TYPE)
                .defaultValue("user")
                .helpText("Username for database authentication")
                .add()
                // Database password configuration
                .property()
                .name("dbPassword")
                .label("Database Password")
                .type(ProviderConfigProperty.PASSWORD)
                .defaultValue("user_password")
                .helpText("Password for database authentication")
                .add()
                // Table name configuration
                .property()
                .name("tableName")
                .label("Table Name")
                .type(ProviderConfigProperty.STRING_TYPE)
                .defaultValue("utenti")
                .helpText("Name of the database table containing user records")
                .add()
                .build();
    }

    /**
     * Validates the configuration before allowing provider creation.
     *
     * This method is invoked by Keycloak when an administrator saves
     * the User Federation configuration. It ensures all required
     * parameters are present and meet basic validation requirements.
     *
     * Validation Rules:
     *   - Database URL must not be null or empty
     *   - Database username must not be null or empty
     *   - Database password must not be null or empty
     *
     * @param session Keycloak session
     * @param realm The realm being configured
     * @param config The component configuration to validate
     * @throws ComponentValidationException if validation fails
     */
    @Override
    public void validateConfiguration(KeycloakSession session, RealmModel realm, ComponentModel config)
            throws ComponentValidationException {

        // Validate database URL
        String dbUrl = config.getConfig().getFirst("dbUrl");
        if (dbUrl == null || dbUrl.trim().isEmpty()) {
            throw new ComponentValidationException("Database URL is required");
        }

        // Validate database username
        String dbUser = config.getConfig().getFirst("dbUser");
        if (dbUser == null || dbUser.trim().isEmpty()) {
            throw new ComponentValidationException("Database Username is required");
        }

        // Validate database password
        String dbPassword = config.getConfig().getFirst("dbPassword");
        if (dbPassword == null || dbPassword.trim().isEmpty()) {
            throw new ComponentValidationException("Database Password is required");
        }
    }

    /**
     * Initialization hook called when Keycloak starts up.
     *
     * This method can be used to perform one-time initialization
     * tasks, such as loading global configuration or establishing
     * connection pools. Currently not used.
     *
     * @param config Global Keycloak configuration scope
     */
    @Override
    public void init(Config.Scope config) {
        // No initialization required for this implementation
    }

    /**
     * Post-initialization hook called after Keycloak's session factory is created.
     *
     * This method can be used to perform initialization that requires
     * access to Keycloak's session factory. Currently not used.
     *
     * @param factory Keycloak session factory
     */
    @Override
    public void postInit(org.keycloak.models.KeycloakSessionFactory factory) {
        // No post-initialization required for this implementation
    }

    /**
     * Cleanup hook called when Keycloak shuts down or the provider is removed.
     *
     * This method should release any resources held by the factory,
     * such as connection pools or cache structures. Currently not used.
     */
    @Override
    public void close() {
        // No cleanup required for this implementation
    }
}
