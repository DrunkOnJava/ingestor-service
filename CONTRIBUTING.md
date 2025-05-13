# Contributing to Ingestor System

Thank you for considering contributing to the Ingestor System! This document outlines the process for contributing to the project and the standards we follow.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please be respectful and considerate of others.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue and include:

- A clear, descriptive title
- A detailed description of the bug
- Steps to reproduce the behavior
- Expected behavior
- Current behavior
- Environment details (OS, versions, etc.)
- Any relevant logs or screenshots

### Suggesting Enhancements

If you have ideas for new features or improvements, please open an issue and include:

- A clear, descriptive title
- A detailed description of the enhancement
- The rationale for why this would be valuable
- Any relevant examples or mock-ups

### Pull Requests

1. Fork the repository
2. Create a new branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Run tests and ensure your code passes linting
5. Commit your changes with a descriptive message
6. Push to your branch (`git push origin feature/your-feature`)
7. Open a Pull Request

#### Pull Request Guidelines

- Follow the coding style and conventions used in the project
- Include tests for new functionality
- Update documentation to reflect any changes
- One pull request per feature/bugfix
- Keep pull requests focused in scope and avoid unrelated commits

## Development Setup

To set up the project for development:

1. Clone the repository
2. Run `./scripts/install_dependencies.sh` to install required dependencies
3. Run `./scripts/setup_mcp_server.sh` to set up the MCP server
4. Initialize a test database with `./src/ingestor --init-db test`

## Coding Standards

### Shell Scripts

- Use `#!/bin/bash` for shell scripts
- Include `set -eo pipefail` in all scripts
- Favor readability over brevity
- Write comments for complex operations
- Properly quote variables and check return values

### JavaScript (MCP Server)

- Use modern ES6+ syntax
- Include JSDoc comments for functions
- Handle errors appropriately
- Use meaningful variable and function names
- Include proper error logging

### SQL 

- Use uppercase for SQL keywords
- Format queries for readability
- Use appropriate indexes for performance
- Document complex queries with comments

## Testing

Before submitting a pull request, make sure:

1. All scripts pass syntax checking (`bash -n script.sh`)
2. Shell scripts pass ShellCheck
3. JavaScript code is validated
4. Database schema can be created successfully

## Versioning

We use [Semantic Versioning](https://semver.org/). When creating a release:

- MAJOR version for incompatible API changes
- MINOR version for backwards-compatible functionality additions
- PATCH version for backwards-compatible bug fixes

## License

By contributing to this project, you agree that your contributions will be licensed under the project's license.