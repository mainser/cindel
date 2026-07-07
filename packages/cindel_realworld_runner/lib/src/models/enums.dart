enum CustomerStatus { active, suspended, archived }

enum CustomerTier {
  standard('standard'),
  gold('gold'),
  wholesale('wholesale');

  const CustomerTier(this.code);

  final String code;
}

enum OrderStatus { draft, submitted, paid, fulfilled, cancelled }

enum PaymentMethod { card, cash, transfer }

enum PaymentStatus { authorized, captured, refunded }

enum MovementType { purchase, sale, adjustment }
