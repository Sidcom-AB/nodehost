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

RELEASES_DIR="/app/releases"
CURRENT_LINK="/app/current"
APP_PID=""
CURRENT_RELEASE=""

# Create releases directory
mkdir -p "$RELEASES_DIR"

# Function to kill the app gracefully
kill_app() {
    if [ ! -z "$APP_PID" ] && kill -0 $APP_PID 2>/dev/null; then
        log "Stopping application gracefully (PID: $APP_PID)..."

        # Try SIGTERM first (graceful shutdown)
        kill -TERM $APP_PID 2>/dev/null || true

        # Wait up to 10 seconds for graceful shutdown
        local count=0
        while kill -0 $APP_PID 2>/dev/null && [ $count -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done

        # If still running, force kill
        if kill -0 $APP_PID 2>/dev/null; then
            warn "Process didn't stop gracefully, forcing shutdown..."
            kill -KILL $APP_PID 2>/dev/null || true
            wait $APP_PID 2>/dev/null || true
        fi

        log "Application stopped"
        APP_PID=""

        # Wait a bit for ports to be released
        log "Waiting for ports to be released..."
        sleep 2
    fi
}

# Function to start the app
start_app() {
    local release_dir=$1

    log "Starting application with: $START_COMMAND"
    log "Working directory: $release_dir"

    # List all custom environment variables (exclude default system vars)
    log "Environment variables being passed to app:"
    env | grep -v -E '^(PATH|HOME|HOSTNAME|PWD|SHLVL|_|OLDPWD|TERM|REPO_URL|BRANCH|CHECK_INTERVAL|START_COMMAND|INSTALL_COMMAND)=' | while read line; do
        # Mask sensitive values in logs
        key=$(echo "$line" | cut -d'=' -f1)
        log "  $key=***"
    done

    # Start the app in background with explicit directory
    cd "$release_dir"
    eval "$START_COMMAND" &
    APP_PID=$!

    log "Application started with PID: $APP_PID"
}

# Function to install dependencies
install_deps() {
    local release_dir=$1
    cd "$release_dir"

    if [ ! -f "package.json" ]; then
        warn "No package.json found, skipping dependency installation"
        return 0
    fi

    # Try npm ci first if package-lock.json exists
    if [ -f "package-lock.json" ] && [ "$INSTALL_COMMAND" = "npm install" ]; then
        log "Found package-lock.json, trying: npm ci"
        if npm ci 2>&1; then
            log "Dependencies installed successfully with npm ci"
        else
            warn "npm ci failed (possibly out of sync), falling back to npm install"
            if npm install; then
                log "Dependencies installed successfully with npm install"
            else
                error "Failed to install dependencies!"
                return 1
            fi
        fi
    else
        log "Installing dependencies with: $INSTALL_COMMAND"
        if eval "$INSTALL_COMMAND"; then
            log "Dependencies installed successfully"
        else
            error "Failed to install dependencies!"
            return 1
        fi
    fi

    # Verify node_modules exists
    if [ ! -d "node_modules" ]; then
        error "node_modules directory not created after installation!"
        return 1
    fi
    log "node_modules directory verified"
    return 0
}

# Function to cleanup old releases (keep last 3)
cleanup_old_releases() {
    log "Cleaning up old releases..."
    local keep_count=3
    local releases=($(ls -t "$RELEASES_DIR" 2>/dev/null))
    local count=0

    for release in "${releases[@]}"; do
        count=$((count + 1))
        if [ $count -gt $keep_count ]; then
            local release_path="$RELEASES_DIR/$release"
            # Don't delete if it's the current release
            if [ "$release_path" != "$CURRENT_RELEASE" ]; then
                log "Removing old release: $release"
                rm -rf "$release_path"
            fi
        fi
    done
}

# Function to deploy a new release
deploy_release() {
    local commit_hash=$1
    local release_dir="$RELEASES_DIR/$commit_hash"

    log "Deploying release: $commit_hash"

    # Create release directory
    mkdir -p "$release_dir"

    # Clone or copy repo to release directory
    if [ -d "$release_dir/.git" ]; then
        log "Release directory exists, updating..."
        cd "$release_dir"
        git fetch origin
        git reset --hard "$commit_hash"
    else
        log "Cloning repository to release directory..."
        git clone "$REPO_URL" "$release_dir"
        cd "$release_dir"
        git checkout "$commit_hash"
    fi

    # Install dependencies in new release
    if ! install_deps "$release_dir"; then
        error "Failed to install dependencies for new release"
        rm -rf "$release_dir"
        return 1
    fi

    # Stop old application
    kill_app

    # Update symlink to new release
    rm -f "$CURRENT_LINK"
    ln -sf "$release_dir" "$CURRENT_LINK"
    CURRENT_RELEASE="$release_dir"

    log "Symlink updated to new release"

    # Start new application
    start_app "$release_dir"

    # Cleanup old releases
    cleanup_old_releases

    return 0
}

# Trap signals to ensure cleanup
trap 'log "Received signal, shutting down..."; kill_app; exit 0' SIGTERM SIGINT

# Initial setup - check if we have an existing deployment
if [ -L "$CURRENT_LINK" ] && [ -d "$(readlink -f "$CURRENT_LINK")" ]; then
    log "Found existing deployment"
    CURRENT_RELEASE=$(readlink -f "$CURRENT_LINK")
    cd "$CURRENT_RELEASE"
    LAST_COMMIT=$(git rev-parse HEAD)
    log "Current commit: $LAST_COMMIT"

    # Start existing app
    start_app "$CURRENT_RELEASE"
else
    log "No existing deployment, performing initial deployment..."

    # Clone to temporary location to get commit hash
    temp_clone="/tmp/repo-temp-$$"
    git clone -b "$BRANCH" "$REPO_URL" "$temp_clone"
    cd "$temp_clone"
    LAST_COMMIT=$(git rev-parse HEAD)
    rm -rf "$temp_clone"

    log "Initial commit: $LAST_COMMIT"

    # Deploy initial release
    if ! deploy_release "$LAST_COMMIT"; then
        error "Initial deployment failed"
        exit 1
    fi
fi

# Monitor loop
log "Starting monitoring loop (checking every ${CHECK_INTERVAL}s)..."
while true; do
    sleep "$CHECK_INTERVAL"

    # Check if app is still running
    if [ ! -z "$APP_PID" ] && ! kill -0 $APP_PID 2>/dev/null; then
        warn "Application process died unexpectedly, restarting..."
        start_app "$CURRENT_RELEASE"
        continue
    fi

    # Fetch latest changes
    cd "$CURRENT_RELEASE"
    git fetch origin "$BRANCH" 2>/dev/null || {
        warn "Failed to fetch from remote, will retry next cycle"
        continue
    }

    # Check for new commits
    REMOTE_COMMIT=$(git rev-parse "origin/$BRANCH")

    if [ "$LAST_COMMIT" != "$REMOTE_COMMIT" ]; then
        log "New commit detected: $REMOTE_COMMIT"
        log "Updating application..."

        # Deploy new release
        if deploy_release "$REMOTE_COMMIT"; then
            LAST_COMMIT=$REMOTE_COMMIT
            log "Application updated and restarted successfully"
        else
            error "Deployment failed, keeping current version running"
        fi
    fi
done
