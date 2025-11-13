#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Validate required environment variables
if [ -z "$REPO_URL" ]; then
    error "REPO_URL environment variable is required!"
    exit 1
fi

log "Starting Node.js Repo Hoster"
log "Repository: $REPO_URL"
log "Branch: $BRANCH"
log "Check interval: ${CHECK_INTERVAL}s"
log "Start command: $START_COMMAND"
log "Install command: $INSTALL_COMMAND"

REPO_DIR="/app/repo"
APP_PID=""

# Function to kill the app if it's running
kill_app() {
    if [ ! -z "$APP_PID" ] && kill -0 $APP_PID 2>/dev/null; then
        log "Stopping application (PID: $APP_PID)..."
        kill $APP_PID 2>/dev/null || true
        wait $APP_PID 2>/dev/null || true
        APP_PID=""
    fi
}

# Function to start the app
start_app() {
    cd "$REPO_DIR"
    log "Starting application with: $START_COMMAND"

    # Start the app in background
    bash -c "$START_COMMAND" &
    APP_PID=$!

    log "Application started with PID: $APP_PID"
}

# Function to install dependencies
install_deps() {
    cd "$REPO_DIR"
    if [ -f "package.json" ]; then
        log "Installing dependencies with: $INSTALL_COMMAND"
        if eval "$INSTALL_COMMAND"; then
            log "Dependencies installed successfully"
        else
            error "Failed to install dependencies!"
            return 1
        fi
    else
        warn "No package.json found, skipping dependency installation"
    fi
    return 0
}

# Trap signals to ensure cleanup
trap 'log "Received signal, shutting down..."; kill_app; exit 0' SIGTERM SIGINT

# Clone or update repository
if [ -d "$REPO_DIR/.git" ]; then
    log "Repository already exists, fetching latest changes..."
    cd "$REPO_DIR"
    git fetch origin
    git reset --hard "origin/$BRANCH"
else
    log "Cloning repository..."
    git clone -b "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

# Get initial commit hash
cd "$REPO_DIR"
LAST_COMMIT=$(git rev-parse HEAD)
log "Current commit: $LAST_COMMIT"

# Install dependencies and start app
if ! install_deps; then
    error "Cannot start application - dependency installation failed"
    exit 1
fi
start_app

# Monitor loop
log "Starting monitoring loop (checking every ${CHECK_INTERVAL}s)..."
while true; do
    sleep "$CHECK_INTERVAL"

    # Check if app is still running
    if [ ! -z "$APP_PID" ] && ! kill -0 $APP_PID 2>/dev/null; then
        warn "Application process died unexpectedly, restarting..."
        start_app
        continue
    fi

    # Fetch latest changes
    cd "$REPO_DIR"
    git fetch origin "$BRANCH" 2>/dev/null || {
        warn "Failed to fetch from remote, will retry next cycle"
        continue
    }

    # Check for new commits
    REMOTE_COMMIT=$(git rev-parse "origin/$BRANCH")

    if [ "$LAST_COMMIT" != "$REMOTE_COMMIT" ]; then
        log "New commit detected: $REMOTE_COMMIT"
        log "Updating application..."

        # Stop current app
        kill_app

        # Pull changes
        git reset --hard "origin/$BRANCH"

        # Update commit hash
        LAST_COMMIT=$REMOTE_COMMIT

        # Reinstall dependencies
        if ! install_deps; then
            error "Failed to install dependencies after update, will retry next cycle"
            continue
        fi

        # Restart app
        start_app

        log "Application updated and restarted successfully"
    fi
done
