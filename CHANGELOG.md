# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-12

### Added

#### Core Features
- Multi-provider object storage support (S3, Azure Blob Storage, GCS, Local, Memory)
- Unified API across all storage providers
- Rustler NIFs for high-performance operations
- **Precompiled NIFs for 8 mainstream platforms** (macOS, Linux GNU/musl, Windows) - no Rust toolchain required
- Comprehensive error handling with descriptive error types

#### Advanced Operations
- Compare-And-Swap (CAS) operations with ETags
- Conditional operations (If-Match, If-None-Match, If-Modified-Since)
- Create-only writes for distributed locking
- Atomic copy operations (`copy_if_not_exists`, `rename_if_not_exists`)
- Rich metadata and attributes support (Content-Type, Cache-Control, tags)

#### Streaming
- Streaming downloads for large files
- Streaming uploads with multipart support
- Streaming list operations with automatic pagination
- Memory-efficient processing of large datasets

#### Bulk Operations
- Delete many objects with automatic batching
- Get multiple byte ranges in a single request
- Efficient list operations with delimiter support

#### Error Handling
- Comprehensive error module (`ObjectStoreX.Error`)
- Retryable error detection
- Error formatting utilities
- Error context support

#### Documentation
- Complete API documentation with ExDoc
- Getting Started guide
- Configuration guide for all providers
- Streaming guide for large file handling
- Distributed Systems guide (locks, CAS, caching)
- Error Handling guide with retry strategies
- Contributing guide
- README with examples and provider support matrix

#### Testing
- Unit tests for all core functionality
- Integration tests for cloud providers
- Example implementations (distributed locks, optimistic counters, HTTP cache)
- Quality assurance script (mix test, credo, dialyzer, format)

### Provider-Specific Features

#### AWS S3
- S3-compatible service support (MinIO, Cloudflare R2, DigitalOcean Spaces)
- IAM role credential support
- Version support for CAS operations
- Object tagging support
- Multipart uploads

#### Azure Blob Storage
- Managed identity support
- Connection string authentication
- SAS token support
- Atomic copy operations
- ETag-based conditional operations

#### Google Cloud Storage
- Application Default Credentials support
- Service account key authentication
- Atomic copy operations
- Object tagging support
- Version support

#### Local Filesystem
- Automatic directory creation
- Atomic operations via filesystem primitives
- ETag simulation for consistency

#### In-Memory
- Perfect for testing
- Full feature support
- Fast operations

### Quality & Performance
- Test coverage >80%
- Zero Dialyzer warnings
- Zero Credo warnings (strict mode)
- Comprehensive type specifications
- Optimized Rust NIFs with async I/O
- Efficient memory usage for streaming operations

### Deployment & Distribution
- Automated CI/CD pipeline for precompiled NIFs (GitHub Actions)
- Precompiled binaries for 8 platforms:
  - macOS: aarch64-apple-darwin, x86_64-apple-darwin
  - Linux GNU: aarch64-unknown-linux-gnu, x86_64-unknown-linux-gnu
  - Linux musl: aarch64-unknown-linux-musl, x86_64-unknown-linux-musl
  - Windows: x86_64-pc-windows-msvc, x86_64-pc-windows-gnu
- Build attestation and artifact signing for security
- Automatic GitHub Releases publishing on version tags
- Checksum verification for downloaded binaries
- Fallback to source compilation for unsupported platforms

## [Unreleased]

### Planned Features
- Telemetry integration for observability
- Metrics and instrumentation
- Advanced retry strategies (circuit breaker, rate limiting)
- Object versioning support across all providers
- Server-side encryption configuration
- Presigned URL generation
- Object lifecycle management
- Additional providers (Wasabi, Backblaze B2)

---

## Release Process

1. Update version in `mix.exs`
2. Update CHANGELOG.md with changes
3. Commit: `git commit -m "Release v0.x.y"`
4. Tag: `git tag v0.x.y`
5. Push: `git push && git push --tags`
6. Wait for GitHub Actions to build precompiled NIFs
7. Generate checksums: `mix gen.checksum`
8. Commit checksum file: `git commit -am "Add checksums for v0.x.y"`
9. Publish to Hex.pm: `mix hex.publish`
10. Create GitHub release with release notes

## Links

- [Hex.pm](https://hex.pm/packages/objectstorex)
- [Documentation](https://hexdocs.pm/objectstorex)
- [GitHub](https://github.com/yourorg/objectstorex)
- [Issues](https://github.com/yourorg/objectstorex/issues)
