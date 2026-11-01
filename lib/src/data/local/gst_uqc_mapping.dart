/// Conservative mapping from common entered unit labels to GST UQC codes.
/// Unknown labels intentionally return null; quantities are never converted.
class GstUqcMapping {
  GstUqcMapping._();

  static const Map<String, String> _aliases = {
    'pcs': 'PCS', 'pc': 'PCS', 'piece': 'PCS', 'pieces': 'PCS',
    'nos': 'NOS', 'no': 'NOS', 'number': 'NOS', 'numbers': 'NOS',
    'kg': 'KGS', 'kgs': 'KGS', 'kilogram': 'KGS', 'kilograms': 'KGS',
    'g': 'GMS', 'gm': 'GMS', 'gms': 'GMS', 'gram': 'GMS', 'grams': 'GMS',
    'l': 'LTR', 'lt': 'LTR', 'ltr': 'LTR', 'litre': 'LTR', 'litres': 'LTR', 'liter': 'LTR', 'liters': 'LTR',
    'ml': 'MLT', 'mlt': 'MLT', 'millilitre': 'MLT', 'millilitres': 'MLT',
    'm': 'MTR', 'mtr': 'MTR', 'meter': 'MTR', 'meters': 'MTR', 'metre': 'MTR', 'metres': 'MTR',
    'box': 'BOX', 'boxes': 'BOX', 'doz': 'DOZ', 'dozen': 'DOZ', 'dozens': 'DOZ',
    'pack': 'PAC', 'packs': 'PAC', 'set': 'SET', 'sets': 'SET',
    'pair': 'PRS', 'pairs': 'PRS', 'roll': 'ROL', 'rolls': 'ROL',
    'other': 'OTH', 'others': 'OTH',
  };

  static String? fromUnit(String unit) {
    final normalized = unit.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (RegExp(r'^[A-Z]{3}$').hasMatch(unit.trim())) {
      final code = unit.trim().toUpperCase();
      if (const {'BAG','BAL','BDL','BKL','BOU','BOX','BTL','BUN','CAN','CBM','CCM','CMS','CTN','DOZ','DRM','GGK','GMS','GRS','GYD','KGS','KLR','KME','LTR','MLT','MTR','MTS','NOS','OTH','PAC','PCS','PRS','QTL','ROL','SET','SQF','SQM','SQY','TBS','TGM','THD','TON','TUB','UGS','UNT','YDS'}.contains(code)) return code;
    }
    return _aliases[normalized];
  }
}
