require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { PrismaClient } = require('@prisma/client');

const app = express();
const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development' ? ['query', 'info', 'warn', 'error'] : ['error'],
});
const PORT = process.env.PORT || 3000;

console.log('🚀 Starting Inventory Pro Server...');
console.log('📊 Environment:', process.env.NODE_ENV || 'development');
console.log('🔑 JWT_SECRET exists:', !!process.env.JWT_SECRET);
console.log('🗄️ DATABASE_URL exists:', !!process.env.DATABASE_URL);

// Middleware
app.use(cors({
  origin: process.env.NODE_ENV === 'production' 
    ? [
        process.env.FRONTEND_URL, 
        /\.railway\.app$/, 
        'https://gavin-morris-04.github.io',
        /\.netlify\.app$/,
        /\.github\.io$/,
        'https://inventoryprotracker.com',
        'http://inventoryprotracker.com',
        'https://www.inventoryprotracker.com',
        'http://www.inventoryprotracker.com',
        'null'
      ] 
    : [
        'http://localhost:3000', 
        'http://localhost:8080', 
        'http://127.0.0.1:3000',
        'https://gavin-morris-04.github.io',
        'null'
      ],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Origin', 'Accept']
}));

// Handle preflight requests
app.options('*', cors());

app.use(express.json({ limit: '10mb' }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Health check for Railway
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({ 
    message: 'Inventory Pro API - Running Successfully!',
    version: '2.0.0',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
    endpoints: {
      health: '/health',
      login: '/api/auth/login',
      register: '/api/companies/register',
      items: '/api/items',
      activities: '/api/activities',
      invites: '/api/invites'
    }
  });
});

// Database connection test
app.get('/api/health/db', async (req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ database: 'connected', timestamp: new Date().toISOString() });
  } catch (error) {
    console.error('Database connection error:', error);
    res.status(500).json({ 
      database: 'disconnected', 
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Invite system health check
app.get('/api/health/invites', async (req, res) => {
  try {
    const inviteCount = await prisma.invite.count();
    res.json({ 
      invites: 'working', 
      count: inviteCount,
      timestamp: new Date().toISOString() 
    });
  } catch (error) {
    console.error('Invite system health check error:', error);
    res.status(500).json({ 
      invites: 'error', 
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Auth middleware
const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      include: { company: true }
    });
    
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }
    
    if (!user.isActive) {
      return res.status(401).json({ error: 'User account is disabled' });
    }
    
    req.user = user;
    next();
  } catch (error) {
    console.error('Token verification error:', error);
    return res.status(403).json({ error: 'Invalid token' });
  }
};

// AUTH ENDPOINTS

// Login
app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }
    
    console.log('🔐 Login attempt for:', email);
    
    // Find user and include company
    const user = await prisma.user.findFirst({
      where: { 
        email: email.toLowerCase().trim(),
        isActive: true 
      },
      include: { company: true }
    });
    
    if (!user) {
      console.log('❌ User not found:', email);
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    
    // Check password
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      console.log('❌ Invalid password for:', email);
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    
    // Update last login
    await prisma.user.update({
      where: { id: user.id },
      data: { last_login: new Date() }
    });
    
    // Generate token
    const token = jwt.sign(
      { 
        userId: user.id, 
        companyId: user.company_id,
        role: user.role 
      },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    console.log('✅ Login successful for:', user.name);
    
    res.json({
      success: true,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
        created_at: user.created_at.toISOString()
      },
      company: {
        id: user.company.id,
        name: user.company.name,
        code: user.company.code,
        subscription_tier: user.company.subscription_tier,
        max_users: user.company.max_users,
        low_stock_threshold: user.company.low_stock_threshold || 5
      },
      token
    });
    
  } catch (error) {
    console.error('❌ Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Register Company
app.post('/api/companies/register', async (req, res) => {
  try {
    const { companyName, adminEmail, adminPassword, adminName } = req.body;
    
    // Validation
    if (!companyName || !adminEmail || !adminPassword || !adminName) {
      return res.status(400).json({ error: 'All fields are required' });
    }
    
    if (adminPassword.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }
    
    const email = adminEmail.toLowerCase().trim();
    
    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email }
    });
    
    if (existingUser) {
      return res.status(400).json({ error: 'User already exists' });
    }
    
    // Hash password
    const hashedPassword = await bcrypt.hash(adminPassword, 12);
    
    // Generate company code
    const companyCode = companyName.substring(0, 3).toUpperCase() + Math.floor(Math.random() * 1000).toString().padStart(3, '0');
    
    // Check if company code exists
    const existingCompany = await prisma.company.findUnique({
      where: { code: companyCode }
    });
    
    const finalCompanyCode = existingCompany 
      ? companyCode + Math.floor(Math.random() * 100)
      : companyCode;
    
    // Create company and admin user in transaction
    const result = await prisma.$transaction(async (prisma) => {
      const company = await prisma.company.create({
        data: {
          name: companyName.trim(),
          code: finalCompanyCode,
          subscription_tier: 'trial',
          max_users: 50,
          low_stock_threshold: 5
        }
      });
      
      const user = await prisma.user.create({
        data: {
          email,
          name: adminName.trim(),
          password: hashedPassword,
          role: 'admin',
          company_id: company.id
        }
      });
      
      return { company, user };
    });
    
    // Generate token
    const token = jwt.sign(
      { 
        userId: result.user.id, 
        companyId: result.company.id,
        role: result.user.role 
      },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    console.log('✅ Company registered:', result.company.name);
    
    res.status(201).json({
      success: true,
      user: {
        id: result.user.id,
        email: result.user.email,
        name: result.user.name,
        role: result.user.role,
        created_at: result.user.created_at.toISOString()
      },
      company: {
        id: result.company.id,
        name: result.company.name,
        code: result.company.code,
        subscription_tier: result.company.subscription_tier,
        max_users: result.company.max_users,
        low_stock_threshold: result.company.low_stock_threshold
      },
      token
    });
    
  } catch (error) {
    console.error('❌ Registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// ITEMS ENDPOINTS

// Get all items
app.get('/api/items', authenticateToken, async (req, res) => {
  try {
    const items = await prisma.item.findMany({
      where: { company_id: req.user.company_id },
      orderBy: { created_at: 'desc' }
    });
    
    const formattedItems = items.map(item => ({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      barcode: item.barcode,
      updated_at: item.updated_at.toISOString(),
      low_stock_threshold: item.low_stock_threshold
    }));
    
    res.json(formattedItems);
  } catch (error) {
    console.error('❌ Get items error:', error);
    res.status(500).json({ error: 'Failed to fetch items' });
  }
});

// Create item
app.post('/api/items', authenticateToken, async (req, res) => {
  try {
    const { name, quantity, barcode } = req.body;
    
    if (!name || !barcode) {
      return res.status(400).json({ error: 'Name and barcode are required' });
    }
    
    // Check if barcode already exists
    const existingItem = await prisma.item.findUnique({
      where: { barcode }
    });
    
    if (existingItem) {
      return res.status(400).json({ error: 'Barcode already exists' });
    }
    
    const item = await prisma.item.create({
      data: {
        name: name.trim(),
        quantity: parseInt(quantity) || 0,
        barcode: barcode.trim(),
        company_id: req.user.company_id
      }
    });
    
    // Log activity
    await prisma.activity.create({
      data: {
        type: 'created',
        quantity: item.quantity,
        item_name: item.name,
        user_name: req.user.name,
        company_id: req.user.company_id,
        item_id: item.id,
        user_id: req.user.id
      }
    });
    
    console.log('✅ Item created:', item.name);
    
    res.status(201).json({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      barcode: item.barcode,
      updated_at: item.updated_at.toISOString(),
      low_stock_threshold: item.low_stock_threshold
    });
  } catch (error) {
    console.error('❌ Create item error:', error);
    res.status(500).json({ error: 'Failed to create item' });
  }
});

// Update item quantity
app.put('/api/items', authenticateToken, async (req, res) => {
  try {
    const { id, quantity } = req.body;
    
    if (!id || quantity === undefined) {
      return res.status(400).json({ error: 'ID and quantity are required' });
    }
    
    const existingItem = await prisma.item.findFirst({
      where: { 
        id,
        company_id: req.user.company_id 
      }
    });
    
    if (!existingItem) {
      return res.status(404).json({ error: 'Item not found' });
    }
    
    const newQuantity = Math.max(0, parseInt(quantity));
    
    const item = await prisma.item.update({
      where: { id },
      data: { quantity: newQuantity }
    });
    
    // Log activity
    const change = newQuantity - existingItem.quantity;
    const activityType = change > 0 ? 'added' : 'removed';
    
    await prisma.activity.create({
      data: {
        type: activityType,
        quantity: Math.abs(change),
        old_quantity: existingItem.quantity,
        item_name: item.name,
        user_name: req.user.name,
        company_id: req.user.company_id,
        item_id: item.id,
        user_id: req.user.id
      }
    });
    
    res.json({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      barcode: item.barcode,
      updated_at: item.updated_at.toISOString(),
      low_stock_threshold: item.low_stock_threshold
    });
  } catch (error) {
    console.error('❌ Update item error:', error);
    res.status(500).json({ error: 'Failed to update item' });
  }
});

// Update item low stock threshold
app.put('/api/items/threshold', authenticateToken, async (req, res) => {
  try {
    const { id, lowStockThreshold } = req.body;
    
    if (!id || lowStockThreshold === undefined) {
      return res.status(400).json({ error: 'ID and lowStockThreshold are required' });
    }
    
    const existingItem = await prisma.item.findFirst({
      where: { 
        id,
        company_id: req.user.company_id 
      }
    });
    
    if (!existingItem) {
      return res.status(404).json({ error: 'Item not found' });
    }
    
    const item = await prisma.item.update({
      where: { id },
      data: { low_stock_threshold: parseInt(lowStockThreshold) }
    });
    
    console.log('✅ Item threshold updated:', item.name);
    
    res.json({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      barcode: item.barcode,
      updated_at: item.updated_at.toISOString(),
      low_stock_threshold: item.low_stock_threshold
    });
  } catch (error) {
    console.error('❌ Update item threshold error:', error);
    res.status(500).json({ error: 'Failed to update item threshold' });
  }
});

// Delete item
app.delete('/api/items', authenticateToken, async (req, res) => {
  try {
    const { id } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'ID is required' });
    }
    
    const item = await prisma.item.findFirst({
      where: { 
        id,
        company_id: req.user.company_id 
      }
    });
    
    if (!item) {
      return res.status(404).json({ error: 'Item not found' });
    }
    
    // Log activity before deletion
    await prisma.activity.create({
      data: {
        type: 'deleted',
        quantity: item.quantity,
        item_name: item.name,
        user_name: req.user.name,
        company_id: req.user.company_id,
        user_id: req.user.id
      }
    });
    
    await prisma.item.delete({
      where: { id }
    });
    
    console.log('✅ Item deleted:', item.name);
    
    res.json({ success: true });
  } catch (error) {
    console.error('❌ Delete item error:', error);
    res.status(500).json({ error: 'Failed to delete item' });
  }
});

// Search item by barcode
app.get('/api/items/search', authenticateToken, async (req, res) => {
  try {
    const { barcode } = req.query;
    
    if (!barcode) {
      return res.status(400).json({ error: 'Barcode parameter is required' });
    }
    
    const item = await prisma.item.findFirst({
      where: { 
        barcode: barcode.trim(),
        company_id: req.user.company_id
      }
    });
    
    if (!item) {
      return res.status(404).json({ error: 'Item not found' });
    }
    
    res.json({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      barcode: item.barcode,
      updated_at: item.updated_at.toISOString(),
      low_stock_threshold: item.low_stock_threshold
    });
  } catch (error) {
    console.error('❌ Search item error:', error);
    res.status(500).json({ error: 'Failed to search item' });
  }
});

// ACTIVITIES ENDPOINTS

// Get activities
app.get('/api/activities', authenticateToken, async (req, res) => {
  try {
    const activities = await prisma.activity.findMany({
      where: { company_id: req.user.company_id },
      orderBy: { created_at: 'desc' },
      take: 100
    });
    
    const formattedActivities = activities.map(activity => ({
      id: activity.id,
      type: activity.type,
      quantity: activity.quantity,
      old_quantity: activity.old_quantity,
      item_name: activity.item_name,
      user_name: activity.user_name,
      created_at: activity.created_at.toISOString(),
      session_title: activity.session_title,
      item_id: activity.item_id
    }));
    
    res.json(formattedActivities);
  } catch (error) {
    console.error('❌ Get activities error:', error);
    res.status(500).json({ error: 'Failed to fetch activities' });
  }
});

// Get activities for specific item
app.get('/api/activities/item/:itemId', authenticateToken, async (req, res) => {
  try {
    const { itemId } = req.params;
    
    const activities = await prisma.activity.findMany({
      where: { 
        company_id: req.user.company_id,
        item_id: itemId
      },
      orderBy: { created_at: 'desc' },
      take: 50
    });
    
    const formattedActivities = activities.map(activity => ({
      id: activity.id,
      type: activity.type,
      quantity: activity.quantity,
      old_quantity: activity.old_quantity,
      item_name: activity.item_name,
      user_name: activity.user_name,
      created_at: activity.created_at.toISOString(),
      session_title: activity.session_title,
      item_id: activity.item_id
    }));
    
    res.json(formattedActivities);
  } catch (error) {
    console.error('❌ Get item activities error:', error);
    res.status(500).json({ error: 'Failed to fetch item activities' });
  }
});

// Create batch activity
app.post('/api/activities/batch', authenticateToken, async (req, res) => {
  try {
    const { sessionTitle, items } = req.body;
    
    if (!sessionTitle || !items || !Array.isArray(items)) {
      return res.status(400).json({ error: 'Session title and items array are required' });
    }
    
    console.log('🔄 Processing batch operation:', sessionTitle);
    
    // Process all items in a transaction
    await prisma.$transaction(async (prisma) => {
      for (const batchItem of items) {
        const { itemId, quantityChange } = batchItem;
        
        // Get current item
        const currentItem = await prisma.item.findFirst({
          where: { 
            id: itemId,
            company_id: req.user.company_id 
          }
        });
        
        if (!currentItem) {
          throw new Error(`Item not found: ${itemId}`);
        }
        
        // Calculate new quantity
        const newQuantity = Math.max(0, currentItem.quantity + quantityChange);
        
        // Update item quantity
        await prisma.item.update({
          where: { id: itemId },
          data: { quantity: newQuantity }
        });
        
        // Log activity
        const activityType = quantityChange > 0 ? 'added' : 'removed';
        
        await prisma.activity.create({
          data: {
            type: activityType,
            quantity: Math.abs(quantityChange),
            old_quantity: currentItem.quantity,
            item_name: currentItem.name,
            user_name: req.user.name,
            company_id: req.user.company_id,
            item_id: currentItem.id,
            user_id: req.user.id,
            session_title: sessionTitle
          }
        });
      }
    });
    
    console.log('✅ Batch operation completed:', sessionTitle);
    
    res.json({ success: true });
  } catch (error) {
    console.error('❌ Batch activity error:', error);
    res.status(500).json({ error: 'Failed to process batch operation' });
  }
});

// USERS ENDPOINTS (Admin only)

// Get users
app.get('/api/users', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }
    
    const users = await prisma.user.findMany({
      where: { company_id: req.user.company_id },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        isActive: true,
        last_login: true,
        created_at: true
      },
      orderBy: { created_at: 'asc' }
    });
    
    const formattedUsers = users.map(user => ({
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      isActive: user.isActive,
      lastLogin: user.last_login?.toISOString(),
      created_at: user.created_at.toISOString()
    }));
    
    res.json(formattedUsers);
  } catch (error) {
    console.error('❌ Get users error:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// INVITE SYSTEM ENDPOINTS

// Generate invite link
app.post('/api/users/generate-invite', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { role } = req.body;
    
    if (!role || !['user', 'admin'].includes(role)) {
      return res.status(400).json({ error: 'Valid role is required' });
    }

    // Generate invite token
    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

    // Save invite to database
    const invite = await prisma.invite.create({
      data: {
        token,
        company_id: req.user.company_id,
        inviter_id: req.user.id,
        role,
        expires_at: expiresAt,
        used: false
      }
    });

    // Create frontend URL that matches your existing invite.html structure
    const frontendUrl = process.env.FRONTEND_URL || 'https://gavin-morris-04.github.io';
    const inviteUrl = `${frontendUrl}/inventorypro-website/index.html?token=${token}`;

    console.log('✅ Invite link generated:', inviteUrl);

    res.json({
      token,
      company_name: req.user.company.name,
      inviter_name: req.user.name,
      role,
      expires_at: expiresAt.toISOString(),
      invite_url: inviteUrl
    });
  } catch (error) {
    console.error('❌ Generate invite error:', error);
    res.status(500).json({ error: 'Failed to generate invite link' });
  }
});

// Validate invite token (NEW ENDPOINT for invite.html)
app.get('/api/users/validate-invite/:token', async (req, res) => {
  try {
    const { token } = req.params;
    
    const invite = await prisma.invite.findFirst({
      where: { 
        token, 
        used: false, 
        expires_at: { gt: new Date() } 
      },
      include: { 
        company: true, 
        inviter: { 
          select: { name: true } // Only select name for security
        }
      }
    });
    
    if (!invite) {
      return res.status(404).json({ error: 'Invitation not found or expired' });
    }
    
    res.json({
      company_name: invite.company.name,
      inviter_name: invite.inviter.name,
      role: invite.role,
      expires_at: invite.expires_at.toISOString()
    });
    
  } catch (error) {
    console.error('❌ Validate invite error:', error);
    res.status(500).json({ error: 'Failed to validate invitation' });
  }
});

// Get invite details (legacy endpoint)
app.get('/api/invites/:token', async (req, res) => {
  try {
    const { token } = req.params;
    
    const invite = await prisma.invite.findFirst({
      where: { 
        token, 
        used: false, 
        expires_at: { gt: new Date() } 
      },
      include: { 
        company: true, 
        inviter: { 
          select: { name: true } // Only select name for security
        }
      }
    });
    
    if (!invite) {
      return res.status(404).json({ error: 'Invite not found or expired' });
    }
    
    res.json({
      company_name: invite.company.name,
      inviter_name: invite.inviter.name,
      role: invite.role,
      expires_at: invite.expires_at.toISOString()
    });
    
  } catch (error) {
    console.error('❌ Get invite details error:', error);
    res.status(500).json({ error: 'Failed to get invite details' });
  }
});

// Accept invite (UPDATED to return authToken)
app.post('/api/users/accept-invite', async (req, res) => {
  try {
    const { token, name, email, password } = req.body;
    
    if (!token || !name || !email || !password) {
      return res.status(400).json({ error: 'All fields are required' });
    }

    // Find and validate invite
    const invite = await prisma.invite.findFirst({
      where: { 
        token, 
        used: false, 
        expires_at: { gt: new Date() } 
      },
      include: { company: true }
    });
    
    if (!invite) {
      return res.status(404).json({ error: 'Invite not found or expired' });
    }
    
    const userEmail = email.toLowerCase().trim();
    
    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email: userEmail }
    });
    
    if (existingUser) {
      return res.status(400).json({ error: 'User with this email already exists' });
    }
    
    // Hash password
    const hashedPassword = await bcrypt.hash(password, 12);
    
    // Create user and mark invite as used in transaction
    const result = await prisma.$transaction(async (prisma) => {
      // Create user
      const user = await prisma.user.create({
        data: {
          name: name.trim(),
          email: userEmail,
          password: hashedPassword,
          role: invite.role,
          company_id: invite.company_id
        }
      });
      
      // Mark invite as used
      await prisma.invite.update({
        where: { id: invite.id },
        data: { used: true }
      });
      
      return user;
    });
    
    // Generate auth token
    const authToken = jwt.sign(
      { 
        userId: result.id, 
        companyId: invite.company_id,
        role: invite.role 
      },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    console.log('✅ Invite accepted by:', result.email);
    
    res.json({
      success: true,
      user: {
        id: result.id,
        name: result.name,
        email: result.email,
        role: result.role,
        created_at: result.created_at.toISOString()
      },
      company: {
        id: invite.company.id,
        name: invite.company.name,
        code: invite.company.code,
        subscription_tier: invite.company.subscription_tier,
        max_users: invite.company.max_users,
        low_stock_threshold: invite.company.low_stock_threshold
      },
      authToken: authToken // This is what invite.html expects
    });
    
  } catch (error) {
    console.error('❌ Accept invite error:', error);
    res.status(500).json({ error: 'Failed to accept invitation' });
  }
});

// Delete user (Admin only)
app.delete('/api/users/delete', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { userId } = req.body;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    // Don't allow deleting yourself
    if (userId === req.user.id) {
      return res.status(400).json({ error: 'Cannot delete your own account' });
    }

    // Check if user exists and belongs to the same company
    const userToDelete = await prisma.user.findFirst({
      where: { 
        id: userId,
        company_id: req.user.company_id 
      }
    });

    if (!userToDelete) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Soft delete by setting isActive to false
    await prisma.user.update({
      where: { id: userId },
      data: { isActive: false }
    });

    console.log('✅ User deleted:', userToDelete.email);

    res.json({ success: true });

  } catch (error) {
    console.error('❌ Delete user error:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// COMPANY ENDPOINTS

// Get company info
app.get('/api/companies/info', authenticateToken, async (req, res) => {
  try {
    const company = await prisma.company.findUnique({
      where: { id: req.user.company_id }
    });
    
    if (!company) {
      return res.status(404).json({ error: 'Company not found' });
    }
    
    res.json({
      company: {
        id: company.id,
        name: company.name,
        code: company.code,
        subscription_tier: company.subscription_tier,
        max_users: company.max_users,
        low_stock_threshold: company.low_stock_threshold || 5
      }
    });
  } catch (error) {
    console.error('❌ Get company error:', error);
    res.status(500).json({ error: 'Failed to fetch company info' });
  }
});

// Update company low stock threshold
app.put('/api/companies/threshold', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { lowStockThreshold } = req.body;
    
    if (lowStockThreshold === undefined) {
      return res.status(400).json({ error: 'lowStockThreshold is required' });
    }

    const company = await prisma.company.update({
      where: { id: req.user.company_id },
      data: { low_stock_threshold: parseInt(lowStockThreshold) }
    });

    console.log('✅ Company threshold updated:', company.name);

    res.json({
      id: company.id,
      name: company.name,
      code: company.code,
      subscription_tier: company.subscription_tier,
      max_users: company.max_users,
      low_stock_threshold: company.low_stock_threshold
    });
  } catch (error) {
    console.error('❌ Update company threshold error:', error);
    res.status(500).json({ error: 'Failed to update company threshold' });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('❌ Unhandled error:', err);
  res.status(500).json({ 
    error: 'Internal server error',
    timestamp: new Date().toISOString()
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ 
    error: 'Endpoint not found',
    path: req.originalUrl,
    timestamp: new Date().toISOString()
  });
});

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  console.log(`👋 Received ${signal}. Shutting down gracefully...`);
  
  try {
    await prisma.$disconnect();
    console.log('📊 Database disconnected');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
};

// Add this new endpoint to your server.js file, after the existing user deletion endpoint

// Delete company (Admin only) - DANGEROUS OPERATION
app.delete('/api/companies/delete', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { companyId, confirmationText } = req.body;
    
    if (!companyId || !confirmationText) {
      return res.status(400).json({ error: 'Company ID and confirmation text are required' });
    }

    // Verify the company ID matches the user's company
    if (companyId !== req.user.company_id) {
      return res.status(403).json({ error: 'Cannot delete a different company' });
    }

    // Verify confirmation text
    const expectedText = `I am sure I want to delete ${req.user.company.name}`;
    if (confirmationText !== expectedText) {
      return res.status(400).json({ error: 'Confirmation text does not match' });
    }

    console.log(`🗑️ DANGER: Admin ${req.user.email} is deleting company: ${req.user.company.name}`);

    // Delete company and all associated data in transaction
    await prisma.$transaction(async (prisma) => {
      // Delete all activities
      await prisma.activity.deleteMany({
        where: { company_id: companyId }
      });

      // Delete all items
      await prisma.item.deleteMany({
        where: { company_id: companyId }
      });

      // Delete all invites
      await prisma.invite.deleteMany({
        where: { company_id: companyId }
      });

      // Delete all users
      await prisma.user.deleteMany({
        where: { company_id: companyId }
      });

      // Finally delete the company
      await prisma.company.delete({
        where: { id: companyId }
      });
    });

    console.log(`✅ Company deleted: ${req.user.company.name}`);

    res.json({ success: true, message: 'Company and all associated data deleted successfully' });

  } catch (error) {
    console.error('❌ Delete company error:', error);
    res.status(500).json({ error: 'Failed to delete company' });
  }
});

// Permanently delete user (Admin only) - UPDATED to require confirmation
app.delete('/api/users/delete-permanent', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { userId, confirmationText } = req.body;
    
    if (!userId || !confirmationText) {
      return res.status(400).json({ error: 'User ID and confirmation text are required' });
    }

    // Don't allow deleting yourself
    if (userId === req.user.id) {
      return res.status(400).json({ error: 'Cannot delete your own account' });
    }

    // Check if user exists and belongs to the same company
    const userToDelete = await prisma.user.findFirst({
      where: { 
        id: userId,
        company_id: req.user.company_id 
      }
    });

    if (!userToDelete) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Verify confirmation text
    const expectedText = `I am sure I want to delete ${userToDelete.name}`;
    if (confirmationText !== expectedText) {
      return res.status(400).json({ error: 'Confirmation text does not match' });
    }

    console.log(`🗑️ Admin ${req.user.email} is permanently deleting user: ${userToDelete.email}`);

    // Permanently delete user and reassign their activities
    await prisma.$transaction(async (prisma) => {
      // Update activities to remove user reference but keep the activity
      await prisma.activity.updateMany({
        where: { user_id: userId },
        data: { 
          user_id: req.user.id, // Reassign to the admin who deleted them
          user_name: `${userToDelete.name} (deleted by ${req.user.name})`
        }
      });

      // Delete the user
      await prisma.user.delete({
        where: { id: userId }
      });
    });

    console.log(`✅ User permanently deleted: ${userToDelete.email}`);

    res.json({ success: true });

  } catch (error) {
    console.error('❌ Delete user error:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🗄️  Database: Connected to Railway PostgreSQL`);
  console.log(`🌐 Health check: http://localhost:${PORT}/health`);
  console.log(`🔗 Invite system: ENABLED`);
});

// Handle server errors
server.on('error', (error) => {
  console.error('❌ Server error:', error);
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  gracefulShutdown('uncaughtException');
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  gracefulShutdown('unhandledRejection');
});