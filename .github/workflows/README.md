# GitHub Actions CI/CD Pipeline

This directory contains GitHub Actions workflow configurations for the Ingestor System project. These workflows automate testing, linting, building, and releasing the project.

## Workflows

### 1. CI/CD Pipeline (`ci-cd.yml`)

This is the main workflow that runs on:
- Push to the `main` branch
- Any pull request to the `main` branch
- Any tag push with pattern `v*` (for releases)

The workflow consists of the following jobs:

#### Lint
- Installs ShellCheck
- Runs `./scripts/lint.sh` to check code quality of shell scripts

#### Test
- Sets up Node.js
- Installs all required dependencies (npm packages and system dependencies)
- Installs testing dependencies using `./scripts/install_test_deps.sh`
- Runs the test suite using `./scripts/run_tests.sh`

#### Build
- Sets up Node.js
- Installs npm dependencies
- Creates the environment structure
- Verifies the build can run
- Archives build artifacts for later use

#### Release (only on tag pushes)
- Triggered only when pushing tags that start with `v` (e.g., `v1.0.0`)
- Downloads build artifacts
- Creates a compressed tarball of the release
- Creates a GitHub release with the tarball attached

### 2. Code Analysis (`code-analysis.yml`)

This workflow runs advanced code analysis:
- Performs ShellCheck analysis on all shell scripts
- Runs CodeQL analysis on JavaScript code
- Scheduled to run weekly in addition to push/PR triggers

## Creating Releases

To create a new release:

1. Update the version in `package.json`
2. Commit your changes
3. Tag the commit with a version number: `git tag v1.0.0`
4. Push the tag: `git push origin v1.0.0`

The CI/CD pipeline will automatically:
- Run all tests and quality checks
- Build the project
- Create a GitHub release with release notes
- Attach a tarball of the release to the GitHub release

## Local Development

To run the same checks locally before pushing:

```bash
# Lint shell scripts
./scripts/lint.sh

# Run tests
./scripts/run_tests.sh
```