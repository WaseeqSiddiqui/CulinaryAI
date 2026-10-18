import 'package:culinary_ai/services/pandamart_adapter.dart';
import 'package:culinary_ai/services/store_selector_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final adapter = PandaMartAdapter(
    const StoreSelectorConfig({
      'external_login_hosts':
          'accounts.google.com,appleid.apple.com,facebook.com',
      'allowed_hosts': 'foodpanda.pk,www.foodpanda.pk',
      'store_path_marker': '/darkstore/',
      'search_path_template': 'search?q={query}',
      'address_unselected_text': 'New address',
      'address_unselected_markers': 'select your address',
      'address_required_markers': '',
      'store_unavailable_markers': "sorry, we can't deliver from this shop now,this shop is closed,deactivated",
    }),
  );

  test('recognizes only configured HTTPS social-login hosts', () {
    expect(
      adapter.isExternalLoginUri(
        Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
      ),
      isTrue,
    );
    expect(
      adapter.isExternalLoginUri(
        Uri.parse('https://accounts.google.com.attacker.example/login'),
      ),
      isFalse,
    );
    expect(
      adapter.isExternalLoginUri(
        Uri.parse('http://accounts.google.com/o/oauth2/v2/auth'),
      ),
      isFalse,
    );
    expect(
      adapter.isExternalLoginUri(
        Uri.parse('https://www.facebook.com/dialog/oauth'),
      ),
      isTrue,
    );
  });

  test('recognizes a selected live PandaMart address label', () {
    expect(adapter.addressTextShowsSelection('New address47 Karachi'), isTrue);
    expect(adapter.addressTextShowsSelection('New address'), isFalse);
    expect(
      adapter.addressTextShowsSelection('New address Select your address'),
      isFalse,
    );
    expect(adapter.addressTextShowsSelection('sultan town Lahore'), isTrue);
    expect(adapter.addressTextShowsSelection('F-10 Islamabad'), isTrue);
  });

  test('uses whichever PandaMart branch the user selected', () {
    expect(
      adapter.rememberStoreUri(
        Uri.parse(
          'https://www.foodpanda.pk/darkstore/d74x/pandamart-allama-iqbal-town-lhr',
        ),
      ),
      isTrue,
    );
    expect(adapter.searchUriFor('fresh milk')?.path, endsWith('/search'));
    expect(
      adapter.searchUriFor('fresh milk')?.queryParameters['q'],
      'fresh milk',
    );

    expect(
      adapter.rememberStoreUri(
        Uri.parse(
          'https://www.foodpanda.pk/darkstore/pia4/pandamart-i9-platform-fmcg-isb',
        ),
      ),
      isTrue,
    );
    expect(adapter.activeStoreUri?.path, contains('/pia4/'));
  });

  test('does not treat discovery or attacker pages as store branches', () {
    expect(
      adapter.rememberStoreUri(Uri.parse('https://www.foodpanda.pk/groceries')),
      isFalse,
    );
    expect(
      adapter.rememberStoreUri(
        Uri.parse('https://foodpanda.pk.attacker.example/darkstore/nope/store'),
      ),
      isFalse,
    );
  });

  test('accepts search results only from the requested search navigation', () {
    expect(
      adapter.searchUriMatches(
        Uri.parse(
          'https://www.foodpanda.pk/darkstore/zj7v/pandamart-pechs-khi/search?q=Granny+Smith+Apples',
        ),
        'Granny Smith Apples',
      ),
      isTrue,
    );
    expect(
      adapter.searchUriMatches(
        Uri.parse(
          'https://www.foodpanda.pk/darkstore/zj7v/pandamart-pechs-khi/search?q=Baguette',
        ),
        'Granola',
      ),
      isFalse,
    );
    expect(
      adapter.searchUriMatches(
        Uri.parse('https://foodpanda.pk.attacker.example/search?q=Granola'),
        'Granola',
      ),
      isFalse,
    );
  });

  test('blocks closed, non-deliverable, and deactivated store pages', () {
    expect(
      adapter.unavailableReasonForText(
        "Sorry, we can't deliver from this shop now.",
      ),
      isNotNull,
    );
    expect(
      adapter.unavailableReasonForText('Pandamart - DHA EME DEACTIVATED'),
      isNotNull,
    );
    expect(adapter.unavailableReasonForText('Delivery time: 25 min.'), isNull);
  });
}
