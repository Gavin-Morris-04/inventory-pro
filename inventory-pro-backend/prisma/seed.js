const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

async function main() {
  try {
    console.log('🌱 Starting database seeding...');

    // Check if demo company already exists
    let demoCompany = await prisma.company.findUnique({
      where: { code: 'DEMO001' }
    });

    if (!demoCompany) {
      // Create demo company
      demoCompany = await prisma.company.create({
        data: {
          name: 'Demo Company',
          code: 'DEMO001',
          subscription_tier: 'trial',
          max_users: 50,
          low_stock_threshold: 5
        }
      });
      console.log('✅ Demo company created:', demoCompany.name);
    } else {
      // Update existing company to ensure it has the new field
      demoCompany = await prisma.company.update({
        where: { code: 'DEMO001' },
        data: {
          low_stock_threshold: demoCompany.low_stock_threshold || 5
        }
      });
      console.log('ℹ️ Demo company already exists');
    }

    // Check if demo user already exists
    const demoUser = await prisma.user.findUnique({
      where: { email: 'demo@inventorypro.com' }
    });

    if (!demoUser) {
      // Create demo admin user
      const hashedPassword = await bcrypt.hash('demo123', 12);
      
      const user = await prisma.user.create({
        data: {
          email: 'demo@inventorypro.com',
          name: 'Demo Admin',
          password: hashedPassword,
          role: 'admin',
          company_id: demoCompany.id,
          isActive: true
        }
      });
      console.log('✅ Demo user created:', user.email);
    } else {
      console.log('ℹ️ Demo user already exists');
    }

    // Create some demo items
    const existingItems = await prisma.item.findMany({
      where: { company_id: demoCompany.id }
    });

    if (existingItems.length === 0) {
      const demoItems = [
        { name: 'Laptop Computer', quantity: 15, barcode: 'DEMO001-000001', low_stock_threshold: 3 },
        { name: 'Office Chair', quantity: 8, barcode: 'DEMO001-000002', low_stock_threshold: 2 },
        { name: 'Wireless Mouse', quantity: 25, barcode: 'DEMO001-000003', low_stock_threshold: 10 },
        { name: 'Monitor 24"', quantity: 12, barcode: 'DEMO001-000004', low_stock_threshold: 4 },
        { name: 'Keyboard', quantity: 20, barcode: 'DEMO001-000005', low_stock_threshold: 8 },
        { name: 'Printer Paper', quantity: 5, barcode: 'DEMO001-000006', low_stock_threshold: 10 },
        { name: 'USB Cable', quantity: 30, barcode: 'DEMO001-000007', low_stock_threshold: 15 },
        { name: 'Desk Lamp', quantity: 3, barcode: 'DEMO001-000008', low_stock_threshold: 2 }
      ];

      for (const item of demoItems) {
        await prisma.item.create({
          data: {
            ...item,
            company_id: demoCompany.id
          }
        });
      }
      console.log('✅ Demo items created');
    } else {
      console.log('ℹ️ Demo items already exist');
    }

    console.log('🎉 Database seeding completed successfully!');
    console.log('📧 Demo login: demo@inventorypro.com');
    console.log('🔑 Demo password: demo123');

  } catch (error) {
    console.error('❌ Error seeding database:', error);
    throw error;
  } finally {
    await prisma.$disconnect();
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
