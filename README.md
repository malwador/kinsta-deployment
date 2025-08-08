# Kinsta WordPress sFTP Deployment Action

A GitHub Action for efficiently deploying WordPress websites to Kinsta hosting via sFTP. This action intelligently transfers only files that are newer or different in size, making deployments faster and more efficient.

## ✨ Features

- **Efficient File Synchronization**: Only transfers files with newer timestamps or different sizes using rsync
- **Secure SSH Connection**: Uses SSH for secure file transfer and command execution
- **Selective Deployment**: Configurable file exclusion patterns
- **Detailed Logging**: Comprehensive deployment statistics and verbose output options
- **Dry Run Support**: Test deployments without actually transferring files
- **WordPress Optimized**: Designed specifically for WordPress deployment workflows
- **Parallel Transfers**: Uses multiple connections for faster uploads

## 🚀 Quick Start

### 1. Add Secrets to Your Repository

Go to your repository settings and add these secrets:

- `KINSTA_HOST_IP`: Your Kinsta sFTP host IP address (required due to Cloudflare)
- `KINSTA_USERNAME`: Your Kinsta sFTP username
- `KINSTA_PASSWORD`: Your Kinsta sFTP password
- `KINSTA_PORT`: Your Kinsta sFTP port (each site has a unique port)
- `KINSTA_TARGET_PATH`: Remote target path on Kinsta server (e.g., `/www/your-site_123/public`)

> **💡 Finding your Kinsta credentials**: Go to MyKinsta dashboard → Sites → [Your Site] → Info → SFTP/SSH to find your IP address, port, username, and path.

### 2. Create Workflow File

Create `.github/workflows/deploy-kinsta.yml`:

```yaml
name: Deploy to Kinsta

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
      
    - name: Deploy to Kinsta
      uses: malwador/kinsta-deployment@v1
      with:
        kinsta_host_ip: ${{ secrets.KINSTA_HOST_IP }}
        kinsta_username: ${{ secrets.KINSTA_USERNAME }}
        kinsta_password: ${{ secrets.KINSTA_PASSWORD }}
        kinsta_port: ${{ secrets.KINSTA_PORT }}
        target_path: ${{ secrets.KINSTA_TARGET_PATH }}
        exclude_patterns: '.git,.github,node_modules,.env,.DS_Store'
```

## 📖 Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `kinsta_host_ip` | Kinsta sFTP host IP address (due to Cloudflare) | ✅ | - |
| `kinsta_username` | Kinsta sFTP username | ✅ | - |
| `kinsta_password` | Kinsta sFTP password | ✅ | - |
| `kinsta_port` | Kinsta sFTP port (unique per site) | ✅ | - |
| `target_path` | Remote target path on Kinsta server | ✅ | - |
| `source_path` | Local source path to deploy | ❌ | `.` |
| `exclude_patterns` | Comma-separated exclusion patterns | ❌ | `.git,.github,node_modules,.env,.DS_Store,*.log` |
| `dry_run` | Perform dry run without transferring | ❌ | `false` |
| `verbose` | Enable verbose logging | ❌ | `false` |
| `skip_wp_cli` | Skip wp-cli post-deployment actions | ❌ | `false` |
| `install_kinsta_mu_plugin` | Download and install Kinsta MU Plugin | ❌ | `true` |
| `kinsta_mu_plugin_path` | Custom MU Plugin path (relative to target_path) | ❌ | `wp-content/mu-plugins` |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `files_transferred` | Number of files transferred |
| `bytes_transferred` | Total bytes transferred |
| `deployment_time` | Time taken for deployment (seconds) |

## 🔌 Kinsta MU Plugin Integration

This action automatically downloads and installs the [official Kinsta MU Plugin](https://kinsta.com/kinsta-tools/kinsta-mu-plugins.zip) to enhance your WordPress site's performance and integration with Kinsta's infrastructure.

### Features
- **Automatic Download**: Fetches the latest version directly from Kinsta
- **Custom Installation Path**: Configure for different WordPress setups (standard, Bedrock, etc.)
- **Safe Installation**: Creates directories if they don't exist
- **Clean Upload**: Excludes ZIP files and system files from upload
- **Validation**: Verifies successful installation

### Standard WordPress Installation
```yaml
- name: Deploy with Kinsta MU Plugin
  uses: malwador/kinsta-deployment@v1
  with:
    # ... other parameters ...
    install_kinsta_mu_plugin: 'true'
    kinsta_mu_plugin_path: 'wp-content/mu-plugins'  # Default path
```

### Bedrock/Trellis Installation
```yaml
- name: Deploy Bedrock with Kinsta MU Plugin
  uses: malwador/kinsta-deployment@v1
  with:
    # ... other parameters ...
    install_kinsta_mu_plugin: 'true'
    kinsta_mu_plugin_path: 'app/mu-plugins'  # Bedrock structure
```

### Disable MU Plugin Installation
```yaml
- name: Deploy without MU Plugin
  uses: malwador/kinsta-deployment@v1
  with:
    # ... other parameters ...
    install_kinsta_mu_plugin: 'false'
```

## 🔧 Advanced Usage

### WordPress with Build Process

```yaml
name: Deploy WordPress with Build

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
    
    - name: Install dependencies
      run: npm ci
      
    - name: Build assets
      run: npm run build
    
    - name: Deploy to Kinsta
      uses: malwador/kinsta-deployment@v1
      with:
        kinsta_host_ip: ${{ secrets.KINSTA_HOST_IP }}
        kinsta_username: ${{ secrets.KINSTA_USERNAME }}
        kinsta_password: ${{ secrets.KINSTA_PASSWORD }}
        kinsta_port: ${{ secrets.KINSTA_PORT }}
        target_path: ${{ secrets.KINSTA_TARGET_PATH }}
        exclude_patterns: '.git,.github,node_modules,.env,src/,webpack.config.js,package*.json'
        verbose: 'true'
        install_kinsta_mu_plugin: 'true'
```

### Staging and Production Deployments

```yaml
name: Deploy to Multiple Environments

on:
  push:
    branches: [ main, develop ]

jobs:
  deploy-staging:
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Deploy to Staging
      uses: malwador/kinsta-deployment@v1
      with:
        kinsta_host_ip: ${{ secrets.KINSTA_STAGING_HOST_IP }}
        kinsta_username: ${{ secrets.KINSTA_STAGING_USERNAME }}
        kinsta_password: ${{ secrets.KINSTA_STAGING_PASSWORD }}
        kinsta_port: ${{ secrets.KINSTA_STAGING_PORT }}
        target_path: ${{ secrets.KINSTA_STAGING_TARGET_PATH }}

  deploy-production:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Deploy to Production
      uses: malwador/kinsta-deployment@v1
      with:
        kinsta_host_ip: ${{ secrets.KINSTA_PROD_HOST_IP }}
        kinsta_username: ${{ secrets.KINSTA_PROD_USERNAME }}
        kinsta_password: ${{ secrets.KINSTA_PROD_PASSWORD }}
        kinsta_port: ${{ secrets.KINSTA_PROD_PORT }}
        target_path: ${{ secrets.KINSTA_PROD_TARGET_PATH }}
```

### Dry Run for Testing

```yaml
- name: Test Deployment (Dry Run)
  uses: malwador/kinsta-deployment@v1
  with:
    kinsta_host_ip: ${{ secrets.KINSTA_HOST_IP }}
    kinsta_username: ${{ secrets.KINSTA_USERNAME }}
    kinsta_password: ${{ secrets.KINSTA_PASSWORD }}
    kinsta_port: ${{ secrets.KINSTA_PORT }}
    target_path: ${{ secrets.KINSTA_TARGET_PATH }}
    dry_run: 'true'
    verbose: 'true'
```

## 🔒 Security Best Practices

1. **Never commit credentials**: Always use GitHub Secrets for sensitive information
2. **Use environment-specific secrets**: Separate staging and production credentials
3. **Limit file permissions**: Ensure proper file permissions on uploaded files
4. **Review exclude patterns**: Make sure sensitive files are excluded from deployment

## 🚀 Performance Tips

1. **Optimize exclude patterns**: Exclude unnecessary files to speed up transfers
2. **Use selective deployment**: Only deploy changed files using the built-in sync logic
3. **Enable parallel transfers**: The action uses multiple connections automatically
4. **Monitor transfer statistics**: Use the output values to track deployment efficiency

## 🐛 Troubleshooting

### Connection Issues

```yaml
# Add connection debugging
- name: Debug Connection
  run: |
    echo "Testing connection to ${{ secrets.KINSTA_HOST_IP }}:${{ secrets.KINSTA_PORT }}"
    nc -zv ${{ secrets.KINSTA_HOST_IP }} ${{ secrets.KINSTA_PORT }}
```

### File Permission Issues

Ensure your Kinsta user has proper permissions for the target directory. Contact Kinsta support if you encounter permission errors.

### Large File Transfers

For large WordPress sites, consider:
- Using more specific exclude patterns
- Deploying during off-peak hours
- Monitoring the `deployment_time` output

## 📋 Common Exclude Patterns

### WordPress-specific
```
.git,.github,node_modules,.env,.DS_Store,*.log,wp-config-local.php,wp-content/cache/,wp-content/uploads/cache/
```

### Development files
```
src/,webpack.config.js,package*.json,composer.json,composer.lock,.gitignore,README.md
```

### Build artifacts
```
dist/,build/,tmp/,temp/,*.map,*.scss,*.sass,*.less
```

## 🗂️ Common MU Plugin Paths

### Standard WordPress
```yaml
kinsta_mu_plugin_path: 'wp-content/mu-plugins'
```

### Bedrock Structure
```yaml
kinsta_mu_plugin_path: 'app/mu-plugins'
```

### Custom WordPress Structure
```yaml
kinsta_mu_plugin_path: 'public/wp-content/mu-plugins'
```

### Subdirectory Installation
```yaml
kinsta_mu_plugin_path: 'wordpress/wp-content/mu-plugins'
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Kinsta Documentation**: [Kinsta sFTP Guide](https://kinsta.com/help/connect-to-ssh/)
- **GitHub Actions**: [GitHub Actions Documentation](https://docs.github.com/en/actions)
- **Issues**: [Report a bug or request a feature](https://github.com/malwador/kinsta-deployment/issues)

## 🏗️ Roadmap

- [x] Kinsta MU Plugin automatic installation
- [x] Custom MU Plugin paths for Bedrock/Trellis
- [ ] WP-CLI integration for post-deployment tasks
- [ ] Database synchronization options
- [ ] Rollback functionality
- [ ] Slack/Discord notifications
- [ ] Advanced caching strategies
- [ ] MU Plugin version pinning/selection
