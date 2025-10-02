#!/bin/bash

set -e

echo "=== ChromeDriver Installation Script ==="
echo ""

# Detect Chrome version
detect_chrome_version() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [ -f "$CHROME_PATH" ]; then
      CHROME_VERSION=$("$CHROME_PATH" --version | awk '{print $NF}')
    fi
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if command -v google-chrome &> /dev/null; then
      CHROME_VERSION=$(google-chrome --version | awk '{print $NF}')
    elif command -v chromium-browser &> /dev/null; then
      CHROME_VERSION=$(chromium-browser --version | awk '{print $NF}')
    fi
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    # Windows
    CHROME_PATH="/c/Program Files/Google/Chrome/Application/chrome.exe"
    if [ -f "$CHROME_PATH" ]; then
      CHROME_VERSION=$("$CHROME_PATH" --version | awk '{print $NF}')
    fi
  fi

  if [ -z "$CHROME_VERSION" ]; then
    echo "❌ Chrome not found. Installing latest ChromeDriver..."
    CHROME_VERSION="latest"
  else
    echo "✓ Detected Chrome version: $CHROME_VERSION"
  fi
}

# Install ChromeDriver
install_chromedriver() {
  echo ""
  echo "Installing ChromeDriver $CHROME_VERSION..."
  
  # Extract major version (e.g., 131.0.6778.204 -> 131)
  if [ "$CHROME_VERSION" != "latest" ]; then
    MAJOR_VERSION=$(echo $CHROME_VERSION | cut -d'.' -f1)
    echo "Installing ChromeDriver for Chrome $MAJOR_VERSION..."
    npx --yes @puppeteer/browsers install chromedriver@$MAJOR_VERSION
  else
    npx --yes @puppeteer/browsers install chromedriver@latest
  fi
}

# Setup symlink
setup_symlink() {
  echo ""
  echo "Setting up drivers directory..."
  
  # Create drivers directory
  mkdir -p drivers
  
  # Find ChromeDriver executable
  CHROMEDRIVER_PATH=$(find chromedriver -type f -name "chromedriver" 2>/dev/null | head -1)
  
  if [ -z "$CHROMEDRIVER_PATH" ]; then
    echo "❌ ChromeDriver executable not found!"
    exit 1
  fi
  
  echo "✓ Found ChromeDriver at: $CHROMEDRIVER_PATH"
  
  # Remove existing symlink/file if exists
  if [ -L "drivers/chromedriver" ] || [ -f "drivers/chromedriver" ]; then
    rm -f drivers/chromedriver
  fi
  
  # Create symlink (use absolute path)
  ABSOLUTE_PATH=$(cd "$(dirname "$CHROMEDRIVER_PATH")" && pwd)/$(basename "$CHROMEDRIVER_PATH")
  ln -sf "$ABSOLUTE_PATH" drivers/chromedriver
  chmod +x drivers/chromedriver
  
  echo "✓ Symlink created: drivers/chromedriver -> $CHROMEDRIVER_PATH"
}

# Verify installation
verify_installation() {
  echo ""
  echo "Verifying installation..."
  
  if drivers/chromedriver --version &> /dev/null; then
    INSTALLED_VERSION=$(drivers/chromedriver --version)
    echo "✓ ChromeDriver installed successfully!"
    echo "  $INSTALLED_VERSION"
  else
    echo "❌ ChromeDriver verification failed!"
    exit 1
  fi
}

# Main execution
main() {
  detect_chrome_version
  install_chromedriver
  setup_symlink
  verify_installation
  
  echo ""
  echo "=== Installation Complete ==="
}

main
