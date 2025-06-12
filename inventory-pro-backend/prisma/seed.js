const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Starting database seed...');

  // Create demo company
  const demoCompany = await prisma.company.upsert({
    where: { code: 'DEMO001' },
    update: {},
    create: {
      name: 'Demo Company',
      code: 'DEMO001',
      subscription_tier: 'pro',
      max_users: 100,
    },
  });

  console.log('✅ Created demo company:', demoCompany.name);

  // Create demo admin user
  const hashedPassword = await bcrypt.hash('demo123', 12);
  
  const demoAdmin = await prisma.user.upsert({
    where: { email: 'demo@inventorypro.com' },
    update: {},
    create: {
      email: 'demo@inventorypro.com',
      name: 'Demo Administrator',
      password: hashedPassword,
      role: 'admin',
      company_id: demoCompany.id,
      isActive: true,
    },
  });

  console.log('✅ Created demo admin user:', demoAdmin.email);

  // Create demo regular user
  const demoUser = await prisma.user.upsert({
    where: { email: 'user@inventorypro.com' },
    update: {},
    create: {
      email: 'user@inventorypro.com',
      name: 'Demo User',
      password: hashedPassword,
      role: 'user',
      company_id: demoCompany.id,
      isActive: true,
    },
  });

  console.log('✅ Created demo regular user:', demoUser.email);

  // Create demo items
  const demoItems = [
    {
      name: 'Wireless Headphones',
      quantity: 25,
      barcode: 'DEMO001-000001',
      company_id: demoCompany.id,
    },
    {
      name: 'USB-C Cable',
      quantity: 150,
      barcode: 'DEMO001-000002',
      company_id: demoCompany.id,
    },
    {
      name: 'Laptop Stand',
      quantity: 8,
      barcode: 'DEMO001-000003',
      company_id: demoCompany.id,
    },
    {
      name: 'Bluetooth Mouse',
      quantity: 42,
      barcode: 'DEMO001-000004',
      company_id: demoCompany.id,
    },
    {
      name: 'Phone Case',
      quantity: 3,
      barcode: 'DEMO001-000005',
      company_id: demoCompany.id,
    },
    {
      name: 'Screen Protector',
      quantity: 0,
      barcode: 'DEMO001-000006',
      company_id: demoCompany.id,
    },
  ];

  for (const itemData of demoItems) {
    const item = await prisma.item.upsert({
      where: { barcode: itemData.barcode },
      update: {},
      create: itemData,
    });

    // Create initial activity for each item
    await prisma.activity.create({
      data: {
        type: 'created',
        quantity: item.quantity,
        item_name: item.name,
        user_name: demoAdmin.name,
        company_id: demoCompany.id,
        item_id: item.id,
        user_id: demoAdmin.id,
      },
    });

    console.log(`✅ Created demo item: ${item.name}`);
  }

  console.log('🎉 Database seed completed successfully!');
  console.log('');
  console.log('Demo Login Credentials:');
  console.log('👤 Admin: demo@inventorypro.com / demo123');
  console.log('👤 User:  user@inventorypro.com / demo123');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
