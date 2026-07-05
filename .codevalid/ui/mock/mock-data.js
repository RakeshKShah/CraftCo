/**
 * mock-data.js
 * Static mock data returned by the mock API server.
 * Matches the Product and User shapes used in the frontend.
 */

export const MOCK_PRODUCTS = [
  {
    id: "prod-1",
    title: "Silver Leaf Earrings",
    description: "Handcrafted sterling silver earrings shaped like delicate leaves.",
    category: "jewelry",
    price_cents: 4500,
    stock_qty: 10,
    photos: [],
    status: "active",
    store_name: "Silver & Stone",
  },
  {
    id: "prod-2",
    title: "Terracotta Bowl",
    description: "Hand-thrown terracotta bowl, food-safe glaze.",
    category: "ceramics",
    price_cents: 3200,
    stock_qty: 5,
    photos: [],
    status: "active",
    store_name: "Clay Days",
  },
  {
    id: "prod-3",
    title: "Woven Linen Tote",
    description: "Sturdy hand-woven tote bag made from natural linen.",
    category: "textiles",
    price_cents: 5800,
    stock_qty: 8,
    photos: [],
    status: "active",
    store_name: "Thread & Needle",
  },
  {
    id: "prod-4",
    title: "Copper Ring",
    description: "Hammered copper band with adjustable sizing.",
    category: "jewelry",
    price_cents: 2200,
    stock_qty: 20,
    photos: [],
    status: "active",
    store_name: "Metalworks Studio",
  },
];

export const MOCK_USERS = {
  buyer: {
    id: "user-buyer-1",
    email: "buyer@craftco.com",
    role: "BUYER",
    status: "ACTIVE",
  },
  seller: {
    id: "user-seller-1",
    email: "seller@craftco.com",
    role: "SELLER",
    status: "ACTIVE",
    sellerProfile: {
      id: "sp-1",
      storeName: "Silver & Stone",
      bio: "Crafting silver jewelry since 2010.",
    },
  },
  admin: {
    id: "user-admin-1",
    email: "admin@craftco.com",
    role: "ADMIN",
    status: "ACTIVE",
  },
};

export const MOCK_ORDERS = [
  {
    id: "order-1",
    status: "CONFIRMED",
    total_cents: 4500,
    created_at: "2024-01-15T10:00:00Z",
    items: [
      {
        id: "item-1",
        product_id: "prod-1",
        qty: 1,
        unit_price_cents: 4500,
        product: MOCK_PRODUCTS[0],
      },
    ],
  },
];

export const MOCK_AUTH_TOKENS = {
  "buyer@craftco.com": "mock-jwt-buyer-token",
  "seller@craftco.com": "mock-jwt-seller-token",
  "admin@craftco.com": "mock-jwt-admin-token",
};

export const MOCK_SELLER_STATS = {
  total_revenue_cents: 125000,
  total_orders: 28,
  active_products: 4,
};
