#!/usr/bin/env python3
"""
Simple Flask application that uses AWS AppConfig to control feature flags.
This app demonstrates how to retrieve configuration from AppConfig agent
and use it to enable/disable features dynamically.
"""

import json
import logging
import os
import time
from threading import Thread
from flask import Flask, jsonify, render_template_string
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global configuration cache
current_config = {
    "featureXEnabled": False,
    "apiUrl": "https://api.example.com"
}

# Mock users data
MOCK_USERS = [
    {"id": 1, "name": "Alice Johnson", "email": "alice@example.com", "role": "admin"},
    {"id": 2, "name": "Bob Smith", "email": "bob@example.com", "role": "user"},
    {"id": 3, "name": "Carol Davis", "email": "carol@example.com", "role": "user"},
    {"id": 4, "name": "David Wilson", "email": "david@example.com", "role": "moderator"},
    {"id": 5, "name": "Eve Brown", "email": "eve@example.com", "role": "user"}
]

# AppConfig agent configuration
APPCONFIG_AGENT_URL = "http://localhost:2772"
APPCONFIG_APPLICATION = os.getenv("APPCONFIG_APPLICATION", "myapp")
APPCONFIG_ENVIRONMENT = os.getenv("APPCONFIG_ENVIRONMENT", "prod")
APPCONFIG_PROFILE = os.getenv("APPCONFIG_PROFILE", "app-config")

def fetch_config_from_agent():
    """Fetch configuration from AppConfig agent."""
    try:
        url = f"{APPCONFIG_AGENT_URL}/applications/{APPCONFIG_APPLICATION}/environments/{APPCONFIG_ENVIRONMENT}/configurations/{APPCONFIG_PROFILE}"
        logger.info(f"Fetching config from: {url}")
        
        response = requests.get(url, timeout=5)
        if response.status_code == 200:
            config_data = response.json()
            logger.info(f"Successfully retrieved config: {config_data}")
            return config_data
        elif response.status_code == 304:
            logger.info("Config not modified (304)")
            return None
        else:
            logger.error(f"Failed to fetch config: {response.status_code} - {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        logger.error(f"Error fetching config from agent: {e}")
        return None

def config_updater():
    """Background thread to periodically update configuration."""
    global current_config
    
    while True:
        try:
            new_config = fetch_config_from_agent()
            if new_config:
                old_config = current_config.copy()
                current_config.update(new_config)
                
                # Log configuration changes
                if old_config.get("featureXEnabled") != current_config.get("featureXEnabled"):
                    logger.info(f"Feature flag changed: featureXEnabled = {current_config.get('featureXEnabled')}")
                
                logger.info(f"Configuration updated: {current_config}")
        except Exception as e:
            logger.error(f"Error in config updater: {e}")
        
        time.sleep(30)  # Check for updates every 30 seconds

@app.route('/')
def home():
    """Home page showing current configuration and available endpoints."""
    html_template = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Flask AppConfig Demo</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .config { background: #f0f0f0; padding: 20px; border-radius: 5px; margin: 20px 0; }
            .feature-enabled { color: green; }
            .feature-disabled { color: red; }
            .endpoint { background: #e8f4f8; padding: 10px; margin: 10px 0; border-radius: 3px; }
            .status { font-weight: bold; }
        </style>
    </head>
    <body>
        <h1>Flask AppConfig Demo Application</h1>
        
        <h2>Current Configuration</h2>
        <div class="config">
            <pre>{{ config | tojson(indent=2) }}</pre>
        </div>
        
        <h2>User Listing Feature Status</h2>
        <p class="status {{ 'feature-enabled' if config.featureXEnabled else 'feature-disabled' }}">
            Feature is currently <strong>{{ 'ENABLED' if config.featureXEnabled else 'DISABLED' }}</strong>
        </p>
        
        <h2>Available Endpoints</h2>
        <div class="endpoint">
            <strong>GET /</strong> - This home page
        </div>
        <div class="endpoint">
            <strong>GET /health</strong> - Health check endpoint
        </div>
        <div class="endpoint">
            <strong>GET /config</strong> - Current configuration (JSON)
        </div>
        <div class="endpoint">
            <strong>GET /users</strong> - List users (controlled by featureXEnabled flag)
        </div>
        
        <h2>Instructions</h2>
        <p>To test the feature flag functionality:</p>
        <ol>
            <li>Visit <a href="/users">/users</a> to see the current behavior</li>
            <li>Update the <code>featureXEnabled</code> flag in AWS AppConfig console</li>
            <li>Wait up to 30 seconds for the configuration to refresh</li>
            <li>Visit <a href="/users">/users</a> again to see the change</li>
        </ol>
    </body>
    </html>
    """
    return render_template_string(html_template, config=current_config)

@app.route('/health')
def health():
    """Health check endpoint."""
    return jsonify({
        "status": "healthy",
        "timestamp": time.time(),
        "config_loaded": bool(current_config)
    })

@app.route('/config')
def get_config():
    """Return current configuration as JSON."""
    return jsonify(current_config)

@app.route('/users')
def list_users():
    """List users - controlled by featureXEnabled flag."""
    if not current_config.get("featureXEnabled", False):
        return jsonify({
            "error": "User listing feature is currently disabled",
            "message": "This feature is controlled by the 'featureXEnabled' flag in AppConfig",
            "current_flag_value": current_config.get("featureXEnabled", False)
        }), 403
    
    return jsonify({
        "users": MOCK_USERS,
        "total_count": len(MOCK_USERS),
        "feature_enabled": True,
        "timestamp": time.time()
    })

def initialize_config():
    """Initialize configuration during app startup."""
    logger.info("Initializing application configuration...")
    
    # Try to fetch initial config
    initial_config = fetch_config_from_agent()
    if initial_config:
        current_config.update(initial_config)
        logger.info(f"Initial config loaded: {current_config}")
    else:
        logger.warning("Could not fetch initial config, using defaults")
    
    # Start background config updater
    config_thread = Thread(target=config_updater, daemon=True)
    config_thread.start()
    logger.info("Configuration updater thread started")

# Initialize configuration when the app starts
with app.app_context():
    initialize_config()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
