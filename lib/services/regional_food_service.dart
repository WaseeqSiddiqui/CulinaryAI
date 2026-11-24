import 'package:flutter/widgets.dart';

/// Device region is a default, not a claim about the user's GPS location.
class RegionalFoodService {
  static const countries = <String, String>{
    'PK': 'Pakistan',
    'IN': 'India',
    'BD': 'Bangladesh',
    'LK': 'Sri Lanka',
    'AF': 'Afghanistan',
    'NP': 'Nepal',
    'GB': 'United Kingdom',
    'US': 'United States',
    'CA': 'Canada',
    'AU': 'Australia',
    'NZ': 'New Zealand',
    'AE': 'United Arab Emirates',
    'SA': 'Saudi Arabia',
    'TR': 'Turkey',
    'IR': 'Iran',
    'EG': 'Egypt',
    'MA': 'Morocco',
    'LB': 'Lebanon',
    'IT': 'Italy',
    'FR': 'France',
    'DE': 'Germany',
    'ES': 'Spain',
    'PT': 'Portugal',
    'GR': 'Greece',
    'CN': 'China',
    'JP': 'Japan',
    'KR': 'South Korea',
    'TH': 'Thailand',
    'VN': 'Vietnam',
    'MY': 'Malaysia',
    'ID': 'Indonesia',
    'PH': 'Philippines',
    'MX': 'Mexico',
    'BR': 'Brazil',
    'NG': 'Nigeria',
    'ZA': 'South Africa',
    'KE': 'Kenya',
    'ET': 'Ethiopia',
    'IE': 'Ireland',
    'SE': 'Sweden',
    'PL': 'Poland',
    'UA': 'Ukraine',
    'RU': 'Russia',
    'JM': 'Jamaica',
  };

  static String deviceCountry() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    return countries[code] ?? '';
  }

  static String normalizeCountry(String value) {
    final clean = value.trim();
    return countries[clean.toUpperCase()] ??
        countries.values.firstWhere(
          (name) => name.toLowerCase() == clean.toLowerCase(),
          orElse: () => clean,
        );
  }

  static List<String> suggestions(String country) => [
    'What can I cook?',
    if (country.isNotEmpty)
      'Suggest popular meals in $country'
    else
      'Suggest a quick dinner',
    'What is low stock?',
  ];
}
