require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { PrismaClient } = require('@prisma/client');

const app = express();
const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development' ? ['query', 'info', 'warn', 'error'] : ['error'],
});
const PORT = process.env.PORT || 3000;

// Health check for Railway
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Middleware
app.use(cors({
  origin: process.env.NODE_ENV === 'production' 
    ? [process.env.FRONTEND_URL, /\.railway\.app$/] 
    : ['http://localhost:3000', 'http://localhost:8080', 'http://127.0.0.1:3000'],
  credentials: true
}));

app.use(express.json({ limit: '10mb' }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Test endpoint
app.get('/', (req, res) => {
  res.json({ 
    message: 'Inventory Pro API - Railway Deployment',
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString()
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
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    
    // Check password
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
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
        max_users: user.company.max_users
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
          max_users: 50
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
        max_users: result.company.max_users
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
      updated_at: item.updated_at.toISOString()
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
      updated_at: item.updated_at.toISOString()
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
      updated_at: item.updated_at.toISOString()
    });
  } catch (error) {
    console.error('❌ Update item error:', error);
    res.status(500).json({ error: 'Failed to update item' });
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
      updated_at: item.updated_at.toISOString()
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
      created_at: activity.created_at.toISOString()
    }));
    
    res.json(formattedActivities);
  } catch (error) {
    console.error('❌ Get activities error:', error);
    res.status(500).json({ error: 'Failed to fetch activities' });
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

// Invite user
app.post('/api/users/invite', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }
    
    const { email, name, role } = req.body;
    
    if (!email || !name || !role) {
      return res.status(400).json({ error: 'Email, name, and role are required' });
    }
    
    const normalizedEmail = email.toLowerCase().trim();
    
    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email: normalizedEmail }
    });
    
    if (existingUser) {
      return res.status(400).json({ error: 'User with this email already exists' });
    }
    
    // For demo purposes, create user with temporary password
    // In production, you'd send an invitation email
    const tempPassword = Math.random().toString(36).slice(-8);
    const hashedPassword = await bcrypt.hash(tempPassword, 12);
    
    const newUser = await prisma.user.create({
      data: {
        email: normalizedEmail,
        name: name.trim(),
        password: hashedPassword,
        role: role,
        company_id: req.user.company_id,
        isActive: true
      }
    });
    
    console.log('✅ User invited:', newUser.email);
    
    // In production, you'd send an actual email here
    res.json({
      success: true,
      message: 'Invitation sent successfully',
      invitationId: newUser.id,
      emailSent: true,
      emailMethod: 'demo',
      temporaryPassword: tempPassword // Remove this in production
    });
  } catch (error) {
    console.error('❌ Invite user error:', error);
    res.status(500).json({ error: 'Failed to invite user' });
  }
});

// Delete user
app.delete('/api/users/delete', authenticateToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }
    
    const { userId } = req.body;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }
    
    if (userId === req.user.id) {
      return res.status(400).json({ error: 'Cannot delete yourself' });
    }
    
    const userToDelete = await prisma.user.findFirst({
      where: { 
        id: userId,
        company_id: req.user.company_id 
      }
    });
    
    if (!userToDelete) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    await prisma.user.delete({
      where: { id: userId }
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
        max_users: company.max_users
      }
    });
  } catch (error) {
    console.error('❌ Get company error:', error);
    res.status(500).json({ error: 'Failed to fetch company info' });
  }
});

// ANALYTICS ENDPOINTS

// Get analytics
app.get('/api/analytics', authenticateToken, async (req, res) => {
  try {
    const [
      totalItems,
      totalQuantity,
      lowStockItems,
      outOfStockItems,
      recentActivities
    ] = await Promise.all([
      prisma.item.count({
        where: { company_id: req.user.company_id }
      }),
      prisma.item.aggregate({
        where: { company_id: req.user.company_id },
        _sum: { quantity: true }
      }),
      prisma.item.count({
        where: { 
          company_id: req.user.company_id,
          quantity: { gt: 0, lte: 5 }
        }
      }),
      prisma.item.count({
        where: { 
          company_id: req.user.company_id,
          quantity: 0
        }
      }),
      prisma.activity.count({
        where: {
          company_id: req.user.company_id,
          created_at: { gte: new Date(Date.now() - 24 * 60 * 60 * 1000) }
        }
      })
    ]);
    
    res.json({
      totalItems,
      totalQuantity: totalQuantity._sum.quantity || 0,
      lowStockItems,
      outOfStockItems,
      recentActivities
    });
  } catch (error) {
    console.error('❌ Get analytics error:', error);
    res.status(500).json({ error: 'Failed to fetch analytics' });
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

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🗄️  Database: Connected to Railway PostgreSQL`);
  console.log(`🌐 Health check: http://localhost:${PORT}/health`);
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
