# ProxLock Backend
![Dynamic JSON Badge](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.proxlock.dev%2Fversion.json&query=%24.commit_hash&label=Running%20Commit:)

💧 A Vapor Swift backend for ProxLock, providing API proxy functionality with authentication, device validation, and usage tracking.

## Overview

This is the backend service for ProxLock, built with the [Vapor](https://vapor.codes) web framework. It provides a robust API proxy solution with features including:

- User authentication via Clerk
- API key management
- Device validation using Apple DeviceCheck
- Project and usage tracking
- Request proxying with rate limiting

## Prerequisites

Before you begin, ensure you have the following installed:

- **Swift 6.1+** - [Download Swift](https://www.swift.org/download/)
- **PostgreSQL 16+** - [Download PostgreSQL](https://www.postgresql.org/download/)
- **macOS 13+** (for local development)
- **Docker** (optional, for containerized development)

## Setup Instructions

### Local Development

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd backend
   ```

2. **Install dependencies**
   ```bash
   swift package resolve
   ```

3. **Set up PostgreSQL database**
   
   Create a PostgreSQL database for the application:
   ```bash
   createdb proxlock_dev
   ```

4. **Configure environment variables**
   
   Create a `.env` file in the root directory with the following variables:
   ```env
   DATABASE_HOST=localhost
   DATABASE_PORT=5432
   DATABASE_NAME=proxlock_dev
   DATABASE_USERNAME=your_postgres_username
   DATABASE_PASSWORD=your_postgres_password
   CLERK_WEBHOOK_SECRET=your_clerk_webhook_secret
   ```

5. **Run database migrations**
   
   The application will automatically run migrations on startup, or you can run them manually:
   ```bash
   swift run ProxLock migrate
   ```

6. **Start the server**
   ```bash
   swift run
   ```

   The server will start on `http://localhost:8080` by default.

### Docker Development

1. **Set up environment variables**
   
   Create a `.env` file or export the following environment variables:
   ```bash
   export DATABASE_NAME=proxlock
   export DATABASE_USERNAME=vapor
   export DATABASE_PASSWORD=password
   export CLERK_WEBHOOK_SECRET=your_clerk_webhook_secret
   ```

2. **Build and start services**
   ```bash
   docker compose build
   docker compose up
   ```

3. **Access the application**
   
   The API will be available at `http://localhost:8080`

## Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `DATABASE_HOST` | PostgreSQL hostname | No | `localhost` |
| `DATABASE_PORT` | PostgreSQL port | No | `5432` |
| `DATABASE_NAME` | Database name | Yes | - |
| `DATABASE_USERNAME` | Database username | Yes | - |
| `DATABASE_PASSWORD` | Database password | Yes | - |
| `CLERK_WEBHOOK_SECRET` | Clerk webhook secret for authentication | Yes | - |
| `CLERK_ADMIN_IDS` | The Clerk User IDs denoting administrators | no | - |

## Building and Running

### Build the project
```bash
swift build
```

### Run the application
```bash
swift run
```

### Run tests
```bash
swift test
```

### Run migrations manually
```bash
swift run ProxLock migrate
```

### Revert migrations
```bash
swift run ProxLock migrate --revert
```

## Project Structure

```
backend/
├── Sources/
│   └── ProxLock/
│       ├── Controllers/      # Request handlers
│       ├── DTOs/             # Data transfer objects
│       ├── Middleware/       # Custom middleware
│       ├── Migrations/       # Database migrations
│       ├── Models/           # Database models
│       ├── Webhooks/         # Webhook handlers
│       ├── configure.swift   # Application configuration
│       ├── entrypoint.swift  # Application entry point
│       └── routes.swift      # Route definitions
├── Tests/                    # Test files
├── Dockerfile               # Docker build configuration
├── docker-compose.yml       # Docker Compose configuration
└── Package.swift            # Swift package dependencies
```

## Contributing

We welcome contributions to ProxLock! Here's how you can help:

### Getting Started

1. **Fork the repository** and clone your fork
2. **Create a new branch** for your feature or bug fix:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

3. **Make your changes** following these guidelines:
   - Follow Swift style conventions
   - Write clear, descriptive commit messages
   - Add comments for complex logic
   - Ensure your code compiles without warnings

4. **Test your changes**
   - Run the test suite: `swift test`
   - Test manually if applicable
   - Ensure migrations work correctly if you've modified the database schema

5. **Submit a pull request**
   - Push your branch to your fork
   - Create a pull request with a clear description of your changes
   - Reference any related issues

### Code Style Guidelines

- Use Swift 6.1+ features and best practices
- Follow Vapor conventions for route and controller structure
- Keep controllers focused and single-responsibility
- Use DTOs for request/response data
- Add appropriate error handling
- Document public APIs and complex logic

### Database Changes

If you're modifying the database schema:

1. Create a new migration in the respective model's file within `Sources/ProxLock/Migrations/`
2. Follow the existing migration patterns
3. Test migrations both forward and backward
4. Update model files if needed

### Testing

- Write tests for new features when possible
- Ensure existing tests pass
- Test edge cases and error conditions

### Questions?

If you have questions or need help, please:
- Open an issue for bugs or feature requests
- Check existing issues and discussions
- Review the [Vapor documentation](https://docs.vapor.codes)

## Resources

- [Vapor Website](https://vapor.codes)
- [Vapor Documentation](https://docs.vapor.codes)
- [Vapor GitHub](https://github.com/vapor)
- [Vapor Community](https://github.com/vapor-community)
- [Swift Documentation](https://www.swift.org/documentation/)

## License

See the [License](License) file for details.
