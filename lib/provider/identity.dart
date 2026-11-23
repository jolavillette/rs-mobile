import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:retroshare/model/http_exception.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'dart:async' show unawaited;
import 'package:shared_preferences/shared_preferences.dart';

/// The active identity, kept across restarts. Own identity ids are unique to
/// a node, so a value saved by another node matches none of ours.
const _activeIdentityKey = 'active_identity_id';

class Identities with ChangeNotifier {
  List<Identity> _ownidentities = [];
  Identity? _selected;
  AuthToken? _authToken;
  String? _pgpPassword;
  set authToken(AuthToken? authToken) {
    _authToken = authToken;
  }
  set pgpPassword(String? pgpPassword) {
    _pgpPassword = pgpPassword;
  }

  AuthToken? get authToken => _authToken;

  List<Identity> get ownIdentity => _ownidentities;
  Identity? _currentIdentity;
  Identity? get currentIdentity => _currentIdentity;

  Future<void> fetchOwnidenities() async {
    if (_authToken == null) {
      return;
    }
    _ownidentities = await getOwnIdentities(_authToken!);
    // Keep the current and the selected identity while they are still ours:
    // this runs again while the Change Identity screen is open, and moving
    // both back to the first identity undid the user's choice.
    Identity? stillOwn(Identity? id) => id == null
        ? null
        : _ownidentities.where((e) => e.mId == id.mId).firstOrNull;
    final savedId =
        (await SharedPreferences.getInstance()).getString(_activeIdentityKey);
    final saved =
        _ownidentities.where((e) => e.mId == savedId).firstOrNull;
    if (_ownidentities.isNotEmpty) {
      _currentIdentity =
          stillOwn(_currentIdentity) ?? saved ?? _ownidentities[0];
      _selected = stillOwn(_selected) ?? _currentIdentity;
    }
    notifyListeners();
  }

  Identity? get selectedIdentity => _selected;

  void updateCurrentIdentity() {
    if (_selected != null) {
      _currentIdentity = _selected;
      _saveActiveIdentity();
    }
    notifyListeners();
  }

  void _saveActiveIdentity() {
    final id = _currentIdentity?.mId;
    if (id == null) return;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_activeIdentityKey, id)),
    );
  }

  void updateSelectedIdentity(Identity id) {
    if (_selected == null) {
      _selected = id;
      notifyListeners();
    } else if (_selected!.mId != id.mId) {
      _selected = id;
      notifyListeners();
    }
  }

  Future<void> createNewIdenity(Identity id, RsGxsImage image) async {
    if (_authToken == null) {
      return;
    }
    final newIdentity = await RsIdentity.createIdentity(id, image, _authToken!, _pgpPassword);
    _ownidentities.add(newIdentity);
    _currentIdentity = newIdentity;
    _selected = _currentIdentity;
    _saveActiveIdentity();
    notifyListeners();
  }

  Future<void> deleteIdentity() async {
    if (_authToken == null || _currentIdentity == null) {
      return;
    }

    try {
      final success =
          await RsIdentity.deleteIdentity(_currentIdentity!, _authToken!);
      if (!success) throw HttpException('BAD REQUEST');
      // ignore: unrelated_type_equality_checks
      _ownidentities.removeWhere((element) => element.mId == _currentIdentity);
      final random = Random();
      final randomNum = random.nextInt(_ownidentities.length);
      _currentIdentity = _ownidentities[randomNum];
      _selected = _currentIdentity;
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> updateIdentity(Identity id, RsGxsImage avatar) async {
    if (_authToken == null) {
      return;
    }

    final success = await RsIdentity.updateIdentity(id, avatar, _authToken!, _pgpPassword);
    if (!success) {
      throw 'Try Again';
    }
    
    // Refresh to get the latest details from the core (including PGP info if applicable)
    await fetchOwnidenities();
    
    // Fallback if the list didn't include the updated ID for some reason
    var found = false;
    for (var i = 0; i < _ownidentities.length; i++) {
      if (_ownidentities[i].mId == id.mId) {
        _ownidentities[i] = id;
        _currentIdentity = _ownidentities[i];
        found = true;
        break;
      }
    }
    
    if (!found) {
      _currentIdentity = id;
    }

    _selected = _currentIdentity;
    notifyListeners();
  }
}
