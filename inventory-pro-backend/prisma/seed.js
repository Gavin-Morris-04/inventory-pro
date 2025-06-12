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
      subscription_tier: 'trial',
      max_users: 50
    }
  });

  console.log('✅ Created demo company:', demoCompany.name);

  // Hash password for demo user
  const hashedPassword = await bcrypt.hash('demo123', 12);

  // Create demo admin user
  const demoUser = await prisma.user.upsert({
    where: { email: 'demo@inventorypro.com' },
    update: {
      password: hashedPassword,
      name: 'Demo Administrator',
      role: 'admin',
      isActive: true
    },
    create: {
      email: 'demo@inventorypro.com',
      name: 'Demo Administrator',
      password: hashedPassword,
      role: 'admin',
      isActive: true,
      company_id: demoCompany.id
    }
  });

  console.log('✅ Created demo user:', demoUser.email);

  // Create sample items
  const sampleItems = [
    { name: 'Laptop Computer', quantity: 15, barcode: 'DEMO001-001' },
    { name: 'Wireless Mouse', quantity: 50, barcode: 'DEMO001-002' },
    { name: 'USB Cable', quantity: 25, barcode: 'DEMO001-003' },
    { name: 'Monitor Stand', quantity: 8, barcode: 'DEMO001-004' },
    { name: 'Keyboard', quantity: 20, barcode: 'DEMO001-005' }
  ];

  for (const itemData of sampleItems) {
    const item = await prisma.item.upsert({
      where: { barcode: itemData.barcode },
      update: {
        quantity: itemData.quantity,
        name: itemData.name
      },
      create: {
        name: itemData.name,
        quantity: itemData.quantity,
        barcode: itemData.barcode,
        company_id: demoCompany.id
      }
    });

    // Create initial activity for each item
    await prisma.activity.upsert({
      where: { 
        id: `activity-${item.id}-created`
      },
      update: {},
      create: {
        id: `activity-${item.id}-created`,
        type: 'created',
        quantity: item.quantity,
        item_name: item.name,
        user_name: demoUser.name,
        company_id: demoCompany.id,
        item_id: item.id,
        user_id: demoUser.id
      }
    });

    console.log(`✅ Created item: ${item.name} (${item.quantity} units)`);
  }

  console.log('🎉 Database seeded successfully!');
  console.log('📱 You can now login with:');
  console.log('   Email: demo@inventorypro.com');
  console.log('   Password: demo123');
}

main()
  .catch((e) => {
    console.error('❌ Seed error:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
