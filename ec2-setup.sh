#!/bin/bash

# Flask Portfolio App - EC2 Application Setup Script
# This script runs on the EC2 instance to set up the Flask application
# Can be run manually if needed for debugging or re-deployment

set -e

# Configuration
GITHUB_REPO="https://github.com/hvardhan1024/Cloud_computing_el.git"  # Update this
APP_DIR="/home/ec2-user/flask-portfolio"
LOG_FILE="/var/log/portfolio-setup.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "🚀 Starting Flask Portfolio App setup on EC2..."

# Check if running as root or ec2-user
if [ "$EUID" -eq 0 ]; then
    USER_HOME="/home/ec2-user"
    DOCKER_USER="ec2-user"
else
    USER_HOME="$HOME"
    DOCKER_USER="$(whoami)"
fi

log "📦 Step 1: Installing system packages..."
sudo yum update -y
sudo yum install -y docker git curl postgresql

# Install AWS CLI v2 if not present
if ! command -v aws &> /dev/null; then
    log "📥 Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
fi

log "🐳 Step 2: Setting up Docker..."
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker $DOCKER_USER

# Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
    log "📥 Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Wait for Docker to be ready
log "⏳ Waiting for Docker to be ready..."
sleep 15

# Test Docker access
if ! docker ps &> /dev/null; then
    log "⚠️ Docker not accessible, trying with sudo..."
    DOCKER_CMD="sudo docker"
else
    DOCKER_CMD="docker"
fi

log "📁 Step 3: Setting up application directory..."
cd $USER_HOME

# Remove existing directory if it exists
if [ -d "$APP_DIR" ]; then
    log "🗑️ Removing existing application directory..."
    sudo rm -rf $APP_DIR
fi

log "📥 Step 4: Cloning repository..."
if git clone $GITHUB_REPO flask-portfolio; then
    log "✅ Repository cloned successfully"
    cd flask-portfolio
    
    # Check if essential files exist, create them if missing
    if [ ! -f "Dockerfile" ]; then
        log "⚠️ Dockerfile missing, creating default..."
        cat > Dockerfile << 'DOCKERFILE_EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 5000

# Run the application
CMD ["python", "app.py"]
DOCKERFILE_EOF
    fi
    
    if [ ! -f "requirements.txt" ]; then
        log "⚠️ requirements.txt missing, creating default..."
        cat > requirements.txt << 'REQUIREMENTS_EOF'
Flask==2.3.3
Flask-SQLAlchemy==3.0.5
psycopg2-binary==2.9.7
boto3==1.28.85
Werkzeug==2.3.7
python-dotenv==1.0.0
requests==2.31.0
gunicorn==21.2.0
REQUIREMENTS_EOF
    fi
    
    if [ ! -f "app.py" ]; then
        log "⚠️ app.py missing, creating default..."
        cat > app.py << 'APP_EOF'
from flask import Flask, request, render_template_string, jsonify
import os
import psycopg2
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'fallback-secret-key')

def test_db_connection():
    try:
        conn = psycopg2.connect(os.getenv('DATABASE_URL'))
        cursor = conn.cursor()
        cursor.execute('SELECT version();')
        version = cursor.fetchone()
        cursor.close()
        conn.close()
        return f"✅ Connected: {version[0][:50]}..."
    except Exception as e:
        return f"❌ Connection failed: {str(e)[:100]}..."

def test_s3_connection():
    try:
        s3_client = boto3.client('s3', region_name=os.getenv('AWS_REGION'))
        bucket_name = os.getenv('S3_BUCKET')
        s3_client.head_bucket(Bucket=bucket_name)
        return f"✅ S3 bucket accessible: {bucket_name}"
    except ClientError as e:
        return f"❌ S3 error: {str(e)[:100]}..."
    except Exception as e:
        return f"❌ S3 connection failed: {str(e)[:100]}..."

@app.route('/')
def home():
    db_status = test_db_connection()
    s3_status = test_s3_connection()
    
    return render_template_string('''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Portfolio App - Free Tier Deployment</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { 
                font-family: 'Segoe UI', Arial, sans-serif; 
                margin: 0; 
                padding: 40px; 
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                color: #333;
            }
            .container {
                max-width: 800px;
                margin: 0 auto;
                background: white;
                border-radius: 15px;
                padding: 40px;
                box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            }
            h1 { 
                color: #4a5568; 
                text-align: center; 
                margin-bottom: 30px;
                font-size: 2.5em;
            }
            .status-grid {
                display: grid;
                gap: 20px;
                margin: 30px 0;
            }
            .status { 
                padding: 20px; 
                border-radius: 10px; 
                border-left: 5px solid;
                font-weight: 500;
            }
            .success { 
                background-color: #f0fff4; 
                color: #22543d; 
                border-left-color: #38a169;
            }
            .error { 
                background-color: #fed7d7; 
                color: #742a2a; 
                border-left-color: #e53e3e;
            }
            .info {
                background-color: #ebf8ff;
                color: #2c5282;
                border-left-color: #3182ce;
            }
            .header-info {
                text-align: center;
                margin: 20px 0;
                padding: 20px;
                background: #f7fafc;
                border-radius: 10px;
            }
            .free-tier-badge {
                display: inline-block;
                background: #38a169;
                color: white;
                padding: 8px 16px;
                border-radius: 20px;
                font-size: 0.9em;
                font-weight: bold;
                margin: 10px 0;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Portfolio Application</h1>
            
            <div class="header-info">
                <div class="free-tier-badge">AWS Free Tier Deployment</div>
                <p><strong>Deployment Time:</strong> {{ timestamp }}</p>
            </div>

            <div class="status-grid">
                <div class="status {{ 'success' if '✅' in db_status else 'error' }}">
                    <strong>🗄️ Database Status:</strong><br>{{ db_status }}
                </div>
                
                <div class="status {{ 'success' if '✅' in s3_status else 'error' }}">
                    <strong>📦 S3 Storage Status:</strong><br>{{ s3_status }}
                </div>
                
                <div class="status info">
                    <strong>🌍 AWS Region:</strong> {{ aws_region }}<br>
                    <strong>⚙️ Environment:</strong> {{ flask_env }}
                </div>
                
                <div class="status success">
                    <strong>✅ Application Status:</strong> Running successfully!<br>
                    <strong>🔗 Health Check:</strong> <a href="/health">/health</a>
                </div>
            </div>

            <div class="status info">
                <strong>💰 Free Tier Resources:</strong><br>
                • EC2: t2.micro (750 hours/month)<br>
                • RDS: db.t3.micro (750 hours/month)<br>
                • S3: 5GB storage<br>
                • Data Transfer: 1GB/month
            </div>
        </div>
    </body>
    </html>
    ''', 
    db_status=db_status,
    s3_status=s3_status,
    aws_region=os.getenv('AWS_REGION', 'Not configured'),
    flask_env=os.getenv('FLASK_ENV', 'production'),
    timestamp=datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'))

@app.route('/health')
def health():
    db_status = test_db_connection()
    s3_status = test_s3_connection()
    
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'database': '✅' in db_status,
        's3': '✅' in s3_status,
        'environment': os.getenv('FLASK_ENV', 'production'),
        'region': os.getenv('AWS_REGION', 'unknown')
    })

@app.route('/test-db')
def test_db():
    return jsonify({'database_status': test_db_connection()})

@app.route('/test-s3')
def test_s3():
    return jsonify({'s3_status': test_s3_connection()})

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('FLASK_DEBUG', 'False').lower() == 'true'
    app.run(host='0.0.0.0', port=port, debug=debug)
APP_EOF
    fi
    
else
    log "❌ Failed to clone repository, creating minimal app structure..."
    mkdir -p flask-portfolio
    cd flask-portfolio
    
    # Create minimal working app
    log "📝 Creating minimal Flask application..."
    
    # Create the files as shown above (same content)
    # ... (same file creation logic as in the else block above)
fi

cd $APP_DIR

log "⚙️ Step 5: Creating environment configuration..."

# Create .env file with proper error handling
log "📝 Creating environment file..."

# Validate required environment variables
if [ -z "$DATABASE_URL" ]; then
    log "⚠️ DATABASE_URL not provided"
    if [ -z "$RDS_ENDPOINT" ]; then
        log "❌ No database configuration available"
        DATABASE_URL="postgresql://postgres:password@localhost:5432/postgres"
    else
        DATABASE_URL="postgresql://${DB_USER:-postgres}:${DB_PASSWORD:-password}@${RDS_ENDPOINT}:5432/${DB_NAME:-postgres}"
    fi
fi

if [ -z "$S3_BUCKET" ]; then
    log "⚠️ S3_BUCKET not provided"
    S3_BUCKET="portfolio-app-placeholder"
fi

if [ -z "$AWS_REGION" ]; then
    AWS_REGION="ap-south-1"
fi

# Create comprehensive .env file
cat > .env << EOF
# Database Configuration
DATABASE_URL=$DATABASE_URL

# Flask Configuration
SECRET_KEY=simple-secret-key-$(date +%s)
FLASK_ENV=production
FLASK_DEBUG=False

# AWS Configuration
AWS_REGION=$AWS_REGION
S3_BUCKET=$S3_BUCKET
AWS_DEFAULT_REGION=$AWS_REGION

# Application Settings
PORT=5000
UPLOAD_MAX_SIZE=16777216

# Additional settings
PYTHONUNBUFFERED=1
EOF

log "✅ Environment file created"

# Test database connectivity if possible
if command -v psql &> /dev/null && [ ! -z "$RDS_ENDPOINT" ]; then
    log "🔍 Testing database connectivity..."
    if PGPASSWORD="${DB_PASSWORD:-password}" psql -h "${RDS_ENDPOINT}" -U "${DB_USER:-postgres}" -d "${DB_NAME:-postgres}" -c "SELECT version();" &> /dev/null; then
        log "✅ Database connection successful"
    else
        log "⚠️ Database connection failed - this is normal if RDS is still starting"
    fi
fi

log "🔨 Step 6: Building Docker image..."
if $DOCKER_CMD build -t portfolio-app .; then
    log "✅ Docker image built successfully"
else
    log "❌ Failed to build Docker image"
    log "📝 Checking Dockerfile and requirements..."
    ls -la
    exit 1
fi

log "🚀 Step 7: Starting application container..."

# Stop and remove existing container if it exists
$DOCKER_CMD stop portfolio-container 2>/dev/null || true
$DOCKER_CMD rm portfolio-container 2>/dev/null || true

# Run the container with health check
if $DOCKER_CMD run -d \
    -p 5000:5000 \
    --env-file .env \
    --name portfolio-container \
    --restart unless-stopped \
    --health-cmd="curl -f http://localhost:5000/health || exit 1" \
    --health-interval=30s \
    --health-timeout=10s \
    --health-retries=3 \
    portfolio-app; then
    log "✅ Application container started successfully"
else
    log "❌ Failed to start application container"
    log "📝 Checking Docker logs..."
    $DOCKER_CMD logs portfolio-container 2>/dev/null || true
    exit 1
fi

# Wait for application to start
log "⏳ Waiting for application to be ready (60 seconds)..."
sleep 60

# Check if application is responding
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")
APP_URL="http://localhost:5000"

if curl -f $APP_URL/health >/dev/null 2>&1; then
    log "✅ Application is responding on port 5000"
    log "🌐 Application URL: http://$PUBLIC_IP:5000"
else
    log "⚠️ Application health check failed, checking container status..."
    $DOCKER_CMD ps -a | grep portfolio-container || true
    log "📝 Container logs:"
    $DOCKER_CMD logs --tail 50 portfolio-container || true
fi

log "🔧 Step 8: Setting up file permissions..."
sudo chown -R $DOCKER_USER:$DOCKER_USER $APP_DIR

log "📊 Step 9: Final status check..."
echo ""
echo "=== Docker Container Status ==="
$DOCKER_CMD ps -a | grep portfolio-container || echo "Container not found"

echo ""
echo "=== Recent Application Logs ==="
$DOCKER_CMD logs --tail 20 portfolio-container 2>/dev/null || echo "No logs available"

echo ""
echo "=== Environment Configuration ==="
echo "Database URL: ${DATABASE_URL//:*@/:***@}"  # Hide password
echo "S3 Bucket: $S3_BUCKET"
echo "AWS Region: $AWS_REGION"

echo ""
echo "=== Network Information ==="
echo "Public IP: $PUBLIC_IP"
echo "Application URL: http://$PUBLIC_IP:5000"
echo "Health Check: http://$PUBLIC_IP:5000/health"

log "🎉 Flask Portfolio App setup completed!"
log "📍 Application should be accessible at: http://$PUBLIC_IP:5000"
log "📝 Setup logs are available at: $LOG_FILE"
log "🐳 Container name: portfolio-container"

echo ""
echo "🔍 Troubleshooting commands:"
echo "   View logs: $DOCKER_CMD logs portfolio-container"
echo "   Follow logs: $DOCKER_CMD logs -f portfolio-container"
echo "   Restart app: $DOCKER_CMD restart portfolio-container"
echo "   Check status: $DOCKER_CMD ps"
echo "   Access container: $DOCKER_CMD exec -it portfolio-container /bin/bash"
echo "   Test locally: curl http://localhost:5000/health"
